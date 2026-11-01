import Foundation
import Testing
@testable import ScannerCore

@Test func csvHasHeaderAndOneRowPerHost() throws {
    // Requirement 11.1
    let document = ScanExport(target: "10.0.0.0/30", hosts: [
        observation("10.0.0.1", name: "router", latency: .milliseconds(12), ports: [80, 443], discovery: .icmp),
    ])
    let csv = try ResultExporter.export(document, as: .csv)
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == document.hosts.count + 1)
    #expect(lines[0] == "address,display_name,status,latency_ms,open_ports,discovery")
    #expect(lines[1].contains("10.0.0.1"))
    #expect(lines[1].contains("router"))
    #expect(lines[1].contains("alive"))
    #expect(lines[1].contains("12"))
    #expect(lines[1].contains("80 443"))
    #expect(lines[1].contains("icmp"))
}

@Test func jsonContainsTargetAndHostFields() throws {
    // Requirement 11.2
    let document = ScanExport(target: "10.1.0.0/32", hosts: [
        observation("10.1.0.1", bonjour: "Office", ports: [22], discovery: .tcpOpen),
    ])
    let text = try ResultExporter.export(document, as: .json)
    let data = Data(text.utf8)
    let decoded = try JSONDecoder().decode(ExportCheck.self, from: data)
    #expect(decoded.target == "10.1.0.0/32")
    #expect(decoded.hosts.count == 1)
    #expect(decoded.hosts[0].address == "10.1.0.1")
    #expect(decoded.hosts[0].displayName == "Office")
    #expect(decoded.hosts[0].status == "alive")
    #expect(decoded.hosts[0].openPorts == [22])
    #expect(decoded.hosts[0].discovery == "tcpOpen")
}

@Test func txtHasOneBlockPerHost() throws {
    // Requirement 11.3
    let text = try ResultExporter.export(
        ScanExport(target: "10.0.0.1", hosts: [observation("10.0.0.1", name: "box")]),
        as: .txt
    )
    #expect(text.contains("Target: 10.0.0.1"))
    #expect(text.contains("status: alive"))
    #expect(text.contains("open ports:"))
    #expect(text.contains("discovery:"))
}

@Test func emptyExportIsAValidDocument() throws {
    // Requirement 11.4
    let empty = ScanExport(target: "10.0.0.0/30", hosts: [])
    let csv = try ResultExporter.export(empty, as: .csv)
    #expect(csv == "address,display_name,status,latency_ms,open_ports,discovery")
    let json = try ResultExporter.export(empty, as: .json)
    let decoded = try JSONDecoder().decode(ExportCheck.self, from: Data(json.utf8))
    #expect(decoded.hosts.isEmpty)
    let txt = try ResultExporter.export(empty, as: .txt)
    #expect(txt.contains("No hosts were recorded."))
}

private struct ExportCheck: Decodable {
    var target: String
    var hosts: [ExportHostCheck]
}

private struct ExportHostCheck: Decodable {
    var address: String
    var displayName: String?
    var status: String
    var latencyMilliseconds: Int?
    var openPorts: [UInt16]
    var discovery: String
}
