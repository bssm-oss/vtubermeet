# Manual QA Checklist

Run from the repository root:

```bash
swift run VTuberMeetCoreChecks
swift build
swift run VTuberMeet
```

For Local TTS checks, start the private local TTS API first:

```bash
PORT=9888 DEVICE=cpu Sources/VTuberMeet/Resources/start_local_tts_api.sh
```

## Happy Path
- [ ] App launches as a native macOS AppKit window.
- [ ] A cute official Live2D model appears by default (`Hiyori Momose`), not the old generated vector avatar.
- [ ] The character preset dropdown switches between Hiyori, Haru, Mao, Rice, Natori, and Ren.
- [ ] Send a Korean message such as `안녕, 오늘 뭐 할까?`.
- [ ] User message appears in the chat list.
- [ ] Assistant response appears in the chat list.
- [ ] If the Local TTS API is running, assistant response audio plays through the app backend proxy.
- [ ] `curl -X POST http://127.0.0.1:9890/api/tts -H 'Content-Type: application/json' -d '{"text":"안녕, 오늘 기분 좋아"}' --output local-tts.wav` writes a non-empty WAV file while the app is running.
- [ ] Repeating the same request writes a non-empty WAV file and uses the app cache instead of regenerating upstream audio.
- [ ] With the local upstream stopped, launching the app shows a TTS starting/checking state and `TTS 시작/재연결` can start the loopback upstream.
- [ ] Chat input sends with `Enter`; `Shift+Enter` inserts a newline.
- [ ] Optional MP3 mode is only used after a separate `MEDIA_TYPE=mp3` upstream/app generation test passes.
- [ ] If the Local TTS API is not running, the app shows a clear Local TTS error and chat still works.
- [ ] The selected model changes mood or idle motion after assistant responses.
- [ ] Avatar mood changes for cheerful or curious messages.
- [ ] Toggle `항상 위` and confirm the window remains above another app.
- [ ] Toggle `컴패니언 모드` and confirm the UI switches to avatar-focused companion mode.

## Bad Input
- [ ] Submit an empty or whitespace-only message.
- [ ] The app shows `메시지를 입력해 주세요.` and does not send a chat response.

## Visual/Responsive
- [ ] Resize the window and confirm the AppKit layout remains usable.
- [ ] Keyboard focus is visible on the text view, submit button, and toggles.
