#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import Testing
@testable import ScannerCore

@Test func posixProbeSeesAnOpenLoopbackPort() async throws {
    // Requirements 6.4 and 7.4
    let server = try LoopbackServer()
    defer { server.close() }
    let result = await POSIXTCPProbe().connect(
        host: address("127.0.0.1"),
        port: server.port,
        timeout: .milliseconds(500)
    )
    guard case .open = result else {
        Issue.record("expected an open port, got \(result)")
        return
    }
}

@Test func posixProbeSeesARefusedPort() async throws {
    // Requirement 6.5
    let port = try LoopbackServer.closedPort()
    let result = await POSIXTCPProbe().connect(
        host: address("127.0.0.1"),
        port: port,
        timeout: .milliseconds(500)
    )
    guard case .refused = result else {
        Issue.record("expected a refusal, got \(result)")
        return
    }
}

private final class LoopbackServer {
    private let descriptor: Int32
    let port: UInt16

    init() throws {
        let fileDescriptor = socket(AF_INET, BSDSocket.stream, 0)
        if fileDescriptor < 0 { throw POSIXError(.EIO) }
        var reuse: Int32 = 1
        _ = setsockopt(fileDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: IPv4(raw: 0x7F00_0001).raw.bigEndian)
        let bound = Self.bind(fileDescriptor, address: &address)
        if bound != 0 || listen(fileDescriptor, 1) != 0 {
            _ = BSDSocket.close(fileDescriptor)
            throw POSIXError(.EIO)
        }
        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = Self.socketName(fileDescriptor, address: &boundAddress, length: &length)
        if named != 0 {
            _ = BSDSocket.close(fileDescriptor)
            throw POSIXError(.EIO)
        }
        descriptor = fileDescriptor
        port = UInt16(bigEndian: boundAddress.sin_port)
    }

    private static func bind(_ fileDescriptor: Int32, address: inout sockaddr_in) -> Int32 {
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                BSDSocket.bind(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private static func socketName(
        _ fileDescriptor: Int32,
        address: inout sockaddr_in,
        length: inout socklen_t
    ) -> Int32 {
        withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(fileDescriptor, socketAddress, &length)
            }
        }
    }

    func close() {
        _ = BSDSocket.close(descriptor)
    }

    static func closedPort() throws -> UInt16 {
        let server = try LoopbackServer()
        let port = server.port
        server.close()
        return port
    }
}
