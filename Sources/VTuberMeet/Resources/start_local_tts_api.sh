#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${LOCAL_TTS_CONFIG_FILE:-$HOME/Library/Application Support/local.vtubermeet.app/local_tts.env}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

RUNTIME_ROOT="${LOCAL_TTS_RUNTIME_ROOT:-}"
ACOUSTIC_MODEL="${LOCAL_TTS_ACOUSTIC_MODEL:-}"
TEXT_MODEL="${LOCAL_TTS_TEXT_MODEL:-}"
REFERENCE_AUDIO="${LOCAL_TTS_REFERENCE_AUDIO:-}"
REFERENCE_TEXT="${LOCAL_TTS_REFERENCE_TEXT:-}"
REFERENCE_LANGUAGE="${LOCAL_TTS_REFERENCE_LANGUAGE:-ko}"
PORT="${PORT:-9888}"
HOST="${HOST:-127.0.0.1}"
DEVICE="${DEVICE:-cpu}"
MEDIA_TYPE="${MEDIA_TYPE:-wav}"
CONDA_ENV="${CONDA_ENV:-LocalTTS}"
CONDA_BIN="${CONDA_BIN:-}"

case "$HOST" in
  127.0.0.1|localhost|::1) ;;
  *)
    echo "Refusing to bind local TTS API to non-loopback host: $HOST" >&2
    exit 2
    ;;
esac

case "$DEVICE" in
  cpu|mps|cuda) ;;
  *)
    echo "Unsupported DEVICE '$DEVICE'. Use cpu, mps, or cuda." >&2
    exit 2
    ;;
esac

case "$MEDIA_TYPE" in
  wav|mp3) ;;
  *)
    echo "Unsupported MEDIA_TYPE '$MEDIA_TYPE'. Use wav or mp3." >&2
    exit 2
    ;;
esac

missing=0
for required_var in RUNTIME_ROOT ACOUSTIC_MODEL TEXT_MODEL REFERENCE_AUDIO REFERENCE_TEXT; do
  if [[ -z "${!required_var}" ]]; then
    echo "Missing $required_var. Set it in $CONFIG_FILE or export it before launch." >&2
    missing=1
  fi
done

for required_path in "$RUNTIME_ROOT/api.py" "$ACOUSTIC_MODEL" "$TEXT_MODEL" "$REFERENCE_AUDIO"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Missing local TTS file: $required_path" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

if [[ -z "$CONDA_BIN" ]]; then
  for candidate in \
    "$(command -v conda 2>/dev/null || true)" \
    "/opt/homebrew/Caskroom/miniconda/base/bin/conda" \
    "/opt/homebrew/bin/conda" \
    "/usr/local/bin/conda" \
    "$HOME/miniconda3/bin/conda" \
    "$HOME/anaconda3/bin/conda"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      CONDA_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "$CONDA_BIN" || ! -x "$CONDA_BIN" ]]; then
  echo "Could not find conda. Set CONDA_BIN to the conda executable path." >&2
  exit 1
fi

cd "$RUNTIME_ROOT"

"$CONDA_BIN" run --no-capture-output -n "$CONDA_ENV" python api.py \
  -s "$ACOUSTIC_MODEL" \
  -g "$TEXT_MODEL" \
  -dr "$REFERENCE_AUDIO" \
  -dt "$REFERENCE_TEXT" \
  -dl "$REFERENCE_LANGUAGE" \
  -d "$DEVICE" \
  -a "$HOST" \
  -p "$PORT" \
  -fp \
  -mt "$MEDIA_TYPE" &

CHILD_PID="$!"

cleanup() {
  if kill -0 "$CHILD_PID" 2>/dev/null; then
    pkill -TERM -P "$CHILD_PID" 2>/dev/null || true
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" 2>/dev/null || true
  fi
}

trap cleanup TERM INT EXIT
wait "$CHILD_PID"
