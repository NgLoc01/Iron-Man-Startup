import SwiftUI
import AppKit

@main
struct IronManStartupApp: App {
    @StateObject private var detector = DoubleClapDetectorService()

    var body: some Scene {
        MenuBarExtra("Iron Man Startup", systemImage: "waveform.circle") {
            ContentView()
                .frame(minWidth: 460, idealWidth: 500, minHeight: 720, idealHeight: 760)
                .environmentObject(detector)
        }
        .menuBarExtraStyle(.window)
    }
}