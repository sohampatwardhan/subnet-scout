#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reverse DNS through `getnameinfo`.
public struct SystemReverseDNSResolver: ReverseDNSResolving {
    public init() {}

    /// Looks up a PTR name.
    ///
    /// `getnameinfo` itself is not cancellable. When the timeout wins, this method
    /// returns `nil` and the system call may finish later in the background.
    ///
    /// - Parameters:
    ///   - host: Address to reverse.
    ///   - timeout: How long to wait before returning `nil`.
    /// - Returns: The hostname, or `nil` when the lookup fails, returns the numeric
    ///   address, or exceeds `timeout`.
    public func lookup(host: IPv4, timeout: Duration) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                Self.blockingLookup(host)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func blockingLookup(_ host: IPv4) -> String? {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: host.raw.bigEndian)
        var buffer = [CChar](repeating: 0, count: 1024)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getnameinfo(
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }
        guard result == 0 else { return nil }
        let name = BSDSocket.string(buffer)
        if name.isEmpty || name == host.description { return nil }
        return name
    }
}
