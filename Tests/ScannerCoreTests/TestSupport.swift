import Foundation
import Synchronization
@testable import ScannerCore

func address(_ dotted: String) -> IPv4 {
    IPv4(dotted: dotted)!
}

func observation(
    _ dotted: String,
    name: String? = nil,
    bonjour: String? = nil,
    status: HostStatus = .alive,
    latency: Duration? = .milliseconds(5),
    ports: [UInt16] = [],
    discovery: DiscoveryMethod = .tcpOpen
) -> HostObservation {
    HostObservation(
        address: address(dotted),
        reverseDNS: name,
        bonjour: bonjour,
        status: status,
        latency: status == .unresponsive ? nil : latency,
        openPorts: ports,
        discovery: discovery
    )
}

final class ScriptedTCP: TCPConnectProbing, Sendable {
    private struct Box: Sendable {
        var result: TCPConnectResult = .timedOut
        var resultsByPort: [UInt16: TCPConnectResult] = [:]
        var calls: [(IPv4, UInt16, Duration)] = []
    }

    private let state = Mutex(Box())

    var result: TCPConnectResult {
        get { state.withLock { $0.result } }
        set { state.withLock { $0.result = newValue } }
    }

    subscript(port port: UInt16) -> TCPConnectResult? {
        get { state.withLock { $0.resultsByPort[port] } }
        set { state.withLock { $0.resultsByPort[port] = newValue } }
    }

    var calls: [(IPv4, UInt16, Duration)] {
        state.withLock { $0.calls }
    }

    func connect(host: IPv4, port: UInt16, timeout: Duration) async -> TCPConnectResult {
        state.withLock { box in
            box.calls.append((host, port, timeout))
            return box.resultsByPort[port] ?? box.result
        }
    }

    var callCount: Int {
        state.withLock { $0.calls.count }
    }
}

final class ScriptedICMP: ICMPEchoProbing, Sendable {
    private struct Box: Sendable {
        var result: ICMPEchoResult = .unresponsive
        var calls = 0
    }

    private let state = Mutex(Box())
    let permitted: Bool

    init(permitted: Bool) {
        self.permitted = permitted
    }

    var result: ICMPEchoResult {
        get { state.withLock { $0.result } }
        set { state.withLock { $0.result = newValue } }
    }

    var isPermitted: Bool { permitted }

    func echo(host: IPv4, timeout: Duration) async -> ICMPEchoResult {
        state.withLock { box in
            box.calls += 1
            return box.result
        }
    }

    var callCount: Int {
        state.withLock { $0.calls }
    }
}

struct ScriptedNames: HostNameResolving {
    var names = HostNames()
    func resolve(host: IPv4, timeout: Duration) async -> HostNames {
        names
    }
}

struct ScriptedReverseDNS: ReverseDNSResolving {
    var name: String?
    func lookup(host: IPv4, timeout: Duration) async -> String? { name }
}

struct ScriptedBonjour: BonjourNameResolving {
    var name: String?
    func lookup(host: IPv4, timeout: Duration) async -> String? { name }
}

final class GateTCP: TCPConnectProbing, Sendable {
    private let gate = AsyncGate()
    private let enteredCount = Mutex(0)

    func connect(host: IPv4, port: UInt16, timeout: Duration) async -> TCPConnectResult {
        enteredCount.withLock { $0 += 1 }
        await gate.wait()
        return .timedOut
    }

    var entered: Int {
        enteredCount.withLock { $0 }
    }

    func releaseOne() {
        gate.releaseOne()
    }
}

final class AsyncGate: Sendable {
    private let waiters = Mutex<[CheckedContinuation<Void, Never>]>([])

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.withLock { $0.append(continuation) }
        }
    }

    func releaseOne() {
        let waiter: CheckedContinuation<Void, Never>? = waiters.withLock { pending in
            if pending.isEmpty { return nil }
            return pending.removeFirst()
        }
        waiter?.resume()
    }
}

func dependencies(
    icmp: any ICMPEchoProbing = ScriptedICMP(permitted: false),
    tcp: any TCPConnectProbing = ScriptedTCP(),
    names: any HostNameResolving = ScriptedNames()
) -> ScanDependencies {
    ScanDependencies(icmp: icmp, tcp: tcp, names: names)
}

func request(
    _ target: String,
    ports: String = "80",
    options: ScanOptions = ScanOptions(),
    acknowledge: Bool = false
) -> ScanRequest {
    ScanRequest(
        targetText: target,
        portText: ports,
        options: options,
        acknowledgePublicRange: acknowledge
    )
}
