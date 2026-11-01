/// Column used to order the result table.
public enum ResultSort: String, Sendable, Equatable, CaseIterable {
    case address
    case displayName
    case latency
    case openPortCount
    case status
}

/// Filter and sort applied to a copy of the scan rows.
public struct ResultQuery: Sendable, Equatable {
    /// Case-insensitive match against the address or display name. Empty matches all.
    public var text: String
    /// When `true`, unresponsive hosts are hidden.
    public var aliveOnly: Bool
    /// Sort key.
    public var sort: ResultSort
    /// `true` for ascending order.
    public var ascending: Bool

    /// Creates a query.
    ///
    /// - Parameters:
    ///   - text: Filter text.
    ///   - aliveOnly: Whether to hide unresponsive hosts.
    ///   - sort: Sort key.
    ///   - ascending: Sort direction.
    public init(
        text: String = "",
        aliveOnly: Bool = false,
        sort: ResultSort = .address,
        ascending: Bool = true
    ) {
        self.text = text
        self.aliveOnly = aliveOnly
        self.sort = sort
        self.ascending = ascending
    }
}

/// Pure filter and sort for host observations.
public enum ResultTable {
    /// Returns a filtered, sorted copy.
    ///
    /// - Parameters:
    ///   - hosts: Underlying rows. This array is not modified.
    ///   - query: Text, alive-only flag, and sort.
    /// - Returns: The rows that match. Addresses sort numerically. Empty display names
    ///   sort after non-empty names when sorting by name ascending. Missing latency sorts
    ///   after known latencies when sorting by latency ascending.
    public static func rows(_ hosts: [HostObservation], matching query: ResultQuery) -> [HostObservation] {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = hosts.filter { host in
            if query.aliveOnly, host.status != .alive { return false }
            if needle.isEmpty { return true }
            if host.address.description.lowercased().contains(needle) { return true }
            if let name = host.displayName?.lowercased(), name.contains(needle) { return true }
            return false
        }
        return filtered.sorted { lhs, rhs in
            query.ascending ? less(lhs, rhs, query.sort) : less(rhs, lhs, query.sort)
        }
    }

    private static func less(_ lhs: HostObservation, _ rhs: HostObservation, _ sort: ResultSort) -> Bool {
        switch sort {
        case .address:
            return lhs.address < rhs.address
        case .displayName:
            return nameKey(lhs) < nameKey(rhs)
        case .latency:
            return latencyKey(lhs) < latencyKey(rhs)
        case .openPortCount:
            return lhs.openPorts.count < rhs.openPorts.count
        case .status:
            return lhs.status < rhs.status
        }
    }

    private static func nameKey(_ host: HostObservation) -> (Int, String) {
        let name = host.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return (name.isEmpty ? 1 : 0, name)
    }

    private static func latencyKey(_ host: HostObservation) -> (Int, Duration) {
        if let latency = host.latency {
            return (0, latency)
        }
        return (1, .zero)
    }
}
