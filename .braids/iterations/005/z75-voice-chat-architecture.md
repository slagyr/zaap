# Voice Chat Architecture — zaap-z75

## Summary

Zaap connects to the OpenClaw gateway as a **paired node** over WebSocket, enabling bidirectional voice conversations. The user speaks, iOS transcribes locally, the transcript is sent to the gateway as a `voice.transcript` node event, the agent processes it and streams a response back, and Zaap speaks it via TTS.

## Protocol Choice: Node WebSocket (Recommended)

### Why Node Protocol

The gateway already has full node support. When Zaap connects as a node:

1. **Pairing** — one-time setup via `node.pair.request` → operator approval → token issued
2. **Bidirectional events** — gateway can push `node.invoke.request` events; Zaap can emit `voice.transcript`, `agent.request`, `chat.subscribe`, etc.
3. **Chat subscriptions** — Zaap subscribes to a session key and receives streamed agent responses in real-time
4. **No new server code** — the gateway's `handleNodeEvent` already handles `voice.transcript` with deduplication, session routing, and agent invocation

### Alternatives Considered

| Approach | Pros | Cons |
|----------|------|------|
| **Node WS protocol** ✅ | Zero server changes, bidirectional, battle-tested by Android | Requires implementing WS + pairing in Swift |
| Custom REST endpoint | Simpler client | No streaming, no push, polling needed |
| Custom WS endpoint | Could be simpler | Duplicates existing infra, needs new server code |

## Connection Lifecycle

```
┌─────────┐         ┌─────────────────┐
│  Zaap   │  WS     │  OpenClaw GW    │
│  (iOS)  │◄───────►│  (port 18789)   │
└────┬────┘         └────────┬────────┘
     │                       │
     │  ← connect.challenge  │   (server sends nonce)
     │                       │
     │  → connect            │   (client sends auth + device info)
     │    { minProtocol: 1,  │
     │      maxProtocol: 1,  │
     │      client: {        │
     │        id: "zaap",    │
     │        mode: "node",  │
     │        platform: "iOS"|
     │        version: "1.0" │
     │      },               │
     │      caps: ["voice",  │
     │        "camera"],     │
     │      device: {        │
     │        id: <nodeId>,  │
     │        publicKey,     │
     │        signature,     │
     │        signedAt,      │
     │        nonce          │
     │      },               │
     │      role: "node"     │
     │    }                  │
     │                       │
     │  ← hello-ok           │   (protocol negotiated)
     │                       │
     │  → node.event         │   (subscribe to chat session)
     │    { event:           │
     │      "chat.subscribe",│
     │      payloadJSON:     │
     │      {"sessionKey":   │
     │       "zaap-voice"}   │
     │    }                  │
     │                       │
```

## Voice Conversation Flow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Micro-  │    │  Speech  │    │ Gateway  │    │  Agent   │
│  phone   │    │  Recog.  │    │   WS     │    │          │
└────┬─────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘
     │               │              │               │
     │  audio stream │              │               │
     │──────────────►│              │               │
     │               │              │               │
     │               │ transcript   │               │
     │               │ (on silence) │               │
     │               │─────────────►│               │
     │               │  node.event  │               │
     │               │  voice.      │  agentCommand │
     │               │  transcript  │──────────────►│
     │               │              │               │
     │               │              │  ← chat.event │
     │               │              │◄──────────────│
     │               │              │  (streamed    │
     │               │              │   tokens)     │
     │               │              │               │
     │  ◄──── AVSpeechSynthesizer speaks response   │
     │               │              │               │
