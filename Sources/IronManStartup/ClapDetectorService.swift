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
    @Published var isListening = false
    @Published var threshold: Float = 0.05
    @Published var level: Float = 0
    @Published var errorText: String?
    @Published var logs: [ClapLogEntry] = []
    @Published var history: [Float] = Array(repeating: 0, count: 120)
    @Published var pulseKind: ClapPulseKind?

    private var audioEngine: AVAudioEngine?

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
        isListening = false
        level = 0
    }

    private func startEngine() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let rms = Self.computeRms(buffer: buffer)
            DispatchQueue.main.async {
                self?.level = rms
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            isListening = true
        } catch {
            errorText = "Failed to start microphone: \(error.localizedDescription)"
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
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