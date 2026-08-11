import SwiftUI

@main
struct LectureCaptionApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView(appState: appState)
        }
        .defaultSize(width: 1_080, height: 720)
        .windowResizability(.contentSize)
    }
}
