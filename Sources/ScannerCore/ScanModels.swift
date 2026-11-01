/// Knobs for one scan.
public struct ScanOptions: Sendable, Equatable {
    /// Maximum hosts with probes in flight. Must be in `1...256`.
    public var maxConcurrentHosts: Int
    /// Budget for each ICMP or TCP probe.
    public var probeTimeout: Duration
    /// Maximum addresses a target may expand to.
    public var hostCap: Int
    /// When `false`, the controller does not call the ICMP probe.
    public var useICMPWhenPermitted: Bool
    /// Budget for reverse DNS and Bonjour lookup of one host.
    public var nameBudget: Duration

    /// Creates scan options.
    ///
    /// - Parameters:
    ///   - maxConcurrentHosts: Hosts probed at once. Default 32.
    ///   - probeTimeout: Per-probe timeout. Default 1 second.
    ///   - hostCap: Expansion cap. Default 4096.
    ///   - useICMPWhenPermitted: Whether to send ICMP when the probe allows it.
    ///   - nameBudget: Name-lookup budget. Default 2 seconds.
    public init(
        maxConcurrentHosts: Int = 32,
        probeTimeout: Duration = .seconds(1),
        hostCap: Int = 4096,
        useICMPWhenPermitted: Bool = true,
        nameBudget: Duration = .seconds(2)
    ) {
        self.maxConcurrentHosts = maxConcurrentHosts
        self.probeTimeout = probeTimeout
        self.hostCap = hostCap
        self.useICMPWhenPermitted = useICMPWhenPermitted
        self.nameBudget = nameBudget
    }
}

/// Input for one scan.
public struct ScanRequest: Sendable, Equatable {
    /// Single address, inclusive range, or CIDR prefix.
    public var targetText: String
    /// Port list. Empty selects the common preset.
    public var portText: String
    /// Concurrency, timeouts, and the host cap.
    public var options: ScanOptions
    /// `true` after the person accepts a public-range warning.
    public var acknowledgePublicRange: Bool

    /// Creates a scan request.
    ///
    /// - Parameters:
    ///   - targetText: Address, range, or CIDR text.
    ///   - portText: Port list text. Default empty, which selects common ports.
    ///   - options: Scan knobs.
    ///   - acknowledgePublicRange: Whether a public range may be probed.
    public init(
        targetText: String,
        portText: String = "",
        options: ScanOptions = ScanOptions(),
        acknowledgePublicRange: Bool = false
    ) {
        self.targetText = targetText
        self.portText = portText
        self.options = options
        self.acknowledgePublicRange = acknowledgePublicRange
    }
}

/// A validated expansion of a `ScanRequest`.
public struct ScanPlan: Sendable, Equatable {
    /// Trimmed target text.
    public var targetText: String
    /// Addresses in ascending numeric order.
    public var hosts: [IPv4]
    /// Ports to probe, in list order.
    public var ports: [UInt16]
    /// Options copied from the request.
    public var options: ScanOptions

    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - targetText: Trimmed target.
    ///   - hosts: Expanded addresses.
    ///   - ports: Ports to probe.
    ///   - options: Scan knobs.
    public init(targetText: String, hosts: [IPv4], ports: [UInt16], options: ScanOptions) {
        self.targetText = targetText
        self.hosts = hosts
        self.ports = ports
        self.options = options
    }
}

/// How the controller learned that a host was alive.
public enum DiscoveryMethod: String, Sendable, Equatable, Codable {
    /// An ICMP echo reply arrived.
    case icmp
    /// At least one TCP handshake completed.
    case tcpOpen
    /// At least one TCP probe was refused and none completed a handshake.
    case tcpRefused
    /// No alive evidence.
    case none
}

/// Whether a finished host answered.
public enum HostStatus: String, Sendable, Equatable, Comparable, Codable {
    case alive
    case unresponsive

    public static func < (lhs: HostStatus, rhs: HostStatus) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .alive: 0
        case .unresponsive: 1
        }
    }
}

/// One finished host. There is no MAC address field.
public struct HostObservation: Sendable, Equatable, Identifiable {
    /// Dotted address, unique inside one scan.
    public var id: String { address.description }
    /// Probed address.
    public var address: IPv4
    /// Reverse DNS name, when the resolver returned one.
    public var reverseDNS: String?
    /// Bonjour instance name, when the browser matched this address.
    public var bonjour: String?
    /// Alive or unresponsive.
    public var status: HostStatus
    /// Time from the start of this host's probes to the first alive evidence.
    public var latency: Duration?
    /// TCP ports whose handshake completed, in ascending order.
    public var openPorts: [UInt16]
    /// Which evidence marked the host alive.
    public var discovery: DiscoveryMethod

    /// Name shown in the table. Bonjour wins when it is non-empty.
    public var displayName: String? {
        if let bonjour, !bonjour.isEmpty { return bonjour }
        if let reverseDNS, !reverseDNS.isEmpty { return reverseDNS }
        return nil
    }

    /// Creates an observation.
    ///
    /// - Parameters:
    ///   - address: Probed address.
    ///   - reverseDNS: Reverse DNS name, or `nil`.
    ///   - bonjour: Bonjour name, or `nil`.
    ///   - status: Alive or unresponsive.
    ///   - latency: Time to first alive evidence, or `nil`.
    ///   - openPorts: Ports that completed a handshake.
    ///   - discovery: Evidence that marked the host alive.
    public init(
        address: IPv4,
        reverseDNS: String?,
        bonjour: String?,
        status: HostStatus,
        latency: Duration?,
        openPorts: [UInt16],
        discovery: DiscoveryMethod
    ) {
        self.address = address
        self.reverseDNS = reverseDNS
        self.bonjour = bonjour
        self.status = status
        self.latency = latency
        self.openPorts = openPorts
        self.discovery = discovery
    }
}

/// Lifecycle of `ScanController`.
public enum ScanPhase: String, Sendable, Equatable {
    case idle
    case running
    case paused
    case cancelled
    case completed
}

/// Counts kept when a scan finishes or is cancelled.
public struct ScanSummary: Sendable, Equatable {
    /// Observations yielded before the scan stopped.
    public var observations: [HostObservation]
    /// Hosts the plan contained, including ones never started.
    public var scheduledHostCount: Int

    /// Creates a summary.
    ///
    /// - Parameters:
    ///   - observations: Rows already produced.
    ///   - scheduledHostCount: Hosts in the plan.
    public init(observations: [HostObservation], scheduledHostCount: Int) {
        self.observations = observations
        self.scheduledHostCount = scheduledHostCount
    }
}

/// Events from a running scan.
public enum ScanEvent: Sendable, Equatable {
    /// The plan was accepted and probing has started.
    case started(hostCount: Int)
    /// One host finished.
    case hostCompleted(HostObservation)
    /// Every scheduled host finished.
    case finished(summary: ScanSummary)
    /// The caller cancelled, or the worker was cancelled.
    case cancelled(summary: ScanSummary)
}
