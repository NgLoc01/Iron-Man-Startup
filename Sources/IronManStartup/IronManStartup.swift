import SwiftUI
import AppKit

let sharedDoubleClapDetector = DoubleClapDetectorService()

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        sharedDoubleClapDetector.start()
    }
}

@main
struct IronManStartupApp: App {
    @StateObject private var detector = sharedDoubleClapDetector
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Iron Man Startup", systemImage: "waveform.circle") {
            ContentView()
                .frame(minWidth: 460, idealWidth: 500, minHeight: 720, idealHeight: 760)
                .environmentObject(detector)
        }
        .menuBarExtraStyle(.window)
    }
}