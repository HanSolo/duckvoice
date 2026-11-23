import AVFoundation
import Foundation
import Observation

struct Line: Identifiable {
    enum Kind { case you, assistant, tool, error, log }
    let id = UUID()
    let kind: Kind
    let text: String
}

@MainActor
@Observable
final class ViewModel {
    enum Phase { case starting, idle, thinking, speaking, confirming, stopped }

    var phase               : Phase  = .starting
    var lines               : [Line] = []
    var partial             : String = ""
    var isListening         : Bool   = false
    var pendingConfirmation : String?

    private var bridge   : AgentBridge?
    private let listener : SpeechListener = SpeechListener()
    private let speaker  : Speaker        = Speaker()

    /// Words that count as a clear yes. Everything else, including "yes, but wait", is a no.
    private static let yesPhrases: Set<String> = ["yes", "yeah", "yep", "yes please", "yes book it", "book it", "correct", "confirm", "confirmed", "that is correct", "that's correct", "quack"]

    func start() async {
        guard bridge == nil else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            lines.append(Line(kind: .error, text: "Microphone access was denied. Allow it for your terminal (or this app) in System Settings, Privacy & Security, Microphone."))
            return
        }
        listener.onPartial = { [weak self] text in self?.partial = text }
        guard let jar = AgentBridge.setting("DUCK_AGENT_JAR") else {
            lines.append(Line(kind: .error, text: "DUCK_AGENT_JAR is not set. Set it in the Xcode scheme or in ~/.duck-voice.env."))
            return
        }
        let bridge = AgentBridge(jarPath: jar)
        self.bridge = bridge
        do { try bridge.start() } catch {
            lines.append(Line(kind: .error, text: "Could not start the Java agent: \(error)"))
            return
        }
        for await event in bridge.events { await handle(event) }
    }

    func stop() {
        bridge?.stop()
    }

    private func handle(_ event: AgentBridge.Event) async {
        switch event {
            case .ready:
                phase = .idle
            case .say(let text):
                lines.append(Line(kind: .assistant, text: text))
                phase = .speaking
                await speaker.speak(text)
                if phase == .speaking { phase = .idle }
            case .confirm(let message):
                pendingConfirmation = message
                phase = .confirming
                lines.append(Line(kind: .assistant, text: "Please confirm: " + message))
                await speaker.speak("Please confirm. " + message + " Say yes or no.")
            case .tool(let name, let arguments, let result, let isError):
                lines.append(Line(kind: .tool, text: "\(name) \(arguments) \(isError ? "ERROR " : "-> ")\(result.prefix(200))"))
            case .error(let message):
                lines.append(Line(kind: .error, text: message))
                if phase != .confirming { phase = .idle }
            case .log(let text):
                lines.append(Line(kind: .log, text: text))
            case .exited(let status):
                lines.append(Line(kind: .error, text: "The Java agent ended with status \(status)."))
                phase = .stopped
        }
    }

    /// The microphone button: first press starts listening, second press ends it and uses what was heard.
    func toggleListening() async {
        if isListening {
            isListening = false
            let heard = await listener.stop()
            partial = ""
            if phase == .confirming { answer(yes: Self.isClearYes(heard), heard: heard) } else { sendUtterance(heard) }
        } else if phase == .idle || phase == .confirming {
            speaker.stop()
            do {
                try await listener.start()
                isListening = true
            } catch {
                lines.append(Line(kind: .error, text: "Could not start listening: \(error)"))
            }
        }
    }

    /// The Yes and No buttons on the screen. They are the user's answer just like the voice.
    func answer(yes: Bool, heard: String? = nil) {
        guard pendingConfirmation != nil else { return }
        speaker.stop()
        lines.append(Line(kind: .you, text: (heard.map { "\"\($0)\" " } ?? "") + (yes ? "(yes)" : "(no)")))
        pendingConfirmation = nil
        phase = .thinking
        bridge?.send(["type": "answer", "yes": yes])
    }

    private func sendUtterance(_ text: String) {
        guard !text.isEmpty else { return }
        lines.append(Line(kind: .you, text: text))
        phase = .thinking
        bridge?.send(["type": "utterance", "text": text])
    }

    static func isClearYes(_ heard: String) -> Bool {
        let cleaned = heard.lowercased().filter { $0.isLetter || $0.isWhitespace || $0 == "'" }.trimmingCharacters(in: .whitespaces)
        return yesPhrases.contains(cleaned)
    }
}
