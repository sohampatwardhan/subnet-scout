/// An IPv4 address stored in host byte order.
public struct IPv4: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    /// The address as a host-order 32-bit value.
    public let raw: UInt32

    /// Creates an address from a host-order value.
    ///
    /// - Parameter raw: Host-order bits. `0x7F000001` is `127.0.0.1`.
    public init(raw: UInt32) {
        self.raw = raw
    }

    /// Creates an address from dotted decimal text.
    ///
    /// - Parameter dotted: Four decimal octets separated by `.`, such as `192.168.1.10`.
    /// - Returns: The address, or `nil` when `dotted` is not a strict IPv4 literal.
    ///   Octets outside `0...255` and leading zeros are rejected.
    public init?(dotted: String) {
        let parts = dotted.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard part.count <= 3 else { return nil }
            if part.count > 1, part.first == "0" { return nil }
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        self.raw = value
    }

    /// The dotted-decimal form, such as `192.168.1.10`.
    public var description: String {
        let octet0 = (raw >> 24) & 0xFF
        let octet1 = (raw >> 16) & 0xFF
        let octet2 = (raw >> 8) & 0xFF
        let octet3 = raw & 0xFF
        return "\(octet0).\(octet1).\(octet2).\(octet3)"
    }

    public static func < (lhs: IPv4, rhs: IPv4) -> Bool {
        lhs.raw < rhs.raw
    }
}
