/// Schedules host probes, pause, resume, and cancel.
public actor ScanController {
    private let dependencies: ScanDependencies
    private var phase: ScanPhase = .idle
    private var paused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var worker: Task<Void, Never>?

    /// Creates a controller.
    ///
    /// - Parameter dependencies: ICMP, TCP, and name implementations. Tests pass fakes.
    public init(dependencies: ScanDependencies) {
        self.dependencies = dependencies
    }

    /// The current phase.
    ///
    /// - Returns: `idle`, `running`, `paused`, `cancelled`, or `completed`.
    public func currentPhase() -> ScanPhase {
        phase
    }

    /// Validates `request` and starts probing.
    ///
    /// - Parameter request: Target, ports, and acknowledgement flag.
    /// - Returns: A stream of start, per-host, and terminal events.
    /// - Throws: `ScanValidationError` when the plan is rejected or a scan is already
    ///   running or paused. A throw leaves the phase unchanged and does not call a probe.
    public func start(_ request: ScanRequest) throws -> AsyncStream<ScanEvent> {
        if phase == .running || phase == .paused {
            throw ScanValidationError.alreadyRunning
        }
        let plan = try ScanPlanner.plan(request)
        phase = .running
        paused = false
        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream()
        let dependencies = self.dependencies
        worker = Task {
            await ScanRunner.run(
                plan: plan,
                dependencies: dependencies,
                controller: self,
                continuation: continuation
            )
        }
        return stream
    }

    /// Stops scheduling hosts that have not started. In-flight probes continue.
    public func pause() {
        guard phase == .running else { return }
        phase = .paused
        paused = true
    }

    /// Continues a paused scan.
    public func resume() {
        guard phase == .paused else { return }
        phase = .running
        paused = false
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Stops scheduling and cancels the worker. Observations already yielded stay yielded.
    public func cancel() {
        guard phase == .running || phase == .paused else { return }
        phase = .cancelled
        paused = false
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        worker?.cancel()
    }

    func waitIfPaused() async -> Bool {
        if phase == .cancelled { return true }
        if !paused { return false }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if phase == .cancelled || !paused {
                continuation.resume()
            } else {
                pauseWaiters.append(continuation)
            }
        }
        return phase == .cancelled
    }

    func finish(workerCancelled: Bool) -> Bool {
        if phase == .cancelled || workerCancelled {
            phase = .cancelled
            paused = false
            worker = nil
            return true
        }
        phase = .completed
        paused = false
        worker = nil
        return false
    }
}

private enum ScanRunner {
    static func run(
        plan: ScanPlan,
        dependencies: ScanDependencies,
        controller: ScanController,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        continuation.yield(.started(hostCount: plan.hosts.count))
        var completed: [HostObservation] = []
        let limit = plan.options.maxConcurrentHosts

        await withTaskGroup(of: HostObservation?.self) { group in
            var nextIndex = 0
            var inFlight = 0

            func scheduleMore() async {
                while inFlight < limit, nextIndex < plan.hosts.count {
                    if Task.isCancelled { return }
                    if await controller.waitIfPaused() { return }
                    let host = plan.hosts[nextIndex]
                    nextIndex += 1
                    inFlight += 1
                    let ports = plan.ports
                    let options = plan.options
                    let dependencies = dependencies
                    group.addTask {
                        if Task.isCancelled { return nil }
                        return await HostScanner.scan(
                            host: host,
                            ports: ports,
                            options: options,
                            dependencies: dependencies
                        )
                    }
                }
            }

            await scheduleMore()
            while let observation = await group.next() {
                inFlight -= 1
                if let observation {
                    completed.append(observation)
                    continuation.yield(.hostCompleted(observation))
                }
                if Task.isCancelled { break }
                await scheduleMore()
            }
            group.cancelAll()
        }

        let summary = ScanSummary(observations: completed, scheduledHostCount: plan.hosts.count)
        let cancelled = await controller.finish(workerCancelled: Task.isCancelled)
        if cancelled {
            continuation.yield(.cancelled(summary: summary))
        } else {
            continuation.yield(.finished(summary: summary))
        }
        continuation.finish()
    }
}

enum HostScanner {
    static func scan(
        host: IPv4,
        ports: [UInt16],
        options: ScanOptions,
        dependencies: ScanDependencies
    ) async -> HostObservation {
        let clock = ContinuousClock()
        let origin = clock.now
        let timeout = options.probeTimeout
        let icmp = dependencies.icmp
        let tcp = dependencies.tcp
        let useICMP = options.useICMPWhenPermitted && icmp.isPermitted

        let probe = await withTaskGroup(of: ProbePiece.self) { group in
            if useICMP {
                group.addTask {
                    let result = await icmp.echo(host: host, timeout: timeout)
                    return .icmp(result)
                }
            }

            var remaining = ports.makeIterator()
            var portInFlight = 0

            func addPorts() {
                while portInFlight < 8, let port = remaining.next() {
                    portInFlight += 1
                    group.addTask {
                        if Task.isCancelled {
                            return .tcp(port, .failed)
                        }
                        let result = await tcp.connect(host: host, port: port, timeout: timeout)
                        return .tcp(port, result)
                    }
                }
            }
            addPorts()

            var icmpReply = false
            var openPorts: [UInt16] = []
            var refused = false
            var latency: Duration?

            while let piece = await group.next() {
                if case .tcp = piece {
                    portInFlight -= 1
                }
                switch piece {
                case .icmp(.replied):
                    icmpReply = true
                    if latency == nil {
                        latency = origin.duration(to: clock.now)
                    }
                case .tcp(let port, .open):
                    openPorts.append(port)
                    if latency == nil {
                        latency = origin.duration(to: clock.now)
                    }
                case .tcp(_, .refused):
                    refused = true
                    if latency == nil {
                        latency = origin.duration(to: clock.now)
                    }
                default:
                    break
                }
                addPorts()
            }

            openPorts.sort()
            let discovery: DiscoveryMethod
            if icmpReply {
                discovery = .icmp
            } else if !openPorts.isEmpty {
                discovery = .tcpOpen
            } else if refused {
                discovery = .tcpRefused
            } else {
                discovery = .none
            }
            return ProbeAccumulator(
                discovery: discovery,
                openPorts: openPorts,
                latency: discovery == .none ? nil : latency
            )
        }

        let names = await dependencies.names.resolve(host: host, timeout: options.nameBudget)
        return HostObservation(
            address: host,
            reverseDNS: names.reverseDNS,
            bonjour: names.bonjour,
            status: probe.discovery == .none ? .unresponsive : .alive,
            latency: probe.latency,
            openPorts: probe.openPorts,
            discovery: probe.discovery
        )
    }
}

private enum ProbePiece: Sendable {
    case icmp(ICMPEchoResult)
    case tcp(UInt16, TCPConnectResult)
}

private struct ProbeAccumulator: Sendable {
    var discovery: DiscoveryMethod
    var openPorts: [UInt16]
    var latency: Duration?
}
