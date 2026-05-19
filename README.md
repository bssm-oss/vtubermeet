# VTuberMeet

Native macOS VTuber companion prototype built with Swift Package Manager and AppKit.

## What It Does
- Launches as a local AppKit macOS app.
- Shows the lightweight runtime-ready Live2D dataset synced from `AIvtuber`: `Hiyori Momose`, `Haru`, `Mao Niziiro`, `Rice Glassfield`, `Natori`, and `Ren`.
- Character preset dropdown switches between all six bundled models.
- Accepts typed chat.
- Connects to a local Ollama Gemma model for chat responses, preferring `gemma4:e4b` when installed and falling back to verified `gemma3:4b`.
- Plays assistant responses through a local-only TTS backend proxy.
- Provides idle motion, expression states, always-on-top, and companion overlay mode.

## Commands
```bash
swift run VTuberMeetCoreChecks
swift build
swift run VTuberMeet
```

## Local LLM
The app talks to Ollama at `http://127.0.0.1:11434` and selects the first available Gemma-family model from this order: `gemma4:e4b`, `gemma4:latest`, `gemma4:e2b`, `gemma3:4b`, `gemma3`, `gemma3n`, `gemma2`, then `gemma`.

```bash
ollama pull gemma4:e4b
ollama pull gemma3:4b
ollama serve
```

## Local TTS

VTuberMeet starts a local-only backend endpoint at `http://127.0.0.1:9890/api/tts` and calls a private local TTS runtime from inside the app. Keep the upstream TTS process bound to loopback only.

The app checks the upstream TTS server on launch and tries to start it locally if it is not already running. You can also start the bundled helper manually when you want to watch its terminal output:

```bash
PORT=9888 DEVICE=cpu Sources/VTuberMeet/Resources/start_local_tts_api.sh
```

The helper wrapper lives at `Sources/VTuberMeet/Resources/start_local_tts_api.sh`. `DEVICE` defaults to `cpu`; set `DEVICE=mps` or `DEVICE=cuda` only if the private runtime supports it. `MEDIA_TYPE` defaults to the verified `wav` path. `mp3` is configuration-supported, but verify it locally before relying on it. GUI-launched apps may not inherit your shell `PATH`, so the wrapper searches common conda locations and also accepts `CONDA_BIN=/path/to/conda`.

Private voice assets and model files are intentionally not committed. Put local paths in:

```bash
~/Library/Application Support/local.vtubermeet.app/local_tts.env
```

Required private config keys:

```bash
LOCAL_TTS_RUNTIME_ROOT="/path/to/local/runtime"
LOCAL_TTS_ACOUSTIC_MODEL="/path/to/acoustic-model"
LOCAL_TTS_TEXT_MODEL="/path/to/text-model"
LOCAL_TTS_REFERENCE_AUDIO="/path/to/reference.wav"
LOCAL_TTS_REFERENCE_TEXT="reference sentence"
LOCAL_TTS_REFERENCE_LANGUAGE=ko
CONDA_ENV=LocalTTS
```

Optional private persona override:

```bash
~/Library/Application Support/local.vtubermeet.app/private_system_prompt.txt
```

Configuration:

```bash
# Upstream local TTS API. Must stay local-only.
export LOCAL_TTS_API_URL="http://127.0.0.1:9888/"

# Optional generated audio cache directory.
export LOCAL_TTS_OUTPUT_DIR="$HOME/Library/Application Support/local.vtubermeet.app/outputs/tts_generated"

# Optional output format. Use verified wav by default; set mp3 only after verifying upstream with MEDIA_TYPE=mp3.
export LOCAL_TTS_AUDIO_FORMAT=wav

# Optional app backend proxy port.
export LOCAL_TTS_BACKEND_PORT=9890
```

The app endpoint accepts:

```bash
curl -X POST http://127.0.0.1:9890/api/tts \
  -H 'Content-Type: application/json' \
  -d '{"text":"안녕, 오늘 기분 좋아"}' \
  --output local-tts.wav
```

Protection built into the app backend:
- binds only to `127.0.0.1`
- accepts only local `LOCAL_TTS_API_URL` values (`127.0.0.1`, `localhost`, or `::1`)
- rejects empty text and text longer than 300 characters
- rate-limits uncached TTS generations
- caches repeated text in memory and on disk so identical text is not regenerated every time
- stores generated audio under `outputs/tts_generated` by default (`LOCAL_TTS_OUTPUT_DIR` can override this)
- checks and starts the local upstream from inside the app when possible
- returns a clear `503` JSON error when the Local TTS server is not running

UI recovery controls:
- `TTS 시작/재연결` checks the local upstream and starts it on loopback when it is down.
- Chat input sends with `Enter`; use `Shift+Enter` for a newline.

## Bundled Live2D Presets

| Preset | Style | Source |
|--------|-------|--------|
| Hiyori Momose | Bright anime-style (default) | Live2D Cubism Web Samples |
| Haru | Polished anime-girl | Live2D Cubism Web Samples |
| Mao Niziiro | Standard anime model | Live2D Cubism Web Samples |
| Rice Glassfield | Fantasy side-facing | Live2D Cubism Web Samples |
| Natori | Butler/neutral VTuber style | Live2D Cubism Web Samples |
| Ren | Boyish/cute VTuber style | Live2D Cubism Web Samples |

## Asset Licensing
The bundled presets come from the official Live2D Cubism Web Samples / Live2D Original Characters. They are bundled under Live2D's Free Material License and sample model terms. See each `Sources/VTuberMeet/Resources/Avatars/<Name>/license.md` file.

Attribution required by Live2D:

> This content uses sample data owned and copyrighted by Live2D Inc. The sample data are utilized in accordance with terms and conditions set by Live2D Inc. This content itself is created at the author's sole discretion.

## Dataset Notes

`AIvtuber` also contains `Generichan` CC0 source assets, but they are not copied into the app bundle because they are not runtime-ready `.model3.json` Live2D assets and add about 79 MB of editor/source files. This keeps VTuberMeet lightweight while preserving all runtime-ready models.

## Verification Notes

Local verification for the Local TTS integration:
- `swift build` passed.
- `swift run VTuberMeetCoreChecks` passed.
- Started local upstream with `PORT=9888 DEVICE=cpu Sources/VTuberMeet/Resources/start_local_tts_api.sh` and confirmed direct WAV output from `POST http://127.0.0.1:9888/`.
- Called `POST http://127.0.0.1:9890/api/tts` while VTuberMeet was running and confirmed non-empty WAV output.
- Validated both WAV files with `afinfo` and briefly played both with `afplay`.
- Repeated identical text and confirmed the app backend served it from cache without another upstream generation.
- Confirmed generated WAV files are stored in the configured `LOCAL_TTS_OUTPUT_DIR` cache.
- Empty text returns a JSON validation error and upstream-down requests return a clear `503` JSON error.
- Optional MP3 mode is configuration-supported but should be runtime-tested separately with `MEDIA_TYPE=mp3` before use.

## API Keys
No cloud API keys are required. Keep local Ollama state, private prompts, voice references, and model files outside the repository.