```

### Node Event: `voice.transcript`

```json
{
  "type": "request",
  "method": "node.event",
  "id": "<uuid>",
  "params": {
    "event": "voice.transcript",
    "payloadJSON": "{\"text\":\"What's the weather like?\",\"sessionKey\":\"zaap-voice\",\"eventId\":\"<uuid>\"}"
  }
}
```

The gateway's `handleNodeEvent` already:
- Parses the payload, extracts `text` and `sessionKey`
- Deduplicates via fingerprint (eventId or text+timestamp)
- Resolves or creates a session
- Calls `agentCommand()` with `messageChannel: "node"`, `inputProvenance: { kind: "external_user", sourceChannel: "voice" }`

### Receiving Responses: `chat.subscribe`

After connecting, Zaap sends a `chat.subscribe` event with its session key. The gateway's `NodeSubscriptionManager` then forwards chat events (streamed tokens, completion) to all subscribed nodes for that session.

Events Zaap will receive:
- `chat.event` — streamed response tokens
- `chat.done` — response complete

## Implementation Components

### 1. GatewayConnection (Swift)

WebSocket client using `URLSessionWebSocketTask`:

```swift
class GatewayConnection: ObservableObject {
    @Published var state: ConnectionState = .disconnected

    private var webSocket: URLSessionWebSocketTask?
    private let nodeId: String      // from pairing
    private let token: String       // from pairing
    private let gatewayURL: URL     // ws://192.168.x.x:18789

    func connect()
    func disconnect()
    func sendEvent(_ event: String, payload: Codable)
    func sendVoiceTranscript(_ text: String, sessionKey: String)

    // Internal: message receive loop
    private func receiveLoop()
    private func handleMessage(_ data: Data)
    private func handleConnectChallenge(_ nonce: String)
    private func handleHelloOk()
    private func handleChatEvent(_ payload: ChatEventPayload)
}
```

### 2. NodePairingManager (Swift)

One-time pairing flow:

```swift
class NodePairingManager {
    // Generate Ed25519 keypair, store in Keychain
    func generateIdentity() -> (nodeId: String, publicKey: String, privateKey: SecKey)

    // Sign nonce for connect handshake
    func signChallenge(nonce: String) -> (signature: String, signedAt: Int)

    // Initiate pairing (user enters gateway URL)
    // 1. Connect WS
    // 2. Send node.pair.request
    // 3. Wait for approval (operator approves in dashboard)
    // 4. Receive token, store in Keychain
    func requestPairing(gatewayURL: URL) async throws -> PairingResult
}
```

### 3. VoiceEngine (Swift)

Speech recognition + VAD:

```swift
class VoiceEngine: ObservableObject {
    @Published var isListening = false
    @Published var currentTranscript = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: .current)
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?

    // Configuration
    let silenceThresholdSeconds: TimeInterval = 1.5
    let minimumTranscriptLength = 3

    func startListening()
    func stopListening()

    // VAD: restart silence timer on each new partial result
    // When timer fires → end-of-utterance detected → emit transcript
    var onUtteranceComplete: ((String) -> Void)?
}
```

**Key iOS constraints:**
- `SFSpeechRecognizer` requires authorization (`SFSpeechRecognizer.requestAuthorization`)
- Continuous recognition via `recognitionTask(with: SFSpeechAudioBufferRecognitionRequest)`
- Set `shouldReportPartialResults = true` for streaming partials
- VAD = silence timer reset on each `.partialResult`; fire on 1.5s silence
- Audio session: `.playAndRecord` category with `.defaultToSpeaker` option
- Must handle interruptions (phone calls, Siri)

### 4. ResponseSpeaker (Swift)

TTS for agent responses:

```swift
class ResponseSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false

    // Speak streamed response — buffer tokens, speak sentence-by-sentence
    func speakStreamed(_ tokens: AsyncStream<String>)
    func speakImmediate(_ text: String)
    func stop()

    // Interrupt: if user starts speaking while TTS is active, stop immediately
    func interrupt()
}
```

**TTS options analysis:**

| Engine | Latency | Quality | Offline | Cost |
|--------|---------|---------|---------|------|
| `AVSpeechSynthesizer` | ~50ms | Good (iOS 17+) | ✅ | Free |
| ElevenLabs API | 200-500ms | Excellent | ❌ | ~$0.30/1k chars |

**Recommendation:** Start with `AVSpeechSynthesizer` for v1. iOS 17+ voices (especially "Personal Voice") sound very natural. Add ElevenLabs as an option later via `talk.config` (gateway already exposes voice settings).

### 5. VoiceChatView (SwiftUI)

```swift
struct VoiceChatView: View {
    @StateObject var voiceEngine = VoiceEngine()
    @StateObject var gateway = GatewayConnection.shared
    @State var conversationLog: [ConversationEntry] = []

