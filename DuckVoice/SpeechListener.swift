import AVFoundation
import Speech

enum ListenerError: Error { case unsupportedLocale, noAudioFormat, noConverter }

/// Push-to-talk speech recognition with SpeechAnalyzer and SpeechTranscriber, on the device. start() opens the microphone, stop() returns what was heard.
@MainActor
final class SpeechListener {
    var onPartial: ((String) -> Void)?

    private var engine       : AVAudioEngine?
    private var analyzer     : SpeechAnalyzer?
    private var inputBuilder : AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask  : Task<String, Error>?

    
    func start(locale: Locale = Locale(identifier: "en-US")) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { throw ListenerError.unsupportedLocale }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])

        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        guard let format : AVAudioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw ListenerError.noAudioFormat }
        
        let analyzer : SpeechAnalyzer = SpeechAnalyzer(modules: [transcriber])
        let (sequence, builder)       = AsyncStream.makeStream(of: AnalyzerInput.self)
        
        self.analyzer     = analyzer
        self.inputBuilder = builder

        resultsTask = Task { [weak self] in
            var finalText    : String = ""
            var volatileText : String = ""
            for try await result in transcriber.results {
                let text : String = String(result.text.characters)
                if result.isFinal {
                    finalText += text
                    volatileText = ""
                } else {
                    volatileText = text
                }
                self?.onPartial?(finalText + volatileText)
            }
            return finalText + volatileText
        }
        try await analyzer.start(inputSequence: sequence)

        let engine      : AVAudioEngine    = AVAudioEngine()
        let input       : AVAudioInputNode = engine.inputNode
        let inputFormat : AVAudioFormat    = input.outputFormat(forBus: 0)
        
        guard let converter : AVAudioConverter = AVAudioConverter(from: inputFormat, to: format) else { throw ListenerError.noConverter }
        
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let ratio    : Double = format.sampleRate / buffer.format.sampleRate
            let capacity : UInt32 = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            
            guard let converted : AVAudioPCMBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            
            var supplied : Bool = false
            var error    : NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil && converted.frameLength > 0 { builder.yield(AnalyzerInput(buffer: converted)) }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// Closes the microphone and returns the final text.
    func stop() async -> String {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        inputBuilder?.finish()
        inputBuilder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        let text : String = (try? await resultsTask?.value) ?? ""
        resultsTask = nil
        
        let regex       = try! Regex("\\b\(NSRegularExpression.escapedPattern(for: "quack"))\\b").ignoresCase()
        let matches     = text.matches(of: regex)
        let noOfMatches = matches.count
                
        // "Translation" from ducklingo to english
        let receivedText : String
        switch noOfMatches {
            case 0 : receivedText = text
            case 1 : receivedText = "yes"
            case 2 : receivedText = "book an appointment for the owner of daisy for tomorrow"
            case 3 : receivedText = "incoherent quacking problem"
            default: receivedText = text
        }
        
        return receivedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
