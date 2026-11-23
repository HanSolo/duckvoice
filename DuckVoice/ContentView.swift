import SwiftUI

struct ContentView: View {
    @Bindable var model: ViewModel

    var body: some View {
        VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.lines) { line in
                            Text(line.text)
                                .foregroundStyle(color(for: line.kind))
                                .font(line.kind == .tool || line.kind == .log ? .system(.caption, design: .monospaced) : .body)
                                .frame(maxWidth: .infinity, alignment: line.kind == .you ? .trailing : .leading)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: model.lines.count) { _, _ in
                    if let last = model.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            if let message = model.pendingConfirmation {
                VStack(spacing: 8) {
                    Text(message).font(.headline).multilineTextAlignment(.center)
                    HStack {
                        Button("Yes, book it") { model.answer(yes: true) }.buttonStyle(.borderedProminent)
                        Button("No") { model.answer(yes: false) }
                    }
                    Text("or press the microphone and say yes or no").font(.caption).foregroundStyle(.secondary)
                }
                .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }

            Text(model.isListening ? (model.partial.isEmpty ? "Listening..." : model.partial) : status)
                .foregroundStyle(.secondary).frame(minHeight: 22)

            Button { Task { await model.toggleListening() } } label: {
                Label(model.isListening ? "Done" : "Talk", systemImage: model.isListening ? "stop.circle.fill" : "mic.circle.fill").font(.title2)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!(model.phase == .idle || model.phase == .confirming))
            .keyboardShortcut(.space, modifiers: [])
        }
        .padding()
        .frame(minWidth: 460, minHeight: 520)
    }

    private var status: String {
        switch model.phase {
        case .starting: "Starting the agent..."
        case .idle: "Press Talk and ask for a booking."
        case .thinking: "Thinking..."
        case .speaking: "Speaking..."
        case .confirming: "Waiting for your answer."
        case .stopped: "The agent has stopped."
        }
    }

    private func color(for kind: Line.Kind) -> Color {
        switch kind {
        case .you: .blue
        case .assistant: .primary
        case .tool, .log: .secondary
        case .error: .red
        }
    }
}
