# Sandbox Agent iOS

Native iPhone **CallKit** client for Sandbox Agent — call an AI like a phone call.

## Features

- 📞 **Native iOS call UI** via CallKit
- 🎤 **Real-time voice** (speech → AI → spoken response)
- 🔒 **Sandbox security** — AI only operates in `C:\Users\mantou\sandbox`
- 🤖 **AI failover chain**: DeepSeek-V4-Flash → kat-coder-pro-v2.5 → Qwen3.6-27B
- 🧠 **VN persona** with 4 modes: Engineer / Designer / Strategist / Butler

## Architecture

```
iPhone (CallKit)  ⇄  WebSocket  ⇄  Windows Server (Sandbox)
   mic → ASR → LLM → TTS → speaker
```

## Setup

### 1. Backend (Windows)

Download `SandboxAgentServer.exe` from the latest Actions run → run on your PC.

Service runs at: `ws://0.0.0.0:8765/ws/agent`

### 2. iOS App

1. Install via **sideloadly** + Apple ID (free)
2. Open App → Settings → enter `ws://<your-pc-ip>:8765/ws/agent`
3. Tap **Call** → speak → AI responds

## Build (GitHub Actions)

Free cloud macOS builds via `.github/workflows/build.yml`. Triggers on push.

Artifacts: `SandboxAgent-IPA` (download, sideload with sideloadly).

## Requirements

- iOS 15.0+
- iPhone (real device required for CallKit)
- Windows PC running SandboxAgentServer.exe
- Same Wi-Fi network
