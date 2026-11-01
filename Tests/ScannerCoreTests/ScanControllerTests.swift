import Foundation
import Testing
@testable import ScannerCore

@Test func publicRangeSendsNoProbesUntilAcknowledged() async throws {
    // Requirements 3.2 and 3.3
    let tcp = ScriptedTCP()
    let icmp = ScriptedICMP(permitted: true)
    let controller = ScanController(dependencies: dependencies(icmp: icmp, tcp: tcp))
    do {
        _ = try await controller.start(request("8.8.8.8", ports: "80"))
        Issue.record("public range started")
    } catch let error as ScanValidationError {
        #expect(error == .publicRangeRequiresAcknowledgement)
    }
    #expect(tcp.callCount == 0)
    #expect(icmp.callCount == 0)
    #expect(await controller.currentPhase() == .idle)

    tcp[port: 80] = .refused(latency: .milliseconds(1))
    let stream = try await controller.start(request("8.8.8.8", ports: "80", acknowledge: true))
    var sawHost = false
    for await event in stream {
        if case .hostCompleted(let host) = event {
            sawHost = true
            #expect(host.status == .alive)
        }
    }
    #expect(sawHost)
    #expect(tcp.callCount == 1)
}

@Test func icmpReplyMarksHostAliveWhenTcpTimesOut() async throws {
    // Requirements 4.1 and 4.5
    let tcp = ScriptedTCP()
    tcp.result = .timedOut
    let icmp = ScriptedICMP(permitted: true)
    icmp.result = .replied(latency: .milliseconds(3))
    let events = try await runScan(
        request("10.0.0.4", ports: "80"),
        icmp: icmp,
        tcp: tcp
    )
    let host = try completedHost(events)
    #expect(icmp.callCount == 1)
    #expect(host.status == .alive)
    #expect(host.discovery == .icmp)
    #expect(host.openPorts.isEmpty)
    #expect(host.latency != nil)
}

@Test func unavailableICMPFallsBackToTCP() async throws {
    // Requirements 4.2, 4.3, and 6.4
    let tcp = ScriptedTCP()
    tcp[port: 22] = .open(latency: .milliseconds(4))
    tcp[port: 80] = .timedOut
    let icmp = ScriptedICMP(permitted: false)
    let events = try await runScan(
        request("10.0.0.5", ports: "22,80"),
        icmp: icmp,
        tcp: tcp
    )
    let host = try completedHost(events)
    #expect(icmp.callCount == 0)
    #expect(host.status == .alive)
    #expect(host.discovery == .tcpOpen)
    #expect(host.openPorts == [22])
    #expect(events.contains { if case .finished = $0 { return true } else { return false } })
}

@Test func refusalIsAliveAndTimeoutIsUnresponsive() async throws {
    // Requirements 4.3, 4.4, 6.5, 7.1, and 7.2
    let refused = ScriptedTCP()
    refused.result = .refused(latency: .milliseconds(2))
    let refusedEvents = try await runScan(request("10.0.0.6", ports: "80"), tcp: refused)
    let refusedHost = try completedHost(refusedEvents)
    #expect(refusedHost.status == .alive)
    #expect(refusedHost.discovery == .tcpRefused)
    #expect(refusedHost.openPorts.isEmpty)
    #expect(refusedHost.latency != nil)

    let timedOut = ScriptedTCP()
    timedOut.result = .timedOut
    let deadEvents = try await runScan(request("10.0.0.7", ports: "80"), tcp: timedOut)
    let deadHost = try completedHost(deadEvents)
    #expect(deadHost.status == .unresponsive)
    #expect(deadHost.discovery == .none)
    #expect(deadHost.latency == nil)
}

@Test func controllerPassesTheProbeTimeout() async throws {
    // Requirement 7.4
    let tcp = ScriptedTCP()
    tcp.result = .timedOut
    let options = ScanOptions(probeTimeout: .milliseconds(250))
    _ = try await runScan(request("10.0.0.8", ports: "80,443", options: options), tcp: tcp)
    #expect(tcp.calls.allSatisfy { $0.2 == .milliseconds(250) })
}

