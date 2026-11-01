/// Parses the TCP ports a scan will probe.
public enum PortSelection {
    /// Ports Subnet Scout checks when the caller leaves the port field blank.
    ///
    /// This is an original short list for home and lab networks. It is not a
    /// copy of another scanner's preset file.
    public static let commonPorts: [UInt16] = [
        22, 53, 80, 443, 445, 548, 631, 3283, 3389, 5000, 5900, 8080, 8443, 62078,
    ]

    /// Parses a port list.
    ///
    /// - Parameter text: Comma-separated ports and inclusive ranges, such as
    ///   `80,443,8000-8002`. Empty text and `common` select `commonPorts`.
    /// - Returns: Ports in the order written, with duplicates removed.
    /// - Throws: `ScanValidationError.invalidPortList` when a token is not a
    ///   port from 1 through 65535 or a range descends.
    public static func parse(_ text: String) throws -> [UInt16] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "common" {
            return commonPorts
        }
        var ports: [UInt16] = []
        var seen = Set<UInt16>()
        for token in trimmed.split(separator: ",", omittingEmptySubsequences: false) {
            let piece = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if piece.isEmpty {
                throw ScanValidationError.invalidPortList(trimmed)
            }
            if piece.contains("-") {
                try appendRange(piece, source: trimmed, ports: &ports, seen: &seen)
            } else {
                guard let port = parsePort(piece) else {
                    throw ScanValidationError.invalidPortList(trimmed)
                }
                if seen.insert(port).inserted {
                    ports.append(port)
                }
            }
        }
        if ports.isEmpty {
            throw ScanValidationError.invalidPortList(trimmed)
        }
        return ports
    }

    private static func appendRange(
        _ piece: String,
        source: String,
        ports: inout [UInt16],
        seen: inout Set<UInt16>
    ) throws {
        let bounds = piece.split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = parsePort(bounds[0]), let end = parsePort(bounds[1]) else {
            throw ScanValidationError.invalidPortList(source)
        }
        if end < start {
            throw ScanValidationError.invalidPortList(source)
        }
        var value = start
        while true {
            if seen.insert(value).inserted {
                ports.append(value)
            }
            if value == end { break }
            value += 1
        }
    }

    private static func parsePort<S: StringProtocol>(_ text: S) -> UInt16? {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.count > 1, token.first == "0" { return nil }
        guard let value = Int(token), (1...65535).contains(value) else { return nil }
        return UInt16(value)
    }
}
