#if canImport(Network)
import Foundation
import Network

/// TCP connect probe using `NWConnection`.
public struct NetworkTCPProbe: TCPConnectProbing {
    public init() {}

    /// Connects with Network.framework and cancels the connection when the state settles.
    ///
    /// - Parameters:
    ///   - host: Address to probe.
    ///   - port: TCP port.
    ///   - timeout: Maximum time to wait before returning `timedOut`.
    /// - Returns: `open` on `.ready`, `refused` for `ECONNREFUSED`, otherwise timeout or failure.
    public func connect(host: IPv4, port: UInt16, timeout: Duration) async -> TCPConnectResult {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return .failed
        }
        let started = ContinuousClock.now
        let connection = NWConnection(
            host: NWEndpoint.Host(host.description),
            port: endpointPort,
            using: .tcp
        )
        let box = ConnectionBox(connection)
        let kind = await withCheckedContinuation { (continuation: CheckedContinuation<SocketKind, Never>) in
            let gate = ResumeGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resumeOnce {
                        box.cancel()
                        continuation.resume(returning: .open)
                    }
                case .waiting(let error):
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        gate.resumeOnce {
                            box.cancel()
                            continuation.resume(returning: .refused)
                        }
                    }
                case .failed(let error):
                    gate.resumeOnce {
                        box.cancel()
                        continuation.resume(returning: Self.map(error))
                    }
                case .cancelled:
                    gate.resumeOnce {
                        continuation.resume(returning: .failed)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: timeout)
                gate.resumeOnce {
                    box.cancel()
                    continuation.resume(returning: .timedOut)
                }
            }
        }
        let latency = ContinuousClock.now - started
        switch kind {
        case .open:
            return .open(latency: latency)
        case .refused:
            return .refused(latency: latency)
        case .timedOut:
            return .timedOut
        case .failed:
            return .failed
        }
    }

    private enum SocketKind: Sendable {
        case open
        case refused
        case timedOut
        case failed
    }

    private static func map(_ error: NWError) -> SocketKind {
        if case .posix(let code) = error {
            if code == .ECONNREFUSED { return .refused }
            if code == .ETIMEDOUT { return .timedOut }
        }
        return .failed
    }
}

private final class ConnectionBox: @unchecked Sendable {
    private let connection: NWConnection

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func cancel() {
        connection.cancel()
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        body()
    }
}
#endif
