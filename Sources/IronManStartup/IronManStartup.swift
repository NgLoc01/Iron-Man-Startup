import SwiftUI

@main
struct IronManStartupApp: App {
    var body: some Scene {
        MenuBarExtra("Iron Man Startup", systemImage: "waveform.circle") {
            Text("Loading...")
                .padding()
                .frame(minWidth: 460, minHeight: 100)
        }
        .menuBarExtraStyle(.window)
    }
}
