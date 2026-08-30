import SwiftUI

@main
struct MetraCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(MetraBrand.signalTeal)
        }
    }
}
