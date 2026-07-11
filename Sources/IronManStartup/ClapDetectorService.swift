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

    func toggleListening() {
        isListening ? stop() : start()
    }

    func start() {
        if isListening { return }
        errorText = nil

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