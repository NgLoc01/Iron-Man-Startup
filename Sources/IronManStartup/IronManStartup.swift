import SwiftUI
import AppKit

@main
struct IronManStartupApp: App {
    var body: some Scene {
        MenuBarExtra("Iron Man Startup", systemImage: "waveform.circle") {
            ContentView()
                .frame(minWidth: 460, idealWidth: 500, minHeight: 720, idealHeight: 760)
        }
        .menuBarExtraStyle(.window)
    }
}