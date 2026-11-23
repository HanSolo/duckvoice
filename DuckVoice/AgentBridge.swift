import Foundation

/// Starts the Java agent and talks to it in JSON lines (see Protocol.java). Java is the brain; this class only moves lines.
final class AgentBridge: @unchecked Sendable {
    enum Event {
        case ready
        case say(String)
        case confirm(String)
        case tool(name: String, arguments: String, result: String, isError: Bool)
        case error(String)
        case log(String)
        case exited(Int32)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let process   = Process()
    private let toAgent   = Pipe()
    private let fromAgent = Pipe()
    private let errors    = Pipe()
    private let lock      = NSLock()
    private var outBuffer = Data()
    private var errBuffer = Data()

    
    init(jarPath: String) {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.events       = stream
        self.continuation = continuation
        process.executableURL  = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments      = ["java", "-jar", jarPath, "--json"]
        process.standardInput  = toAgent
        process.standardOutput = fromAgent
        process.standardError  = errors
        
        var environment = ProcessInfo.processInfo.environment
        
        for (key, value) in AgentBridge.fileSettings() where environment[key] == nil { environment[key] = value }
        
        process.environment = environment
    }

    
    // A GUI app does not get your shell variables.
    // Settings missing from the environment (for example from the Xcode scheme) are read from ~/.duck-voice.env, lines like KEY=value.
    static func fileSettings() -> [String: String] {
        let path = NSHomeDirectory() + "/.duck-voice.env"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var settings: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard let equals = line.firstIndex(of: "=") else { continue }
            
            let key   = line[line.startIndex..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" { value = String(value.dropFirst().dropLast()) }
            settings[key] = value
        }
        return settings
    }

    static func setting(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key] ?? fileSettings()[key]
    }

    func start() throws {
        fromAgent.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isErrorStream: false)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isErrorStream: true)
        }
        process.terminationHandler = { [weak self] process in
            self?.continuation.yield(.exited(process.terminationStatus))
            self?.continuation.finish()
        }
        try process.run()
    }

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        try? toAgent.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
    }

    func stop() {
        send(["type": "quit"])
        try? toAgent.fileHandleForWriting.close()
    }

    private func consume(_ data: Data, isErrorStream: Bool) {
        if data.isEmpty { return }
        lock.lock()
        defer { lock.unlock() }
        if isErrorStream {
            errBuffer.append(data)
            for line in drainLines(&errBuffer) { continuation.yield(.log(line)) }
        } else {
            outBuffer.append(data)
            for line in drainLines(&outBuffer) { handle(line) }
        }
    }

    private func drainLines(_ buffer: inout Data) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    private func handle(_ line: String) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let type = object["type"] as? String else {
            continuation.yield(.log("not protocol: " + line))
            return
        }
        switch type {
            case "ready"  : continuation.yield(.ready)
            case "say"    : continuation.yield(.say(object["text"] as? String ?? ""))
            case "confirm": continuation.yield(.confirm(object["message"] as? String ?? ""))
            case "tool"   : continuation.yield(.tool(name: object["name"] as? String ?? "", arguments: object["arguments"] as? String ?? "", result: object["result"] as? String ?? "", isError: object["isError"] as? Bool ?? false))
            case "error"  : continuation.yield(.error(object["message"] as? String ?? ""))
            default       : continuation.yield(.log("unknown message: " + line))
        }
    }
}
