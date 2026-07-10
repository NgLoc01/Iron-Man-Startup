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

    func toggleListening() {
        isListening.toggle()
    }
}