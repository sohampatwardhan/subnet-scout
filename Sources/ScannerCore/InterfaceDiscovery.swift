#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// One IPv4 interface address and its prefix length.
public struct NetworkInterface: Sendable, Equatable, Hashable {
    /// Kernel interface name, such as `en0` or `eth0`.
    public var name: String
    /// Assigned address.
    public var address: IPv4
    /// Prefix length derived from the netmask. Negative means the mask was not contiguous.
    public var prefixLength: Int
    /// `true` when the interface flag `IFF_LOOPBACK` is set.
    public var isLoopback: Bool

    /// Creates an interface record.
    ///
    /// - Parameters:
    ///   - name: Interface name.
    ///   - address: IPv4 address.
    ///   - prefixLength: Netmask length.
    ///   - isLoopback: Whether the interface is loopback.
    public init(name: String, address: IPv4, prefixLength: Int, isLoopback: Bool) {
        self.name = name
        self.address = address
        self.prefixLength = prefixLength
        self.isLoopback = isLoopback
    }
}

/// Supplies interface records. Tests pass a fixed list. The app uses `SystemInterfaceListing`.
public protocol InterfaceListing: Sendable {
    /// Returns the IPv4 interfaces visible to this process.
    ///
    /// - Returns: Zero or more interfaces. An empty list means no current subnet.
    func interfaces() -> [NetworkInterface]
}

/// Picks the interface whose prefix becomes the current-subnet target.
public enum InterfacePreference {
    /// Chooses the preferred interface.
    ///
    /// - Parameter interfaces: Candidates from `InterfaceListing`.
    /// - Returns: The first non-loopback private or local prefix shorter than 32,
    ///   otherwise the first other non-loopback prefix shorter than 32, otherwise `nil`.
    public static func preferred(_ interfaces: [NetworkInterface]) -> NetworkInterface? {
        let eligible = interfaces.filter { interface in
            !interface.isLoopback && (0..<32).contains(interface.prefixLength)
        }
        if let local = eligible.first(where: { AddressScope.classify($0.address) == .privateLocal }) {
            return local
        }
        return eligible.first
    }
}

/// Turns a preferred interface into target text or the not-detected message.
public struct CurrentSubnetSelection: Sendable, Equatable {
    /// CIDR text to put in the target field, or `nil` when nothing was detected.
    public var targetText: String?
    /// Failure message. `nil` when `targetText` is set.
    public var message: String?

    /// Creates a selection.
    ///
    /// - Parameters:
    ///   - targetText: CIDR to apply, or `nil` to leave the field unchanged.
    ///   - message: Text to show when no subnet was detected.
    public init(targetText: String?, message: String?) {
        self.targetText = targetText
        self.message = message
    }
}

/// Current-subnet helper used by the app.
public enum CurrentSubnet {
    /// Message required when no eligible interface exists.
    public static let notDetectedMessage = "No local IPv4 subnet detected."

    /// Selects a CIDR from interfaces.
    ///
    /// - Parameter interfaces: Interfaces to consider.
    /// - Returns: CIDR text, or `notDetectedMessage` with a nil target.
    public static func select(from interfaces: [NetworkInterface]) -> CurrentSubnetSelection {
        guard let chosen = InterfacePreference.preferred(interfaces) else {
            return CurrentSubnetSelection(targetText: nil, message: notDetectedMessage)
        }
        return CurrentSubnetSelection(targetText: cidr(for: chosen), message: nil)
    }

    /// Formats an interface as CIDR text.
    ///
    /// - Parameter interface: Interface with a prefix length from 0 through 32.
    /// - Returns: The network address and prefix, such as `192.168.1.0/24`.
    public static func cidr(for interface: NetworkInterface) -> String {
        let length = min(max(interface.prefixLength, 0), 32)
        let hostBits = 32 - length
        let mask: UInt32 = length == 0 ? 0 : (UInt32.max << hostBits)
        let network = IPv4(raw: interface.address.raw & mask)
        return "\(network.description)/\(length)"
    }
}

/// Reads IPv4 interfaces with `getifaddrs`.
public struct SystemInterfaceListing: InterfaceListing {
    public init() {}

    /// Lists IPv4 interfaces.
    ///
    /// - Returns: One record per IPv4 address. Returns an empty array when `getifaddrs` fails.
    public func interfaces() -> [NetworkInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [NetworkInterface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int(current.pointee.ifa_flags)
            guard let addressPointer = current.pointee.ifa_addr,
                  addressPointer.pointee.sa_family == sa_family_t(AF_INET),
                  let maskPointer = current.pointee.ifa_netmask else {
                continue
            }
            let rawAddress = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            let rawMask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            let name = BSDSocket.string(current.pointee.ifa_name)
            found.append(
                NetworkInterface(
                    name: name,
                    address: IPv4(raw: UInt32(bigEndian: rawAddress)),
                    prefixLength: Self.prefixLength(UInt32(bigEndian: rawMask)),
                    isLoopback: (flags & Int(IFF_LOOPBACK)) != 0
                )
            )
        }
        return found
    }

    private static func prefixLength(_ mask: UInt32) -> Int {
        var count = 0
        var seenZero = false
        var bit: UInt32 = 1 << 31
        for _ in 0..<32 {
            if mask & bit == 0 {
                seenZero = true
            } else if seenZero {
                return -1
            } else {
                count += 1
            }
            if bit == 1 { break }
            bit >>= 1
        }
        return count
    }
}
