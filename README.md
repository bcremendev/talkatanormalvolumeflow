# talkatanormalvolumeflow

A free, open, 100%-on-device [Wispr Flow](https://wisprflow.ai) alternative for macOS.
Hold a key, talk at a normal volume, release: clean text lands wherever your cursor is.

**[⬇ Download the latest release](https://github.com/bcremendev/talkatanormalvolumeflow/releases/latest)** · Apple Silicon, macOS 14+ · see [COWORKERS.md](COWORKERS.md) for the 2-minute setup.

- **Speech to text**: [whisper.cpp](https://github.com/ggml-org/whisper.cpp) with Metal acceleration. ~0.5 s for a 10-second sentence on an M-series Mac.
- **Cleanup**: instant built-in filler removal, smart capitalization, voice commands ("new line", "new paragraph", "scratch that"), custom vocabulary / replacements that also bias recognition.
- **Optional AI polish**: bundled [Ollama](https://ollama.com) runs a small local model (default `qwen2.5:3b`) to fix grammar and apply spoken self-corrections. Fully optional; the app works without it. Uses an existing system Ollama if one is running.
- **Menu-bar app**: hold-to-talk or toggle, any shortcut (Fn/🌐, Right ⌥, Right ⌘, or a recorded combo), floating waveform indicator, Esc to cancel, local history, launch at login.
- **Private**: no network calls except downloading models. No accounts, no telemetry.

Requirements: Apple Silicon, macOS 14+.

## Build

```bash
./scripts/build.sh
```

That downloads the prebuilt whisper.cpp xcframework and Ollama into `vendor/`, compiles with SwiftPM, assembles `dist/talkatanormalvolumeflow.app`, signs with your Developer ID (falls back to ad-hoc), and produces a `.zip` and `.dmg` in `dist/`.

### Notarize (so coworkers get no Gatekeeper warnings)

One-time setup with an [app-specific password](https://appleid.apple.com):

```bash
xcrun notarytool store-credentials tanvf --apple-id you@example.com --team-id YOURTEAMID --password xxxx-xxxx-xxxx-xxxx
```

Then:

```bash
NOTARY_PROFILE=tanvf ./scripts/build.sh
```

Options: `SKIP_OLLAMA=1` (smaller app, no bundled AI polish), `VERSION=1.2.0`, `BUNDLE_ID=com.yourco.tanvf`, `SIGN_IDENTITY="Developer ID Application: ..."`.

### Develop

```bash
swift build && .build/debug/talkatanormalvolumeflow
```

Running outside a bundle works for development but Accessibility permission is tied to the binary and resets each build. Test the engine without a mic:

```bash
.build/debug/talkatanormalvolumeflow --transcribe some.wav [--model small.en] [--raw]
```

## Layout

| Path | What |
|---|---|
| `Sources/App/DictationController.swift` | State machine: hotkey → record → transcribe → clean → polish → insert |
| `Sources/App/HotkeyManager.swift` | CGEvent tap for global shortcuts (lone modifiers or combos) |
| `Sources/App/AudioRecorder.swift` | AVAudioEngine → 16 kHz mono float |
| `Sources/App/WhisperEngine.swift` | whisper.cpp wrapper |
| `Sources/App/TextCleaner.swift` | Rule-based cleanup |
| `Sources/App/OllamaManager.swift` | Starts bundled Ollama, pulls models, cleanup prompt |
| `Sources/App/TextInserter.swift` | Paste (clipboard restore) or synthesized typing |
| `Sources/App/*View.swift` | SwiftUI settings, onboarding, overlay |
| `scripts/build.sh` | Bundle, sign, notarize, package |

Data lives in `~/Library/Application Support/talkatanormalvolumeflow/` (models, Ollama models, history).

## Licenses

whisper.cpp and Ollama are MIT licensed; their notices ship inside the app bundle. Whisper models are MIT (OpenAI). Ollama models carry their own licenses (Qwen: Apache 2.0; Gemma: Gemma Terms; Llama: Llama Community License).
