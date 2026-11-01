import SwiftUI

@main
@MainActor
struct SubnetScoutApp: App {
    @State private var model = ScanSessionModel.live()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
