#if os(macOS)
import Foundation

/// ICMP echo by launching `/sbin/ping`. The Mac App Sandbox often makes this unavailable.
public struct ProcessPingProbe: ICMPEchoProbing {
    public init() {}

    public var isPermitted: Bool { true }

    /// Sends one echo with `ping -c 1`.
    ///
    /// - Parameters:
    ///   - host: Address passed to `ping`.
    ///   - timeout: Converted to the `-W` wait in milliseconds.
    /// - Returns: `.replied` when `ping` exits 0, `.unavailable` when it cannot launch,
    ///   otherwise `.unresponsive`.
    public func echo(host: IPv4, timeout: Duration) async -> ICMPEchoResult {
        let milliseconds = max(ProbeTiming.milliseconds(timeout), 1)
        let started = ContinuousClock.now
        let outcome = await Task.detached {
            Self.run(host: host.description, waitMilliseconds: milliseconds)
        }.value
        switch outcome {
        case .replied:
            return .replied(latency: ContinuousClock.now - started)
        case .unresponsive:
            return .unresponsive
        case .unavailable:
            return .unavailable
        }
    }

    private enum Run: Sendable {
        case replied
        case unresponsive
        case unavailable
    }

    private static func run(host: String, waitMilliseconds: Int) -> Run {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", String(waitMilliseconds), host]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return .unavailable
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? .replied : .unresponsive
    }
}
#endif
