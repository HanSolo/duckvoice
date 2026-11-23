Xcode App template: DuckVoice
1. Xcode > New Project > macOS > App. Name DuckVoice, Interface SwiftUI, Language Swift. Untick tests and storage.
2. Delete the generated DuckVoiceApp.swift and ContentView.swift. Drag in the six .swift files of this folder (copy items, add to target).
3. Target > General: Minimum Deployments macOS 26.0.
   Target > Build Settings: Swift Language Version = Swift 5.
4. Target > Signing & Capabilities: remove "App Sandbox" (the app starts java). Under Hardened Runtime tick "Audio Input".
5. Target > Info: add "Privacy - Microphone Usage Description" = "DuckVoice listens to your voice to book duck clinic visits."
6. Settings for the Java agent, in ~/.duck-voice.env (one KEY=value per line), or in Product > Scheme > Edit Scheme > Run > Environment Variables:
     DUCK_AGENT_JAR=/full/path/to/duck-voice-agent/target/duck-voice-agent.jar
     ANTHROPIC_BASE_URL=http://localhost:11434
     ANTHROPIC_API_KEY=ollama
     ANTHROPIC_MODEL=qwen3.8:27b
     ANTHROPIC_MAX_TOKENS=4096
     MCP_URL=http://localhost:8080/duck-clinic/api/mcp
7. duck-clinic must be running (./duck-voice.sh start-clinic) and the jar built (./duck-voice.sh setup).

