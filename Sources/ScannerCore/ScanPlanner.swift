/// Expands targets and rejects requests that must not send probes.
public enum ScanPlanner {
    /// Validates and expands a request.
    ///
    /// - Parameter request: Target, ports, options, and the public-range flag.
    /// - Returns: The addresses and ports to probe.
    /// - Throws: `ScanValidationError` when the target, ports, concurrency, timeout,
    ///   or public-range acknowledgement is not acceptable. A throw means no probe
    ///   should be sent.
    public static func plan(_ request: ScanRequest) throws -> ScanPlan {
        guard (1...256).contains(request.options.maxConcurrentHosts) else {
            throw ScanValidationError.invalidConcurrency
        }
        guard request.options.probeTimeout > .zero, request.options.nameBudget > .zero else {
            throw ScanValidationError.invalidTimeout
        }
        let hosts = try expand(request.targetText, hostCap: request.options.hostCap)
        let ports = try PortSelection.parse(request.portText)
        if hosts.contains(where: { AddressScope.classify($0) == .publicRange }),
           !request.acknowledgePublicRange {
            throw ScanValidationError.publicRangeRequiresAcknowledgement
        }
        let target = request.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScanPlan(targetText: target, hosts: hosts, ports: ports, options: request.options)
    }

    private static func expand(_ text: String, hostCap: Int) throws -> [IPv4] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ScanValidationError.emptyTarget
        }
        if hostCap < 1 {
            throw ScanValidationError.rangeTooLarge(count: 0, limit: hostCap)
        }
        if trimmed.contains("/") {
            return try expandCIDR(trimmed, hostCap: hostCap)
        }
        if trimmed.contains("-") {
            return try expandRange(trimmed, hostCap: hostCap)
        }
        guard let address = IPv4(dotted: trimmed) else {
            throw ScanValidationError.invalidTarget(trimmed)
        }
        return [address]
    }

    private static func expandCIDR(_ text: String, hostCap: Int) throws -> [IPv4] {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let address = IPv4(dotted: String(parts[0])) else {
            throw ScanValidationError.invalidTarget(text)
        }
        guard let prefix = Int(parts[1]), (0...32).contains(prefix) else {
            throw ScanValidationError.invalidTarget(text)
        }
        let hostBits = 32 - prefix
        let count: UInt64 = hostBits == 32 ? (UInt64(1) << 32) : (UInt64(1) << UInt64(hostBits))
        let network: UInt32
        if prefix == 0 {
            network = 0
        } else {
            let mask = UInt32.max << hostBits
            network = address.raw & mask
        }
        return try materialize(from: network, count: count, hostCap: hostCap)
    }

    private static func expandRange(_ text: String, hostCap: Int) throws -> [IPv4] {
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw ScanValidationError.invalidTarget(text)
        }
        let left = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = IPv4(dotted: left) else {
            throw ScanValidationError.invalidTarget(text)
        }
        let end: IPv4
        if right.contains(".") {
            guard let parsed = IPv4(dotted: right) else {
                throw ScanValidationError.invalidTarget(text)
            }
            end = parsed
        } else {
            if right.count > 1, right.first == "0" {
                throw ScanValidationError.invalidTarget(text)
            }
            guard let octet = UInt32(right), octet <= 255 else {
                throw ScanValidationError.invalidTarget(text)
            }
            let startOctet = start.raw & 0xFF
            if octet < startOctet {
                throw ScanValidationError.invertedRange
            }
            end = IPv4(raw: (start.raw & 0xFFFF_FF00) | octet)
        }
        if end.raw < start.raw {
            throw ScanValidationError.invertedRange
        }
        let count = UInt64(end.raw - start.raw) + 1
        return try materialize(from: start.raw, count: count, hostCap: hostCap)
    }

    private static func materialize(from start: UInt32, count: UInt64, hostCap: Int) throws -> [IPv4] {
        if count > UInt64(hostCap) {
            let reported = count > UInt64(Int.max) ? Int.max : Int(count)
            throw ScanValidationError.rangeTooLarge(count: reported, limit: hostCap)
        }
        var hosts: [IPv4] = []
        hosts.reserveCapacity(Int(count))
        var cursor = start
        for _ in 0..<Int(count) {
            hosts.append(IPv4(raw: cursor))
            cursor &+= 1
        }
        return hosts
    }
}
