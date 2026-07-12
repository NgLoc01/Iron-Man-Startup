import AppKit
import AVFoundation
import Foundation

enum ClapPulseKind {
    case single
    case double
}

struct ClapLogEntry: Identifiable {
    let id = UUID()
    let text: String
    let time: String
}

private enum VSCodeFolderSelection {
    case success(String)
    case failure(String)
}

final class DoubleClapDetectorService: ObservableObject, @unchecked Sendable {
    private let historyLength = 120
    private let debounceMs: Double = 120
    private let minGapMs: Double = 100
    private let maxGapMs: Double = 600

    @Published var isListening = false
    @Published var threshold: Float = 0.05
    @Published var level: Float = 0
    @Published var errorText: String?
    @Published var logs: [ClapLogEntry] = []
    @Published var history: [Float] = Array(repeating: 0, count: 120)
    @Published var pulseKind: ClapPulseKind?

    private var audioEngine: AVAudioEngine?
    private var isAbove = false
    private var lastTriggerMs: Double = 0
    private var pendingFirstMs: Double?
    private var pulseResetWorkItem: DispatchWorkItem?
    private var armedVSCodeFolderPath: String?

    func toggleListening() {
        isListening ? stop() : start()
    }

    func start() {
        if isListening { return }
        errorText = nil
        armedVSCodeFolderPath = mostRecentVSCodeFolderPath()

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if !granted {
                    self.errorText = "Microphone access was denied."
                    return
                }
                self.startEngine()
            }
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        pulseResetWorkItem?.cancel()
        isListening = false
        level = 0
        isAbove = false
        pendingFirstMs = nil
        pulseKind = nil
        addLog("Listening stopped")
    }

    private func startEngine() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let rms = Self.computeRms(buffer: buffer)
            let nowMs = Date().timeIntervalSince1970 * 1000
            DispatchQueue.main.async {
                self?.processSample(rms: rms, nowMs: nowMs)
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            isListening = true
            addLog("Listening started")
        } catch {
            errorText = "Failed to start microphone: \(error.localizedDescription)"
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
        }
    }

    private func processSample(rms: Float, nowMs: Double) {
        level = rms
        history.append(rms)
        if history.count > historyLength {
            history.removeFirst(history.count - historyLength)
        }

        let above = rms > threshold
        if above && !isAbove {
            isAbove = true
            registerClap(nowMs: nowMs)
        } else if !above {
            isAbove = false
        }

        if let pendingFirstMs, nowMs - pendingFirstMs > maxGapMs {
            self.pendingFirstMs = nil
        }
    }

    private func registerClap(nowMs: Double) {
        if nowMs - lastTriggerMs < debounceMs { return }
        lastTriggerMs = nowMs

        if pendingFirstMs == nil {
            pendingFirstMs = nowMs
            fireEvent(.single)
            return
        }

        guard let firstMs = pendingFirstMs else { return }
        let gap = nowMs - firstMs

        if gap >= minGapMs && gap <= maxGapMs {
            pendingFirstMs = nil
            fireEvent(.double)
        } else if gap > maxGapMs {
            pendingFirstMs = nowMs
            fireEvent(.single)
        }
    }

    private func fireEvent(_ kind: ClapPulseKind) {
        pulseKind = kind
        pulseResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.pulseKind = nil
            if kind == .double {
                self?.openYouTubeLink()
            }
        }
        pulseResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)

        switch kind {
        case .single:
            addLog("Clap (waiting for second...)")
        case .double:
            addLog("Double clap detected")
        }
    }

    private func openYouTubeLink() {
        stop()
        guard let url = URL(string: "https://www.youtube.com/watch?v=pAgnJDJN4VA") else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)

        _ = openArmedMostRecentVSCodeProject()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.microsoft.VSCode")
                .first?
                .activate()
        }
    }

    private func mostRecentVSCodeFolderPath() -> String? {
        let selection = resolveMostRecentVSCodeFolderPath()
        if case let .failure(message) = selection {
            addLog(message)
            return nil
        }
        if case let .success(path) = selection {
            return path
        }
        return nil
    }

    private func resolveMostRecentVSCodeFolderPath() -> VSCodeFolderSelection {
        guard let storageURL = firstExistingVSCodeStorageURL() else {
            return .failure("VS Code storage.json was not found")
        }
        guard let data = try? Data(contentsOf: storageURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Unable to read VS Code storage.json")
        }

        // Prefer menubar Open Recent ordering — reflects what the user last opened.
        let menuRecentPaths = recentFolderPathsFromMenuBarData(root)
        if let selected = firstValidRecentPath(fromPaths: menuRecentPaths) {
            return .success(selected)
        }

        let folderUris = backupWorkspaceFolderUris(root).reversed()

        if folderUris.isEmpty {
            return .failure("VS Code has no recent folder entries")
        }

        let fallbackPaths = folderUris.compactMap { uri -> String? in
            guard let url = URL(string: uri), url.isFileURL else { return nil }
            return url.standardizedFileURL.path
        }

        if let selected = firstValidRecentPath(fromPaths: fallbackPaths) {
            return .success(selected)
        }

        return .failure("No valid recent VS Code folder exists on disk")
    }

    private func recentFolderPathsFromMenuBarData(_ root: [String: Any]) -> [String] {
        guard let menuData = root["lastKnownMenubarData"] else { return [] }
        var paths: [String] = []
        collectOpenRecentFolderPaths(from: menuData, into: &paths)
        return paths
    }

    private func backupWorkspaceFolderUris(_ root: [String: Any]) -> [String] {
        guard let backupWorkspaces = root["backupWorkspaces"] as? [String: Any],
              let folders = backupWorkspaces["folders"] as? [[String: Any]] else {
            return []
        }
        return folders.compactMap { $0["folderUri"] as? String }
    }

    private func collectOpenRecentFolderPaths(from node: Any, into paths: inout [String]) {
        if let dict = node as? [String: Any] {
            if let id = dict["id"] as? String,
               id == "openRecentFolder",
               let uri = dict["uri"] as? [String: Any],
               let scheme = uri["scheme"] as? String,
               scheme == "file",
               let path = uri["path"] as? String {
                paths.append(path)
            }
            for value in dict.values {
                collectOpenRecentFolderPaths(from: value, into: &paths)
            }
            return
        }
        if let array = node as? [Any] {
            for value in array {
                collectOpenRecentFolderPaths(from: value, into: &paths)
            }
        }
    }

    private func firstValidRecentPath(fromPaths paths: [String]) -> String? {
        for rawPath in paths {
            let path = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            if exists && isDirectory.boolValue && isVisibleProjectPath(path) && !isRunningFolderPath(path) {
                return path
            }
        }
        return nil
    }

    private func isVisibleProjectPath(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        for component in components {
            if component == "/" { continue }
            if component.hasPrefix(".") { return false }
        }
        return true
    }

    private func isRunningFolderPath(_ path: String) -> Bool {
        let candidate = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        for root in runningContextPaths() {
            if candidate == root || candidate.hasPrefix(root + "/") || root.hasPrefix(candidate + "/") {
                return true
            }
        }
        return false
    }

    private func runningContextPaths() -> [String] {
        var paths: [String] = []

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .standardizedFileURL.path
        if cwd != "/" { paths.append(cwd) }

        let executableDir = URL(fileURLWithPath: CommandLine.arguments[0], isDirectory: false)
            .deletingLastPathComponent()
            .standardizedFileURL.path
        if executableDir != "/" { paths.append(executableDir) }

        return Array(Set(paths))
    }

    private func firstExistingVSCodeStorageURL() -> URL? {
        for candidate in vscodeStorageCandidates() {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func vscodeStorageCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/Code/User/globalStorage/storage.json"),
            home.appendingPathComponent(".config/Code/User/globalStorage/storage.json")
        ]
    }

    private func openArmedMostRecentVSCodeProject() -> Bool {
        let path: String
        if let livePath = mostRecentVSCodeFolderPath() {
            path = livePath
        } else if let armedVSCodeFolderPath {
            path = armedVSCodeFolderPath
        } else {
            addLog("No valid recent VS Code folder exists on disk")
            return false
        }

        let codeCandidates = [
            "/opt/homebrew/bin/code",
            "/usr/local/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        ]

        for codePath in codeCandidates where FileManager.default.isExecutableFile(atPath: codePath) {
            if runProcess(executablePath: codePath, arguments: [path], currentDirectory: NSHomeDirectory()) {
                addLog("Opened recent VS Code project")
                return true
            }
        }

        addLog("Could not launch VS Code CLI to open recent project")
        return false
    }

    private func runProcess(executablePath: String, arguments: [String], currentDirectory: String? = nil) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        }
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func addLog(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entry = ClapLogEntry(text: text, time: formatter.string(from: Date()))
        logs.insert(entry, at: 0)
        if logs.count > 12 {
            logs = Array(logs.prefix(12))
        }
    }

    private static func computeRms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channel = channelData[0]
        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 { return 0 }

        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channel[i]
            sumSquares += sample * sample
        }
        return sqrt(sumSquares / Float(frameLength))
    }
}