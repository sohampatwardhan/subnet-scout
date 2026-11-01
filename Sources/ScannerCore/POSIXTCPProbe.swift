#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// TCP connect probe using non-blocking sockets and `poll`.
public struct POSIXTCPProbe: TCPConnectProbing {
    public init() {}

    /// Connects to one TCP port.
    ///
    /// - Parameters:
    ///   - host: Address to probe.
    ///   - port: TCP port.
    ///   - timeout: Maximum time to wait for the handshake or a refusal.
    /// - Returns: `open` when the handshake completes, `refused` for `ECONNREFUSED`,
    ///   `timedOut` when `poll` reaches the timeout, otherwise `failed`.
    public func connect(host: IPv4, port: UInt16, timeout: Duration) async -> TCPConnectResult {
        let timeoutMilliseconds = max(ProbeTiming.milliseconds(timeout), 1)
        let started = ContinuousClock.now
        let outcome = await Task.detached {
            Self.blockingConnect(host: host, port: port, timeoutMilliseconds: timeoutMilliseconds)
        }.value
        let latency = ContinuousClock.now - started
        switch outcome {
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

    private enum SocketOutcome: Sendable {
        case open
        case refused
        case timedOut
        case failed
    }

    private static func blockingConnect(host: IPv4, port: UInt16, timeoutMilliseconds: Int) -> SocketOutcome {
        let descriptor = socket(AF_INET, BSDSocket.stream, 0)
        if descriptor < 0 { return .failed }
        defer { _ = BSDSocket.close(descriptor) }

        let flags = fcntl(descriptor, F_GETFL, 0)
        if flags < 0 { return .failed }
        if fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0 { return .failed }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: host.raw.bigEndian)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                BSDSocket.connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult == 0 { return .open }
        if errno != EINPROGRESS {
            return errno == ECONNREFUSED ? .refused : .failed
        }

        var descriptorSet = pollfd()
        descriptorSet.fd = descriptor
        descriptorSet.events = Int16(POLLOUT)
        descriptorSet.revents = 0
        let ready = poll(&descriptorSet, 1, Int32(timeoutMilliseconds))
        if ready == 0 { return .timedOut }
        if ready < 0 { return .failed }

        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        let optionResult = getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length)
        if optionResult != 0 { return .failed }
        if socketError == 0 { return .open }
        if socketError == ECONNREFUSED { return .refused }
        if socketError == ETIMEDOUT { return .timedOut }
        return .failed
    }
}
