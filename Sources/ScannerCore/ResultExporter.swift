import Foundation

/// Export document passed to `ResultExporter`.
public struct ScanExport: Sendable, Equatable {
    /// Target text stored with the document.
    public var target: String
    /// Hosts to write, in the given order.
    public var hosts: [HostObservation]

    /// Creates an export document.
    ///
    /// - Parameters:
    ///   - target: Target text.
    ///   - hosts: Rows to write.
    public init(target: String, hosts: [HostObservation]) {
        self.target = target
        self.hosts = hosts
    }
}

/// File format for a scan export.
public enum ExportFormat: String, Sendable, Equatable {
    case csv
    case json
    case txt
}

/// Renders scan rows as CSV, JSON, or TXT.
public enum ResultExporter {
    /// Renders a document.
    ///
    /// - Parameters:
    ///   - document: Target and hosts.
    ///   - format: CSV, JSON, or TXT.
    /// - Returns: The file text. An empty host list is a header-only CSV, a JSON
    ///   document with an empty `hosts` array, or a TXT note `No hosts were recorded.`
    /// - Throws: `ResultExportError.encodingFailed` when JSON encoding fails.
    public static func export(_ document: ScanExport, as format: ExportFormat) throws -> String {
        switch format {
        case .csv:
            return csv(document)
        case .json:
            return try json(document)
        case .txt:
            return txt(document)
        }
    }

    private static func csv(_ document: ScanExport) -> String {
        var lines = ["address,display_name,status,latency_ms,open_ports,discovery"]
        for host in document.hosts {
            let fields = [
                host.address.description,
                host.displayName ?? "",
                host.status.rawValue,
                host.latency.map { String(ProbeTiming.milliseconds($0)) } ?? "",
                host.openPorts.map(String.init).joined(separator: " "),
                host.discovery.rawValue,
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func json(_ document: ScanExport) throws -> String {
        let payload = ExportPayload(
            target: document.target,
            hosts: document.hosts.map { host in
                ExportHost(
                    address: host.address.description,
                    displayName: host.displayName,
                    status: host.status.rawValue,
                    latencyMilliseconds: host.latency.map { ProbeTiming.milliseconds($0) },
                    openPorts: host.openPorts,
                    discovery: host.discovery.rawValue
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ResultExportError.encodingFailed
        }
        return text
    }

    private static func txt(_ document: ScanExport) -> String {
        var lines = ["Target: \(document.target)"]
        if document.hosts.isEmpty {
            lines.append("No hosts were recorded.")
            return lines.joined(separator: "\n")
        }
        lines.append("Hosts: \(document.hosts.count)")
        lines.append("")
        for host in document.hosts {
            lines.append("\(host.address.description)  \(host.displayName ?? "")")
            lines.append("  status: \(host.status.rawValue)")
            if let latency = host.latency {
                lines.append("  latency: \(ProbeTiming.milliseconds(latency)) ms")
            } else {
                lines.append("  latency:")
            }
            let ports = host.openPorts.map(String.init).joined(separator: " ")
            lines.append("  open ports: \(ports)")
            lines.append("  discovery: \(host.discovery.rawValue)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// JSON encoding failed.
public enum ResultExportError: Error, Equatable, Sendable {
    case encodingFailed
}

private struct ExportPayload: Encodable {
    var target: String
    var hosts: [ExportHost]
}

private struct ExportHost: Encodable {
    var address: String
    var displayName: String?
    var status: String
    var latencyMilliseconds: Int?
    var openPorts: [UInt16]
    var discovery: String
}
