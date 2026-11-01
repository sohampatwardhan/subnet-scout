/// Outcome of one TCP connect attempt.
public enum TCPConnectResult: Sendable, Equatable {
    /// The handshake completed.
    case open(latency: Duration)
    /// The peer refused the connection.
    case refused(latency: Duration)
    /// The probe stopped because its timeout elapsed.
    case timedOut
    /// The probe could not be attempted or ended for another reason.
    case failed
}

/// A TCP connect probe with a caller-supplied timeout.
public protocol TCPConnectProbing: Sendable {
    /// Tries to connect to one TCP port.
    ///
    /// - Parameters:
    ///   - host: Address to probe.
    ///   - port: TCP port.
    ///   - timeout: Maximum time to wait for a handshake or a refusal.
    /// - Returns: Whether the port is open, refused, timed out, or failed.
    func connect(host: IPv4, port: UInt16, timeout: Duration) async -> TCPConnectResult
}

/// Outcome of one ICMP echo attempt.
public enum ICMPEchoResult: Sendable, Equatable {
    /// An echo reply arrived.
    case replied(latency: Duration)
    /// The probe ran and no reply arrived.
    case unresponsive
    /// This platform or sandbox cannot send ICMP echo.
    case unavailable
}

/// ICMP echo, or an explicit statement that ICMP is not permitted.
public protocol ICMPEchoProbing: Sendable {
    /// `false` on platforms that must not send ICMP. The controller then skips `echo`.
    var isPermitted: Bool { get }

    /// Sends one echo request.
    ///
    /// - Parameters:
    ///   - host: Address to probe.
    ///   - timeout: Maximum time to wait for a reply.
    /// - Returns: A reply, no reply, or `unavailable` when the probe cannot launch.
    func echo(host: IPv4, timeout: Duration) async -> ICMPEchoResult
}

/// ICMP probe used where echo is not permitted, including iOS and Linux tests.
public struct UnavailableICMPProbe: ICMPEchoProbing {
    public init() {}

    public var isPermitted: Bool { false }

    /// Reports that ICMP cannot run.
    ///
    /// - Parameters:
    ///   - host: Ignored.
    ///   - timeout: Ignored.
    /// - Returns: `.unavailable`.
    public func echo(host: IPv4, timeout: Duration) async -> ICMPEchoResult {
        .unavailable
    }
}

/// Names learned for one address.
public struct HostNames: Sendable, Equatable {
    /// Reverse DNS name, if any.
    public var reverseDNS: String?
    /// Bonjour instance name, if any.
    public var bonjour: String?

    /// Bonjour when it is non-empty, otherwise reverse DNS.
    public var displayName: String? {
        if let bonjour, !bonjour.isEmpty { return bonjour }
        if let reverseDNS, !reverseDNS.isEmpty { return reverseDNS }
        return nil
    }

    /// Creates a name pair.
    ///
    /// - Parameters:
    ///   - reverseDNS: Reverse DNS result.
    ///   - bonjour: Bonjour result.
    public init(reverseDNS: String? = nil, bonjour: String? = nil) {
        self.reverseDNS = reverseDNS
        self.bonjour = bonjour
    }
}

/// Resolves a display name for one address.
public protocol HostNameResolving: Sendable {
    /// Looks up reverse DNS and Bonjour for one host.
    ///
    /// - Parameters:
    ///   - host: Address to name.
    ///   - timeout: Budget for the lookup.
    /// - Returns: Whatever names were learned before the budget elapsed.
    func resolve(host: IPv4, timeout: Duration) async -> HostNames
}

/// Resolver that always returns empty names.
public struct EmptyNameResolver: HostNameResolving {
    public init() {}

    /// Returns empty names.
    ///
    /// - Parameters:
    ///   - host: Ignored.
    ///   - timeout: Ignored.
    /// - Returns: Names with both fields `nil`.
    public func resolve(host: IPv4, timeout: Duration) async -> HostNames {
        HostNames()
    }
}

/// Reverse DNS lookup.
public protocol ReverseDNSResolving: Sendable {
    /// Looks up the PTR name for an address.
    ///
    /// - Parameters:
    ///   - host: Address to look up.
    ///   - timeout: Budget for the lookup.
    /// - Returns: The name, or `nil` when none arrives in time.
    func lookup(host: IPv4, timeout: Duration) async -> String?
}

