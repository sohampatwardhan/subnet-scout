/// Whether an address is treated as private or local for the public-range gate.
public enum AddressClass: Sendable, Equatable {
    /// RFC 1918, loopback, or link-local.
    case privateLocal
    /// Every other IPv4 address, including CGNAT and documentation prefixes.
    case publicRange
}

/// Classifies IPv4 addresses for the scan acknowledgement rule.
public enum AddressScope {
    /// Classifies one address.
    ///
    /// - Parameter address: The address to classify.
    /// - Returns: `privateLocal` for `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
    ///   `127.0.0.0/8`, and `169.254.0.0/16`. Every other address is `publicRange`.
    public static func classify(_ address: IPv4) -> AddressClass {
        let raw = address.raw
        if contains(raw, network: network(10, 0, 0, 0), length: 8) { return .privateLocal }
        if contains(raw, network: network(172, 16, 0, 0), length: 12) { return .privateLocal }
        if contains(raw, network: network(192, 168, 0, 0), length: 16) { return .privateLocal }
        if contains(raw, network: network(127, 0, 0, 0), length: 8) { return .privateLocal }
        if contains(raw, network: network(169, 254, 0, 0), length: 16) { return .privateLocal }
        return .publicRange
    }

    private static func network(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> UInt32 {
        (a << 24) | (b << 16) | (c << 8) | d
    }

    private static func contains(_ raw: UInt32, network: UInt32, length: Int) -> Bool {
        let shift = 32 - length
        let mask = shift == 32 ? 0 : (UInt32.max << shift)
        return (raw & mask) == (network & mask)
    }
}
