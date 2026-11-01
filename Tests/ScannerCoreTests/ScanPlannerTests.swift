import Testing
@testable import ScannerCore

@Test func singleAddressExpandsToThatHost() throws {
    // Requirement 1.1
    let plan = try ScanPlanner.plan(request("192.168.1.9", ports: "80"))
    #expect(plan.hosts.map(\.description) == ["192.168.1.9"])
}

@Test func inclusiveRangeIncludesBothEnds() throws {
    // Requirement 1.2
    let shorthand = try ScanPlanner.plan(request("10.0.0.2-5", ports: "80"))
    #expect(shorthand.hosts.map(\.description) == ["10.0.0.2", "10.0.0.3", "10.0.0.4", "10.0.0.5"])
    let full = try ScanPlanner.plan(request("10.0.0.2-10.0.0.4", ports: "80"))
    #expect(full.hosts.map(\.description) == ["10.0.0.2", "10.0.0.3", "10.0.0.4"])
}

@Test func cidrIncludesNetworkAndBroadcast() throws {
    // Requirement 1.3
    let plan = try ScanPlanner.plan(request("192.168.1.21/30", ports: "80"))
    #expect(plan.hosts.map(\.description) == [
        "192.168.1.20", "192.168.1.21", "192.168.1.22", "192.168.1.23",
    ])
}

@Test func prefixLengthsMatchPowerOfTwo() throws {
    // Requirement 1.3
    for length in 24...32 {
        let plan = try ScanPlanner.plan(request("10.1.2.3/\(length)", ports: "80"))
        #expect(plan.hosts.count == 1 << (32 - length))
    }
}

@Test func emptyAndUnknownTargetsDoNotExpand() {
    // Requirement 2.1
    #expect(throws: ScanValidationError.emptyTarget) {
        try ScanPlanner.plan(request("   ", ports: "80"))
    }
    #expect(throws: ScanValidationError.invalidTarget("192.168.01.1")) {
        try ScanPlanner.plan(request("192.168.01.1", ports: "80"))
    }
}

@Test func oversizedRangeIsRejected() {
    // Requirement 2.2
    #expect(throws: ScanValidationError.rangeTooLarge(count: 8192, limit: 4096)) {
        try ScanPlanner.plan(request("10.0.0.0/19", ports: "80"))
    }
}

@Test func invertedRangeIsRejected() {
    // Requirement 2.3
    #expect(throws: ScanValidationError.invertedRange) {
        try ScanPlanner.plan(request("10.0.0.5-4", ports: "80"))
    }
    #expect(throws: ScanValidationError.invertedRange) {
        try ScanPlanner.plan(request("10.0.0.8-10.0.0.2", ports: "80"))
    }
}

@Test func concurrencyAndTimeoutAreRejected() {
    // Requirement 2.4
    var options = ScanOptions()
    options.maxConcurrentHosts = 0
    #expect(throws: ScanValidationError.invalidConcurrency) {
        try ScanPlanner.plan(request("10.0.0.1", ports: "80", options: options))
    }
    options.maxConcurrentHosts = 257
    #expect(throws: ScanValidationError.invalidConcurrency) {
        try ScanPlanner.plan(request("10.0.0.1", ports: "80", options: options))
    }
    options = ScanOptions(probeTimeout: .zero)
    #expect(throws: ScanValidationError.invalidTimeout) {
        try ScanPlanner.plan(request("10.0.0.1", ports: "80", options: options))
    }
}

@Test func portListParsesNumbersAndRanges() throws {
    // Requirement 6.1
    let plan = try ScanPlanner.plan(request("10.0.0.1", ports: "80, 443, 8000-8002, 80"))
    #expect(plan.ports == [80, 443, 8000, 8001, 8002])
}

@Test func blankPortListUsesCommonPreset() throws {
    // Requirement 6.2
    let plan = try ScanPlanner.plan(request("10.0.0.1", ports: "  "))
    #expect(plan.ports == PortSelection.commonPorts)
    let named = try ScanPlanner.plan(request("10.0.0.1", ports: "common"))
    #expect(named.ports == PortSelection.commonPorts)
}

@Test func badPortListIsRejected() {
    // Requirement 6.3
    #expect(throws: ScanValidationError.invalidPortList("80-70")) {
        try ScanPlanner.plan(request("10.0.0.1", ports: "80-70"))
    }
    #expect(throws: ScanValidationError.invalidPortList("0")) {
        try ScanPlanner.plan(request("10.0.0.1", ports: "0"))
    }
    #expect(throws: ScanValidationError.invalidPortList("65536")) {
        try ScanPlanner.plan(request("10.0.0.1", ports: "65536"))
    }
}
