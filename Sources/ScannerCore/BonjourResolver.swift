#if canImport(Network)
import Foundation
import Network

/// Browses a fixed set of Bonjour types and remembers the first instance name per IPv4 address.
public actor NetworkBonjourResolver: BonjourNameResolving {
    private let serviceTypes: [String]
    private var cache: [IPv4: String] = [:]
    private var warm: Task<Void, Never>?

    /// Creates a browser.
    ///
    /// - Parameter serviceTypes: Bonjour types such as `_http._tcp`.
    public init(serviceTypes: [String] = BonjourServiceTypes.defaults) {
        self.serviceTypes = serviceTypes
    }

    /// Returns the cached instance name, browsing once per resolver if needed.
    ///
    /// - Parameters:
    ///   - host: Address to match.
    ///   - timeout: Browse budget used on the first lookup.
    /// - Returns: The first advertised instance name resolved to `host`, or `nil`.
    public func lookup(host: IPv4, timeout: Duration) async -> String? {
        if warm == nil {
            let budget = timeout
            warm = Task { await self.browse(timeout: budget) }
        }
        await warm?.value
        return cache[host]
    }

    private func browse(timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            for serviceType in serviceTypes {
                group.addTask {
                    await self.browseType(serviceType, timeout: timeout)
                }
            }
        }
    }

    private func browseType(_ serviceType: String, timeout: Duration) async {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        let handle = BrowserHandle(browser)
        let box = ResultBox()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = BonjourGate()
            browser.browseResultsChangedHandler = { results, _ in
                box.set(results)
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    gate.resumeOnce {
                        handle.cancel()
                        continuation.resume()
                    }
                }
            }
            browser.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: timeout)
                gate.resumeOnce {
                    handle.cancel()
                    continuation.resume()
                }
            }
        }
        for result in box.snapshot() {
            if let match = await resolve(result.endpoint) {
                remember(match)
            }
        }
    }

    private func resolve(_ endpoint: NWEndpoint) async -> (IPv4, String)? {
        let serviceName: String
        switch endpoint {
        case .service(let name, _, _, _):
            serviceName = name
        default:
            return nil
        }
        let connection = NWConnection(to: endpoint, using: .tcp)
        let connectionBox = BonjourConnectionBox(connection)
        let address = await withCheckedContinuation { (continuation: CheckedContinuation<IPv4?, Never>) in
            let gate = BonjourGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let resolved = connectionBox.ipv4Address()
                    gate.resumeOnce {
                        connectionBox.cancel()
                        continuation.resume(returning: resolved)
                    }
                case .failed, .cancelled:
                    gate.resumeOnce {
                        connectionBox.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                gate.resumeOnce {
                    connectionBox.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
        guard let address else { return nil }
        return (address, serviceName)
    }

    private func remember(_ match: (IPv4, String)) {
        if cache[match.0] == nil, !match.1.isEmpty {
            cache[match.0] = match.1
        }
    }

}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var results: Set<NWBrowser.Result> = []

    func set(_ results: Set<NWBrowser.Result>) {
        lock.lock()
        self.results = results
        lock.unlock()
    }

    func snapshot() -> Set<NWBrowser.Result> {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}

private final class BrowserHandle: @unchecked Sendable {
    private let browser: NWBrowser

    init(_ browser: NWBrowser) {
        self.browser = browser
    }

    func cancel() {
        browser.cancel()
    }
}

private final class BonjourConnectionBox: @unchecked Sendable {
    private let connection: NWConnection

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func cancel() {
        connection.cancel()
    }

    func ipv4Address() -> IPv4? {
        guard case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint,
              case .ipv4(let address) = host else {
            return nil
        }
        let bytes = [UInt8](address.rawValue)
        guard bytes.count == 4 else { return nil }
        let raw = (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
        return IPv4(raw: raw)
    }
}

private final class BonjourGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        body()
    }
}
#endif
