import SwiftUI

@main
struct DuckVoiceApp: App {
    @State private var model = ViewModel()

    var body: some Scene {
        WindowGroup("Duck Clinic Voice") {
            ContentView(model: model)
                .task { await model.start() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
        }
    }
}