/// Bonjour name lookup.
public protocol BonjourNameResolving: Sendable {
    /// Returns a Bonjour instance name previously matched to this address.
    ///
    /// - Parameters:
    ///   - host: Address to match.
    ///   - timeout: Budget for a browse when the cache is cold.
    /// - Returns: The instance name, or `nil` when Bonjour is unavailable or silent.
    func lookup(host: IPv4, timeout: Duration) async -> String?
}

/// Bonjour adapter for platforms that cannot browse.
public struct UnavailableBonjourResolver: BonjourNameResolving {
    public init() {}

    /// Returns no Bonjour name.
    ///
    /// - Parameters:
    ///   - host: Ignored.
    ///   - timeout: Ignored.
    /// - Returns: `nil`.
    public func lookup(host: IPv4, timeout: Duration) async -> String? {
        nil
    }
}

/// Service types advertised in `Info.plist` and browsed on Apple platforms.
public enum BonjourServiceTypes {
    /// Keep this list identical to `NSBonjourServices` in the app Info.plist.
    public static let defaults: [String] = [
        "_http._tcp",
        "_ssh._tcp",
        "_smb._tcp",
        "_airplay._tcp",
        "_companion-link._tcp",
    ]
}

/// Runs reverse DNS and Bonjour together.
public struct CompositeHostNameResolver: HostNameResolving {
    /// Reverse DNS source.
    public var reverseDNS: any ReverseDNSResolving
    /// Bonjour source.
    public var bonjour: any BonjourNameResolving

    /// Creates a composite resolver.
    ///
    /// - Parameters:
    ///   - reverseDNS: PTR lookup.
    ///   - bonjour: Bonjour lookup. Use `UnavailableBonjourResolver` when browsing is absent.
    public init(reverseDNS: any ReverseDNSResolving, bonjour: any BonjourNameResolving) {
        self.reverseDNS = reverseDNS
        self.bonjour = bonjour
    }

    /// Resolves both sources and prefers Bonjour in `HostNames.displayName`.
    ///
    /// - Parameters:
    ///   - host: Address to name.
    ///   - timeout: Budget passed to both sources.
    /// - Returns: The names each source returned. A nil Bonjour name does not fail the lookup.
    public func resolve(host: IPv4, timeout: Duration) async -> HostNames {
        async let dns = reverseDNS.lookup(host: host, timeout: timeout)
        async let bonjourName = bonjour.lookup(host: host, timeout: timeout)
        return HostNames(reverseDNS: await dns, bonjour: await bonjourName)
    }
}

/// Probes and resolvers supplied to `ScanController`.
public struct ScanDependencies: Sendable {
    /// ICMP echo implementation.
    public var icmp: any ICMPEchoProbing
    /// TCP connect implementation.
    public var tcp: any TCPConnectProbing
    /// Hostname implementation.
    public var names: any HostNameResolving

    /// Creates a dependency bundle.
    ///
    /// - Parameters:
    ///   - icmp: ICMP probe.
    ///   - tcp: TCP probe.
    ///   - names: Name resolver.
    public init(
        icmp: any ICMPEchoProbing,
        tcp: any TCPConnectProbing,
        names: any HostNameResolving
    ) {
        self.icmp = icmp
        self.tcp = tcp
        self.names = names
    }

    /// Adapters for the platform this process is running on.
    ///
    /// - Parameter bonjourServiceTypes: Types passed to the Apple browser.
    /// - Returns: Network TCP and Bonjour on Apple, POSIX TCP elsewhere, and ICMP only on macOS.
    public static func live(
        bonjourServiceTypes: [String] = BonjourServiceTypes.defaults
    ) -> ScanDependencies {
        ScanDependencies(
            icmp: PlatformProbes.icmp(),
            tcp: PlatformProbes.tcp(),
            names: CompositeHostNameResolver(
                reverseDNS: SystemReverseDNSResolver(),
                bonjour: PlatformProbes.bonjour(serviceTypes: bonjourServiceTypes)
            )
        )
    }
}
