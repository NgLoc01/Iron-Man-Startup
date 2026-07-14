This is a macOS menu-bar app ("J.A.R.V.I.S") that listens for double-claps and reacts :

Inspiration:
https://www.youtube.com/watch?v=T_3AjPZSlTU

UI / app shell
* SwiftUI builds the whole interface (popover, sliders, canvas soundwave graph).
* AppKit handles what SwiftUI can't: hiding the Dock icon, opening URLs, activating other apps, and quitting.

Audio / clap detection (ClapDetectorService.swift)
* AVFoundation requests mic permission and taps the raw audio stream in real time.
* A custom RMS loudness calculation plus rising-edge + timing-window logic turns two loud spikes within 100–600ms into a "double clap" event.

Opening the most recent VS Code project
* Reads VS Code's own storage.json (~/Library/Application Support/Code/User/globalStorage/storage.json) with JSONSerialization (no official API exists) to find the most recently opened folder, then launches it via Process.

Opening the YouTube link
* NSWorkspace.shared.open(url:) with a hardcoded YouTube URL.
