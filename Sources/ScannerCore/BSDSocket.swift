#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum BSDSocket {
    static var stream: Int32 {
        #if canImport(Darwin)
        SOCK_STREAM
        #else
        Int32(SOCK_STREAM.rawValue)
        #endif
    }

    static func close(_ descriptor: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.close(descriptor)
        #else
        Glibc.close(descriptor)
        #endif
    }

    static func connect(
        _ descriptor: Int32,
        _ address: UnsafePointer<sockaddr>,
        _ length: socklen_t
    ) -> Int32 {
        #if canImport(Darwin)
        Darwin.connect(descriptor, address, length)
        #else
        Glibc.connect(descriptor, address, length)
        #endif
    }

    static func bind(
        _ descriptor: Int32,
        _ address: UnsafePointer<sockaddr>,
        _ length: socklen_t
    ) -> Int32 {
        #if canImport(Darwin)
        Darwin.bind(descriptor, address, length)
        #else
        Glibc.bind(descriptor, address, length)
        #endif
    }

    static func string(_ pointer: UnsafePointer<CChar>) -> String {
        var length = 0
        while pointer[length] != 0 {
            length += 1
        }
        let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: length)
        return String(decoding: bytes, as: UTF8.self)
    }

    static func string(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
