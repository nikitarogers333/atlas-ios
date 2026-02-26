# Atlas Glasses — iOS App

iOS companion app for [Atlas](https://nikitarogers.up.railway.app) with push-to-talk voice input and Meta Wearables integration.

## Architecture

```
iPhone App
  ├── Atlas tab     → WKWebView loading Atlas dashboard
  └── Talk tab      → Push-to-talk mic → on-device transcription
                         ↓
                    POST /events (audio_transcription)
                         ↓
                   senses relay (Railway)
                         ↓
                      Atlas Brain
```

## Features

- **Atlas Dashboard** — Full Atlas UI in a native WebView wrapper
- **Push-to-Talk** — Hold button, speak, auto-transcribes on-device using Apple Speech framework, sends to Atlas via senses relay
- **Senses Relay Client** — SSE connection to cloud relay for real-time bidirectional communication
- **Meta MWDAT Ready** — Info.plist pre-configured with Meta Wearables Device Access Toolkit credentials for Phase B (glasses input)

## Setup

1. Open `AtlasGlasses.xcodeproj` in Xcode 15+
2. Set your Apple Development Team in Signing & Capabilities
3. Build and run on a physical iPhone (mic requires real device)

## Senses Relay

The app connects to `https://senses.up.railway.app`:
- `GET /phone/events` — SSE stream to receive commands from Atlas
- `POST /phone/respond` — Send hardware results back
- `POST /events` — Push audio transcriptions for Atlas to pick up

## Meta Wearables (Phase B)

The Meta MWDAT configuration is already in `Info.plist`:
- **App ID:** `25489663204046627`
- **Client Token:** Pre-configured

Once Meta approves Device Access Toolkit preview access, swap the phone mic input for glasses audio streams using the Meta Wearables SDK.

## Requirements

- iOS 17.0+
- Xcode 15.4+
- Physical iPhone (for microphone)