@Test func hostConcurrencyStaysAtTheConfiguredLimit() async throws {
    // Requirement 7.3
    let tracker = TrackingTCP()
    let options = ScanOptions(maxConcurrentHosts: 2, probeTimeout: .seconds(1))
    _ = try await runScan(
        request("10.1.0.1-6", ports: "80", options: options),
        tcp: tracker
    )
    #expect(await tracker.maxSeen <= 2)
    #expect(await tracker.maxSeen == 2)
}

@Test func pauseResumeAndCancelKeepCollectedRows() async throws {
    // Requirements 8.1, 8.2, 8.3, and 8.4
    let gate = GateTCP()
    let controller = ScanController(dependencies: dependencies(tcp: gate))
    let stream = try await controller.start(request("10.2.0.1-3", ports: "80", options: ScanOptions(maxConcurrentHosts: 1)))
    let collector = Task { () -> [ScanEvent] in
        var events: [ScanEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }
    try await waitUntil { gate.entered == 1 }
    await controller.pause()
    #expect(await controller.currentPhase() == .paused)
    await controller.pause()
    #expect(await controller.currentPhase() == .paused)
    gate.releaseOne()
    try await Task.sleep(for: .milliseconds(120))
    #expect(gate.entered == 1)
    await controller.resume()
    try await waitUntil { gate.entered >= 2 }
    await controller.cancel()
    gate.releaseOne()
    let events = await collector.value
    #expect(events.contains { if case .cancelled = $0 { return true } else { return false } })
    #expect(gate.entered < 3)
    let idle = ScanController(dependencies: dependencies())
    await idle.cancel()
    #expect(await idle.currentPhase() == .idle)
    await idle.resume()
    #expect(await idle.currentPhase() == .idle)
}

@Test func secondStartLeavesTheFirstScanRunning() async throws {
    // Requirement 13.1
    let gate = GateTCP()
    let controller = ScanController(dependencies: dependencies(tcp: gate))
    let stream = try await controller.start(request("10.3.0.1-2", ports: "80", options: ScanOptions(maxConcurrentHosts: 1)))
    let collector = Task {
        for await _ in stream {}
    }
    try await waitUntil { gate.entered == 1 }
    do {
        _ = try await controller.start(request("10.3.0.8", ports: "80"))
        Issue.record("second start was accepted")
    } catch let error as ScanValidationError {
        #expect(error == .alreadyRunning)
    }
    #expect(await controller.currentPhase() == .running)
    await controller.cancel()
    gate.releaseOne()
    await collector.value
}

private func runScan(
    _ request: ScanRequest,
    icmp: any ICMPEchoProbing = ScriptedICMP(permitted: false),
    tcp: any TCPConnectProbing
) async throws -> [ScanEvent] {
    let controller = ScanController(dependencies: dependencies(icmp: icmp, tcp: tcp))
    let stream = try await controller.start(request)
    var events: [ScanEvent] = []
    for await event in stream {
        events.append(event)
    }
    return events
}

private func completedHost(_ events: [ScanEvent]) throws -> HostObservation {
    for event in events {
        if case .hostCompleted(let host) = event {
            return host
        }
    }
    Issue.record("missing host")
    throw ScanValidationError.emptyTarget
}

private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async throws {
    for _ in 0..<50 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition was not met")
}

private actor TrackingTCP: TCPConnectProbing {
    private var current = 0
    private(set) var maxSeen = 0

    func connect(host: IPv4, port: UInt16, timeout: Duration) async -> TCPConnectResult {
        current += 1
        maxSeen = max(maxSeen, current)
        try? await Task.sleep(for: .milliseconds(40))
        current -= 1
        return .timedOut
    }
}