    // Visual states:
    // - Idle (mic icon, tap to start)
    // - Listening (animated waveform, shows partial transcript)
    // - Processing (thinking indicator)
    // - Speaking (animated speaker, shows response text)
}
```

## Pairing Flow (First-Time Setup)

```
User opens Zaap Settings → "Connect to OpenClaw"
  ↓
Enter gateway address (e.g., 192.168.1.100:18789)
  ↓
Zaap generates Ed25519 keypair → stores in Keychain
  ↓
Zaap connects WS → sends node.pair.request
  { nodeId: sha256(publicKey), displayName: "Zaap (iPhone)",
    platform: "iOS", caps: ["voice", "camera"] }
  ↓
Gateway creates pending request → notifies operator
  ↓
User approves in OpenClaw dashboard / CLI
  ↓
Zaap receives token → stores in Keychain
  ↓
Connection established, voice tab unlocked
```

**Discovery:** Use Bonjour/mDNS — the gateway already advertises `_openclaw._tcp`. Zaap can auto-discover local gateways instead of manual IP entry.

## Sub-Beads (Implementation Plan)

| ID | Title | Dependencies | Estimate |
|----|-------|-------------|----------|
| z75-a | `NodePairingManager` — keypair generation, Keychain storage, pairing WS flow | — | 1 day |
| z75-b | `GatewayConnection` — WS client, connect handshake, message routing, reconnect | z75-a | 2 days |
| z75-c | `VoiceEngine` — SFSpeechRecognizer continuous mode, VAD silence detection | — | 1 day |
| z75-d | `ResponseSpeaker` — AVSpeechSynthesizer with streaming token buffering | — | 0.5 day |
| z75-e | `VoiceChatView` — UI with states (idle/listening/processing/speaking) | z75-b, z75-c, z75-d | 1 day |
| z75-f | Integration — wire voice engine → gateway → speaker, handle interrupts | z75-e | 1 day |
| z75-g | Bonjour discovery — auto-find gateway on local network | — | 0.5 day |

**Total estimate:** ~7 days

## Audio Session Configuration

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
try session.setActive(true)
```

- Must handle `AVAudioSession.interruptionNotification` (pause on phone call, resume after)
- When TTS is speaking and user starts talking → interrupt TTS, switch to recognition
- Use `.duckOthers` if background music is playing

## Reconnection Strategy

- On disconnect: exponential backoff (1s, 2s, 4s, 8s, max 30s)
- On app foreground: immediate reconnect attempt
- On network change (NWPathMonitor): reconnect when path becomes satisfied
- Store last-known gateway URL + token in Keychain for seamless reconnect

## Security

- Node token stored in iOS Keychain (not UserDefaults)
- Ed25519 keypair for device identity — private key never leaves device
- WS connection over local network (or Tailscale for remote)
- Gateway validates device signature on every connect
- Token rotation on re-pair

## Open Questions

1. **Background voice?** iOS kills audio sessions in background. Voice chat likely foreground-only. Could explore background audio modes for "walkie-talkie" UX but complex.
2. **Multiple sessions?** Should Zaap always use a fixed session key like `zaap-voice`, or let user pick? Fixed key is simpler; the gateway manages session state.
3. **Response streaming format?** Need to verify exact `chat.event` payload structure that `sendToSession` pushes to subscribed nodes. May need to handle partial markdown, code blocks, etc. gracefully in TTS.
