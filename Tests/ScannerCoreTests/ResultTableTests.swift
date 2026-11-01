import Testing
@testable import ScannerCore

@Test func rowsExposeTheTableFields() {
    // Requirement 9.1
    let row = observation("10.0.0.8", name: "nas", ports: [22, 443], discovery: .tcpOpen)
    #expect(row.address.description == "10.0.0.8")
    #expect(row.displayName == "nas")
    #expect(row.status == .alive)
    #expect(row.latency != nil)
    #expect(row.openPorts == [22, 443])
}

@Test func addressSortIsNumeric() {
    // Requirement 9.2
    let hosts = [
        observation("192.168.1.10"),
        observation("192.168.1.2"),
    ]
    let sorted = ResultTable.rows(hosts, matching: ResultQuery(sort: .address, ascending: true))
    #expect(sorted.map(\.address.description) == ["192.168.1.2", "192.168.1.10"])
}

@Test func textFilterMatchesAddressOrName() {
    // Requirement 9.3
    let hosts = [
        observation("10.0.0.5", name: "Printer"),
        observation("10.0.0.9", name: "laptop"),
    ]
    let matched = ResultTable.rows(hosts, matching: ResultQuery(text: "PRINT"))
    #expect(matched.map(\.address.description) == ["10.0.0.5"])
}

@Test func aliveOnlyHidesUnresponsiveHosts() {
    // Requirement 9.4
    let hosts = [
        observation("10.0.0.1", status: .alive, discovery: .tcpRefused),
        observation("10.0.0.2", status: .unresponsive, discovery: .none),
    ]
    let matched = ResultTable.rows(hosts, matching: ResultQuery(aliveOnly: true))
    #expect(matched.map(\.address.description) == ["10.0.0.1"])
}

@Test func emptyFilterKeepsTheUnderlyingArray() {
    // Requirement 9.5
    let hosts = [observation("10.0.0.1", name: "a")]
    let snapshot = hosts
    let matched = ResultTable.rows(hosts, matching: ResultQuery(text: "missing"))
    #expect(matched.isEmpty)
    #expect(hosts == snapshot)
}
