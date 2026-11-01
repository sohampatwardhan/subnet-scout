import Foundation
import ScannerCore

/// SwiftUI state for one scan session. The package decides what may be probed.
@MainActor
@Observable
final class ScanSessionModel {
    var targetText: String
    var portText: String
    var maxConcurrentHosts: Int
    var timeoutMilliseconds: Int
    var phase: ScanPhase = .idle
    var hosts: [HostObservation] = []
    var scheduledCount = 0
    var filterText = ""
    var aliveOnly = false
    var sort: ResultSort = .address
    var ascending = true
    var favorites: [FavoriteRange] = []
    var favoriteName = ""
    var errorMessage: String?
    var showError = false
    var showPublicConfirm = false
    var subnetMessage: String?
    var exportText = ""
    var exportType: ExportFormat = .csv
    var showExporter = false

    private let controller: ScanController
    private let interfaces: any InterfaceListing
    private let favoritesStore: FileFavoriteStore
    private var pendingAcknowledged: ScanRequest?
    private var runTask: Task<Void, Never>?

    var visibleHosts: [HostObservation] {
        ResultTable.rows(
            hosts,
            matching: ResultQuery(
                text: filterText,
                aliveOnly: aliveOnly,
                sort: sort,
                ascending: ascending
            )
        )
    }

    var canStart: Bool { phase != .running && phase != .paused }
    var canPause: Bool { phase == .running }
    var canResume: Bool { phase == .paused }
    var canCancel: Bool { phase == .running || phase == .paused }

    init(
        controller: ScanController,
        interfaces: any InterfaceListing,
        favoritesStore: FileFavoriteStore,
        defaults: UserDefaults = .standard
    ) {
        self.controller = controller
        self.interfaces = interfaces
        self.favoritesStore = favoritesStore
        targetText = defaults.string(forKey: Keys.target) ?? ""
        portText = defaults.string(forKey: Keys.ports) ?? ""
        let storedConcurrency = defaults.object(forKey: Keys.concurrency) as? Int
        maxConcurrentHosts = storedConcurrency.map { min(max($0, 1), 256) } ?? 32
        let storedTimeout = defaults.object(forKey: Keys.timeout) as? Int
        timeoutMilliseconds = storedTimeout.map { max($0, 1) } ?? 1000
        do {
            favorites = try favoritesStore.load()
        } catch {
            favorites = []
            errorMessage = "Saved ranges could not be read."
            showError = true
        }
    }

    static func live() -> ScanSessionModel {
        let directory = AppSupport.directory()
        return ScanSessionModel(
            controller: ScanController(dependencies: .live()),
            interfaces: SystemInterfaceListing(),
            favoritesStore: FileFavoriteStore(fileURL: directory.appendingPathComponent("favorites.json"))
        )
    }

    func start() {
        run(makeRequest(acknowledge: false))
    }

    /// Requirement 3.3: declining leaves the idle scan and the current rows in place.
    func declinePublicScan() {
        pendingAcknowledged = nil
        showPublicConfirm = false
    }

    func confirmPublicScan() {
        guard let request = pendingAcknowledged else { return }
        pendingAcknowledged = nil
        showPublicConfirm = false
        run(request)
    }

    func pause() {
        Task {
            await controller.pause()
            phase = await controller.currentPhase()
        }
    }

    func resume() {
        Task {
            await controller.resume()
            phase = await controller.currentPhase()
        }
    }

    func cancel() {
        Task {
            await controller.cancel()
            phase = await controller.currentPhase()
        }
    }

    /// Requirement 1.4 and 1.5.
    func useCurrentSubnet() {
        let selection = CurrentSubnet.select(from: interfaces.interfaces())
        if let text = selection.targetText {
            targetText = text
            subnetMessage = nil
            persistFields()
        } else {
            subnetMessage = selection.message
        }
    }

    /// Requirement 10.2.
    func choose(_ favorite: FavoriteRange) {
        targetText = favorite.targetText
        portText = favorite.portText
        persistFields()
    }

    func saveFavorite() {
        let favorite = FavoriteRange(
            id: UUID(),
            name: favoriteName,
            targetText: targetText,
            portText: portText,
            createdAt: Date()
        )
        do {
            try favoritesStore.save(favorite)
            favorites = try favoritesStore.load()
            favoriteName = ""
        } catch {
            present(error)
        }
    }

    func deleteFavorite(_ favorite: FavoriteRange) {
        do {
            try favoritesStore.delete(id: favorite.id)
            favorites = try favoritesStore.load()
        } catch {
            present(error)
        }
    }

    func prepareExport(_ format: ExportFormat) {
        do {
            exportText = try ResultExporter.export(ScanExport(target: targetText, hosts: hosts), as: format)
            exportType = format
            showExporter = true
        } catch {
            present(error)
        }
    }

    private func run(_ request: ScanRequest) {
        persistFields()
        runTask = Task {
            do {
                let stream = try await controller.start(request)
                hosts = []
                scheduledCount = 0
                phase = .running
                for await event in stream {
                    apply(event)
                }
                phase = await controller.currentPhase()
            } catch let error as ScanValidationError {
                phase = await controller.currentPhase()
                if case .publicRangeRequiresAcknowledgement = error {
                    pendingAcknowledged = makeRequest(acknowledge: true)
                    showPublicConfirm = true
                    return
                }
                present(error)
            } catch {
                present(error)
            }
        }
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case .started(let count):
            scheduledCount = count
            phase = .running
        case .hostCompleted(let host):
            hosts.append(host)
        case .finished:
            phase = .completed
        case .cancelled:
            phase = .cancelled
        }
    }

    private func makeRequest(acknowledge: Bool) -> ScanRequest {
        var options = ScanOptions()
        options.maxConcurrentHosts = min(max(maxConcurrentHosts, 1), 256)
        options.probeTimeout = .milliseconds(max(timeoutMilliseconds, 1))
        return ScanRequest(
            targetText: targetText,
            portText: portText,
            options: options,
            acknowledgePublicRange: acknowledge
        )
    }

    private func persistFields() {
        let defaults = UserDefaults.standard
        defaults.set(targetText, forKey: Keys.target)
        defaults.set(portText, forKey: Keys.ports)
        defaults.set(maxConcurrentHosts, forKey: Keys.concurrency)
        defaults.set(timeoutMilliseconds, forKey: Keys.timeout)
    }

    private func present(_ error: Error) {
        if let validation = error as? ScanValidationError {
            errorMessage = validation.description
        } else if let favorite = error as? FavoriteStoreError {
            errorMessage = favorite.description
        } else {
            errorMessage = String(describing: error)
        }
        showError = true
    }
}

enum AppSupport {
    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("SubnetScout", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum Keys {
    static let target = "subnetscout.target"
    static let ports = "subnetscout.ports"
    static let concurrency = "subnetscout.concurrency"
    static let timeout = "subnetscout.timeout"
}
