import SwiftUI
import AppKit

/*
Current app setup:
- sharedDoubleClapDetector: the one DoubleClapDetectorService instance the whole app uses
- AppDelegate: on launch, hides the Dock icon and starts listening automatically
- IronManStartupApp: builds the menu bar scene, hands ContentView the shared detector
*/

let sharedDoubleClapDetector = DoubleClapDetectorService() //global singleton instance, created once at app launch

final class AppDelegate: NSObject, NSApplicationDelegate { //runs automatically once, the moment the app launches
    func applicationDidFinishLaunching(_ notification: Notification) { 
        NSApp.setActivationPolicy(.accessory) //no Dock icon, menu bar only
        sharedDoubleClapDetector.start() //auto-start listening, no click needed
    }
}

@main
struct IronManStartupApp: App {
    @StateObject private var detector = sharedDoubleClapDetector //adopts the existing shared instance
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate //registers AppDelegate as the real app delegate so AppDelegate's code (start up code) actually runs
    

    var body: some Scene {
        MenuBarExtra("Iron Man Startup", systemImage: "waveform.circle") { //menu bar icon + popover
            ContentView()
                .frame(minWidth: 460, idealWidth: 500, minHeight: 720, idealHeight: 760)
                .environmentObject(detector) //makes detector reachable via @EnvironmentObject in ContentView
        }
        .menuBarExtraStyle(.window) 
    }
}