import AVFoundation

/// Speaks text and returns when the speech is finished (or was stopped).
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer : AVSpeechSynthesizer = AVSpeechSynthesizer()
    private var waiting     : CheckedContinuation<Void, Never>?

    
    override init() {
        super.init()
        synthesizer.delegate = self
    }

    
    func speak(_ text: String) async {
        stop()
        await withCheckedContinuation { continuation in
            waiting = continuation
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        waiting?.resume()
        waiting = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
}
