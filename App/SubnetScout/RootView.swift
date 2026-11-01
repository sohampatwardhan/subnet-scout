import ScannerCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: ScanSessionModel

    var body: some View {
        NavigationSplitView {
            FavoritesSidebar(model: model)
        } detail: {
            ScanDetail(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .macMinimumFrame()
        .alert("Scan not started", isPresented: $model.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "This range includes public addresses",
            isPresented: $model.showPublicConfirm,
            titleVisibility: .visible
        ) {
            Button("Scan anyway", role: .destructive) {
                model.confirmPublicScan()
            }
            Button("Don't scan", role: .cancel) {
                model.declinePublicScan()
            }
        } message: {
            Text("Subnet Scout will send a packet to every address in the range. Scan only networks you administer.")
        }
        .fileExporter(
            isPresented: $model.showExporter,
            document: ExportedScan(text: model.exportText),
            contentType: model.exportType.utType,
            defaultFilename: "subnet-scout"
        ) { _ in }
    }
}

private struct FavoritesSidebar: View {
    @Bindable var model: ScanSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(model.favorites) { favorite in
                Button {
                    model.choose(favorite)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favorite.name)
                            .font(.headline)
                        Text(favorite.targetText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use favorite \(favorite.name)")
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        model.deleteFavorite(favorite)
                    }
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        model.deleteFavorite(favorite)
                    }
                }
            }
            .overlay {
                if model.favorites.isEmpty {
                    ContentUnavailableView(
                        "No saved ranges",
                        systemImage: "star",
                        description: Text("Save the target you use for this lab or home network.")
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Favorite name", text: $model.favoriteName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.saveFavorite()
                } label: {
                    Label("Save range", systemImage: "star")
                }
                .disabled(model.favoriteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Text("Probes start only after you press Start. Public addresses ask first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .navigationTitle("Favorites")
    }
}

private struct ScanDetail: View {
    @Bindable var model: ScanSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            progress
            filters
            results
        }
        .padding()
        .navigationTitle("Subnet Scout")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("IPv4 address, range, or CIDR", text: $model.targetText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Scan target")
            HStack {
                Button {
                    model.useCurrentSubnet()
                } label: {
                    Label("Current subnet", systemImage: "wifi")
                }
                if let subnetMessage = model.subnetMessage {
                    Text(subnetMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Ports, such as 22,80,443 or 8000-8002", text: $model.portText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Ports")
            Text("Leave ports blank to probe the built-in common list.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Stepper(value: $model.maxConcurrentHosts, in: 1...256) {
                    Text("Concurrency \(model.maxConcurrentHosts)")
                }
                Stepper(value: $model.timeoutMilliseconds, in: 200...10_000, step: 100) {
                    Text("Timeout \(model.timeoutMilliseconds) ms")
                }
            }
            HStack {
                Button {
                    model.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(!model.canStart)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Start scan")

                Button {
                    model.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(!model.canPause)
                .accessibilityLabel("Pause scan")

                Button {
                    model.resume()
                } label: {
                    Label("Resume", systemImage: "playpause.fill")
                }
                .disabled(!model.canResume)
                .accessibilityLabel("Resume scan")

                Button(role: .destructive) {
                    model.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .disabled(!model.canCancel)
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityLabel("Cancel scan")

                Spacer()
                exportMenu
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("CSV") { model.prepareExport(.csv) }
            Button("JSON") { model.prepareExport(.json) }
            Button("TXT") { model.prepareExport(.txt) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel("Export results")
    }

    private var progress: some View {
        HStack {
            Text("\(model.hosts.count) of \(model.scheduledCount) hosts")
            Text("·")
            Text(model.phase.rawValue.capitalized)
            Spacer()
            Text("\(model.visibleHosts.filter { $0.status == .alive }.count) alive shown")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var filters: some View {
        HStack {
            TextField("Filter address or name", text: $model.filterText)
                .textFieldStyle(.roundedBorder)
            Toggle("Alive only", isOn: $model.aliveOnly)
            Picker("Sort", selection: $model.sort) {
                Text("Address").tag(ResultSort.address)
                Text("Name").tag(ResultSort.displayName)
                Text("Latency").tag(ResultSort.latency)
                Text("Open ports").tag(ResultSort.openPortCount)
                Text("Status").tag(ResultSort.status)
            }
            .pickerStyle(.menu)
            Toggle("Ascending", isOn: $model.ascending)
        }
    }

    private var results: some View {
        Table(model.visibleHosts) {
            TableColumn("Address") { row in
                Text(row.address.description).monospacedDigit()
            }
            TableColumn("Name") { row in
                Text(row.displayName ?? "")
            }
            TableColumn("Status") { row in
                Text(row.status.rawValue.capitalized)
                    .foregroundStyle(row.status == .alive ? Color.accentColor : .secondary)
            }
            TableColumn("Latency") { row in
                Text(latencyText(row))
                    .monospacedDigit()
            }
            TableColumn("Open ports") { row in
                Text(row.openPorts.map(String.init).joined(separator: ", "))
                    .monospacedDigit()
            }
        }
        .overlay {
            if model.visibleHosts.isEmpty {
                ContentUnavailableView(
                    model.hosts.isEmpty ? "No hosts yet" : "No matching hosts",
                    systemImage: "tablecells",
                    description: Text(
                        model.hosts.isEmpty
                            ? "Start a scan to fill this table."
                            : "The filter is hiding every recorded host."
                    )
                )
            }
        }
    }

    private func latencyText(_ row: HostObservation) -> String {
        guard let latency = row.latency else { return "" }
        let milliseconds = Int((latency.components.seconds * 1000) + latency.components.attoseconds / 1_000_000_000_000_000)
        return "\(milliseconds) ms"
    }
}

private extension View {
    @ViewBuilder
    func macMinimumFrame() -> some View {
        #if os(macOS)
        self.frame(minWidth: 760, minHeight: 560)
        #else
        self
        #endif
    }
}

private extension ExportFormat {
    var utType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .json: .json
        case .txt: .plainText
        }
    }
}
