# VTuberMeet

> 개인용 VTuber Companion 앱 — 로컬 LLM과 유니 ASMR TTS로 대화하는 macOS 네이티브 앱

[English README](README.md)

## 소개

VTuberMeet은 macOS에서 실행되는 개인용 VTuber 컴패니언 앱입니다. 로컬 LLM(Ollama Gemma)과 유니 ASMR TTS를 연동해서 채팅하고, Live2D 캐릭터가 반응하며 대화를 이어갑니다.

### 주요 기능

- **Live2D 캐릭터** — Hiyori, Haru, Mao, Rice, Wanko 등 공식 샘플 모델 탑재
- **카톡 스타일 채팅** — 말풍선, 타임스탬프, 시간 구분선
- **버튜버 오버레이** — 최근 메시지가 버튜버 아래에 자막처럼 표시되고 5초 후 페이드아웃
- **로컬 LLM** — Ollama Gemma 계열 모델과 대화 (인터넷 연결 불필요)
- **유니 ASMR TTS** — Yuni ASMR 목소리로 응답을 음성으로 재생
- **컴패니언 모드** — 작은 창으로 항상 위에 띄워둘 수 있음
- **Enter 전송** — Shift+Enter로 줄바꿈

## 설치 및 실행

### 요구사항

- macOS 13+ (Ventura 이상)
- Xcode 15+ 또는 Swift 5.9+
- Ollama (로컬 LLM용)
- Conda (유니 ASMR TTS용, 선택사항)

### 빌드

```bash
swift build
swift run VTuberMeetCoreChecks
swift run VTuberMeet
```

또는 release 빌드:

```bash
swift build -c release
```

### 앱으로 설치

```bash
cp .build/release/VTuberMeet /Applications/VTuberMeet.app/Contents/MacOS/VTuberMeet
cp -R Sources/VTuberMeet/Resources/. /Applications/VTuberMeet.app/Contents/Resources/
codesign --force --deep --sign - /Applications/VTuberMeet.app
open /Applications/VTuberMeet.app
```

## 로컬 LLM 설정 (Ollama)

### 1. Ollama 설치

```bash
brew install ollama
ollama serve
```

### 2. Gemma 모델 다운로드

```bash
ollama pull gemma4:e4b
ollama pull gemma3:4b
```

VTuberMeet은 다음 순서로 모델을 자동 선택합니다:
`gemma4:e4b` → `gemma4:latest` → `gemma3:4b` → `gemma3` → `gemma2` → `gemma`

### 3. 상태 확인

앱 실행 후 우측 설정 패널의 **서비스 상태**에서 "대화 준비됨"이 뜨면 정상입니다.

## 유니 ASMR TTS 설정

### 자동 시작 (권장)

VTuberMeet은 실행 시 자동으로 TTS 서버 상태를 확인하고, 꺼져 있으면 로컬(127.0.0.1)에서 자동으로 시작합니다.

### 수동 시작

터미널에서 직접 시작하려면:

```bash
cd "~/Desktop/유니 목소리"
PORT=9888 DEVICE=cpu ./outputs/asmr_voice_only/deploy/start_yuni_asmr_tts_api.sh
```

### 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `YUNI_TTS_API_URL` | `http://127.0.0.1:9888/` | TTS API 주소 |
| `YUNI_TTS_BACKEND_PORT` | `9890` | 앱 낭부 프록시 포트 |
| `YUNI_TTS_OUTPUT_DIR` | `~/Library/Application Support/local.vtubermeet.app/outputs/tts_generated` | 생성 음성 저장 경로 |
| `YUNI_TTS_AUDIO_FORMAT` | `wav` | 출력 포맷 (wav/mp3) |
| `YUNI_ASMR_ROOT` | 프로젝트 내 `LocalVoiceAssets/YuniASMR` | 음성셋 경로 |
| `GPT_SOVITS_ROOT` | — | GPT-SoVITS 설치 경로 |
| `DEVICE` | `cpu` | 실행 장치 (cpu/mps/cuda) |
| `CONDA_BIN` | 자동 탐색 | conda 실행 파일 경로 |

### 상태 확인

```bash
curl http://127.0.0.1:9890/health
# {"ok":true}

curl -X POST http://127.0.0.1:9890/api/tts \
  -H 'Content-Type: application/json' \
  -d '{"text":"안녕하세요"}' \
  --output yuni.wav
```

## 캐릭터 프리셋

| 프리셋 | 스타일 | 출처 |
|--------|--------|------|
| Hiyori Momose | 밝은 애니메이션 스타일 | Live2D Cubism Web Samples |
| Haru | 세련된 애니메이션 걸 | Live2D Cubism Web Samples |
| Mao Niziiro | 표준 애니메이션 모델 | Live2D Cubism Web Samples |
| Rice Glassfield | 판타지 측면 캐릭터 | Live2D Cubism Web Samples |
| Wanko | 귀여운 VTuber 스타일 | Live2D Cubism Web Samples |

> 더 많은 여성 캐릭터를 추가하려면 [Live2D Sample Data](https://www.live2d.com/en/learn/sample/)에서 다운로드 후 `Sources/VTuberMeet/Resources/Avatars/`에 넣고 `manifest.json`에 등록하세요.

## UI 사용법

- **Enter** — 메시지 전송
- **Shift + Enter** — 줄바꿈
- **TTS 시작/재연결** — TTS 서버 수동 확인/시작
- **항상 위** — 창을 항상 최상위에 표시
- **컴패니언 모드** — 작은 창으로 전환

## 문제 해결

### "대화 설정 필요"가 뜨는 경우

Ollama가 실행 중인지 확인하세요:

```bash
ollama list
ollama serve
```

### "유니 ASMR TTS 서버가 꺼져 있습니다"가 뜨는 경우

1. **TTS 시작/재연결** 버튼을 클릭하세요 (자동 시작 시도)
2. 터미널에서 수동으로 TTS를 시작하세요
3. Conda PATH 문제인 경우 `CONDA_BIN` 환경변수를 설정하세요

### Gemma4에서 빈 응답이 오는 경우

Gemma4는 thinking 모드로 인해 토큰을 많이 소모합니다. VTuberMeet은 `/api/chat` 엔드포인트와 512 토큰 제한을 사용하여 이 문제를 해결합니다. 최신 버전으로 업데이트하세요.

## 라이선스

- **Live2D 샘플 모델**: [Live2D Free Material License](https://www.live2d.com/eula/live2d-free-material-license-agreement_en.html)
- **유니 ASMR TTS**: 본인 목소리용 (외부 공개 금지)
- **코드**: 프로젝트 라이선스 참조

> 본 프로젝트는 Stellive의 공식 허가를 받은 개인 비공개 팬 프로젝트입니다.

## 기여

버그 리포트나 기능 제안은 GitHub Issues를 통해 해주세요.

## 감사의 말

- [Live2D Cubism](https://www.live2d.com/) — Live2D 모델 및 SDK
- [Ollama](https://ollama.com/) — 로컬 LLM 실행 환경
- [GPT-SoVITS](https://github.com/RVC-Boss/GPT-SoVITS) — TTS 엔진
- [Stellive](https://stellive.me/) — 유니 ASMR 음성셋
