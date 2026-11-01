import Foundation
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

final class ScriptedTCP: TCPConnectProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: TCPConnectResult = .timedOut
    private var resultsByPort: [UInt16: TCPConnectResult] = [:]
    private var recordedCalls: [(IPv4, UInt16, Duration)] = []

    var result: TCPConnectResult {
        get { locked { storedResult } }
        set { locked { storedResult = newValue } }
    }

    subscript(port port: UInt16) -> TCPConnectResult? {
        get { locked { resultsByPort[port] } }
        set { locked { resultsByPort[port] = newValue } }
    }

    var calls: [(IPv4, UInt16, Duration)] {
        locked { recordedCalls }
    }

    func connect(host: IPv4, port: UInt16, timeout: Duration) async -> TCPConnectResult {
        record(host: host, port: port, timeout: timeout)
    }

    var callCount: Int {
        locked { recordedCalls.count }
    }

    private func record(host: IPv4, port: UInt16, timeout: Duration) -> TCPConnectResult {
        locked {
            recordedCalls.append((host, port, timeout))
            return resultsByPort[port] ?? storedResult
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class ScriptedICMP: ICMPEchoProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: ICMPEchoResult = .unresponsive
    private var calls = 0
    let permitted: Bool

    init(permitted: Bool) {
        self.permitted = permitted
    }

    var result: ICMPEchoResult {
        get { locked { storedResult } }
        set { locked { storedResult = newValue } }
    }

    var isPermitted: Bool { permitted }

    func echo(host: IPv4, timeout: Duration) async -> ICMPEchoResult {
        noteEcho()
    }

    var callCount: Int {
        locked { calls }
    }

    private func noteEcho() -> ICMPEchoResult {
        locked {
            calls += 1
            return storedResult
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
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

final class GateTCP: TCPConnectProbing, @unchecked Sendable {
    private let gate = AsyncGate()
    private let lock = NSLock()
    private var enteredCount = 0

    func connect(host: IPv4, port: UInt16, timeout: Duration) async -> TCPConnectResult {
        markEntered()
        await gate.wait()
        return .timedOut
    }

    var entered: Int {
        lock.lock()
        defer { lock.unlock() }
        return enteredCount
    }

    func releaseOne() {
        gate.releaseOne()
    }

    private func markEntered() {
        lock.lock()
        enteredCount += 1
        lock.unlock()
    }
}

final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            enqueue(continuation)
        }
    }

    func releaseOne() {
        let waiter = dequeue()
        waiter?.resume()
    }

    private func enqueue(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        waiters.append(continuation)
        lock.unlock()
    }

    private func dequeue() -> CheckedContinuation<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        if waiters.isEmpty { return nil }
        return waiters.removeFirst()
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
