/// Selects the probe implementations compiled into this process.
public enum PlatformProbes {
    /// TCP probe for this process.
    ///
    /// - Returns: `NetworkTCPProbe` when Network.framework is linked, otherwise `POSIXTCPProbe`.
    public static func tcp() -> any TCPConnectProbing {
        #if canImport(Network)
        NetworkTCPProbe()
        #else
        POSIXTCPProbe()
        #endif
    }

    /// ICMP probe for this process.
    ///
    /// - Returns: `ProcessPingProbe` on macOS, otherwise a probe with `isPermitted == false`.
    public static func icmp() -> any ICMPEchoProbing {
        #if os(macOS)
        ProcessPingProbe()
        #else
        UnavailableICMPProbe()
        #endif
    }

    /// Bonjour resolver for this process.
    ///
    /// - Parameter serviceTypes: Types to browse on Apple. Ignored when Bonjour is unavailable.
    /// - Returns: A browser on Apple, or a resolver that always returns `nil`.
    public static func bonjour(
        serviceTypes: [String] = BonjourServiceTypes.defaults
    ) -> any BonjourNameResolving {
        #if canImport(Network)
        NetworkBonjourResolver(serviceTypes: serviceTypes)
        #else
        UnavailableBonjourResolver()
        #endif
    }
}
