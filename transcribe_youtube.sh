#!/usr/bin/env bash
set -euo pipefail
set -o noglob  # avoid zsh-style glob expansion in URLs and paths

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <youtube-url>  |  echo <url> | $0 -" >&2
  echo "Tip for zsh: quote the URL or prefix the command with 'noglob'." >&2
  exit 1
fi

if [[ "$1" == "-" ]]; then
  read -r url
else
  url="$1"
fi
# Remove accidental backslash escapes (common when manually escaping ? and = in zsh)
url="${url//\\/}"

for dep in yt-dlp codex pbcopy python3; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Missing dependency: $dep" >&2
    exit 1
  fi
done

# Reusable whisper venv to keep runs self-contained and fast
venv_dir="${XDG_CACHE_HOME:-$HOME/.cache}/yt-transcriber-whisper-env"
python3 -m venv "$venv_dir" >/dev/null 2>&1 || true
if [[ ! -x "$venv_dir/bin/python" ]]; then
  echo "Failed to create python venv at $venv_dir" >&2
  exit 1
fi
if [[ ! -f "$venv_dir/whisper_installed.ok" ]]; then
  echo "Preparing whisper environment (one-time, downloads whisper model on first run)..."
  "$venv_dir/bin/python" -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
  "$venv_dir/bin/python" -m pip install --quiet openai-whisper >/dev/null
  touch "$venv_dir/whisper_installed.ok"
fi

# Prefetch the small model once to avoid slow downloads chosen by Codex
if [[ ! -f "$venv_dir/whisper_base_downloaded.ok" ]]; then
  echo "Fetching Whisper base model (one-time)..."
  "$venv_dir/bin/python" - <<'PY'
import whisper
whisper.load_model("base")
PY
  touch "$venv_dir/whisper_base_downloaded.ok"
fi

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

echo "Downloading audio with yt-dlp..."
yt-dlp \
  -q --no-warnings \
  -f 'bestaudio/best' \
  -x --audio-format mp3 \
  -o "$tmpdir/%(title)s.%(ext)s" \
  "$url" >/dev/null 2>&1

mp3="$(find "$tmpdir" -maxdepth 1 -type f -name '*.mp3' -print -quit)"
if [[ -z "${mp3:-}" ]]; then
  echo "No MP3 was created; check the URL and yt-dlp output." >&2
  exit 1
fi

echo "Transcribing via codex exec..."
transcript_file="$tmpdir/transcript.txt"
codex_log="$tmpdir/codex.log"

set +e
codex exec \
  --model gpt-5.1-codex-mini \
  -c model_reasoning_effort=low \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  --output-last-message "$transcript_file" \
  "Transcribe the audio file at: $mp3

- Language: English
- Use the existing Python venv at: $venv_dir
- Use whisper model='base' only (the model file is pre-downloaded). Do NOT download medium/large.
- If whisper is missing, install it inside that venv only (do NOT use global pip).
- Tooling allowed: run shell commands or Python if helpful (e.g., whisper or ffmpeg).
- Prefer a single Python command to print the transcript; avoid long planning.
- Output only the final transcript text with no extra commentary." \
  >"$codex_log" 2>&1
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "codex exec failed (exit $status). Log follows:" >&2
  cat "$codex_log" >&2
  exit $status
fi

transcript="$(cat "$transcript_file")"

printf "%s\n" "$transcript"
printf "%s" "$transcript" | pbcopy
echo "Transcript copied to clipboard."
