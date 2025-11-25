#!/usr/bin/env bash
set -euo pipefail
set -o noglob  # avoid zsh-style glob expansion in URLs and paths

progress_bar_width=32
progress_stage_label=""
progress_stage_percent=0
progress_stage_active=false
progress_line_on_newline=true
progress_spinner_frames='|/-\\'
progress_spinner_index=0
progress_spinner_char=""
progress_spinner_visible=false

progress_stage_start_ms=0
progress_last_update_ms=0
progress_stage_fake_duration_ms=0
progress_next_fake_duration_ms=0
progress_stage_fake_slack_percent=0
progress_next_fake_slack_percent=0

telemetry_time_source=""
telemetry_current_name=""
telemetry_current_start_ms=0
telemetry_stage_names=()
telemetry_stage_durations=()

progress_render() {
  local filled=$(( progress_stage_percent * progress_bar_width / 100 ))
  local empty=$(( progress_bar_width - filled ))
  local bar=""
  local pad=""
  if (( filled > 0 )); then
    printf -v bar '%*s' "$filled" ''
    bar=${bar// /#}
  fi
  if (( empty > 0 )); then
    printf -v pad '%*s' "$empty" ''
    pad=${pad// /-}
  fi
  local tail=""
  if [[ "$progress_spinner_visible" == true ]]; then
    tail=" $progress_spinner_char"
  fi
  printf '\r%-18s [%s%s] %3d%%%s' "$progress_stage_label" "$bar" "$pad" "$progress_stage_percent" "$tail" >&2
  progress_line_on_newline=false
}

progress_start() {
  progress_stage_label="$1"
  progress_stage_percent=0
  progress_stage_active=true
  progress_spinner_index=0
  progress_spinner_char=""
  progress_spinner_visible=false
  progress_stage_start_ms="$(now_ms)"
  progress_last_update_ms="$progress_stage_start_ms"
  progress_stage_fake_duration_ms="$progress_next_fake_duration_ms"
  progress_next_fake_duration_ms=0
  progress_stage_fake_slack_percent="$progress_next_fake_slack_percent"
  progress_next_fake_slack_percent=0
  progress_render
}

progress_update() {
  local new_value="$1"
  if [[ "$progress_stage_active" != true ]]; then
    return
  fi
  (( new_value < 0 )) && new_value=0
  (( new_value > 100 )) && new_value=100
  if (( new_value == progress_stage_percent )); then
    return
  fi
  progress_stage_percent=$new_value
  progress_spinner_visible=false
  if [[ "$progress_stage_active" == true ]]; then
    progress_last_update_ms="$(now_ms)"
  fi
  progress_render
}

progress_finish() {
  if [[ "$progress_stage_active" == true ]]; then
    progress_update 100
    printf '\n' >&2
    progress_line_on_newline=true
    progress_stage_active=false
  fi
}

progress_flush_line() {
  if [[ "$progress_stage_active" == true && "$progress_line_on_newline" == false ]]; then
    printf '\n' >&2
    progress_line_on_newline=true
  fi
}

progress_cleanup() {
  progress_flush_line
  progress_stage_active=false
  progress_spinner_visible=false
}

progress_spinner_tick() {
  local target="$1"
  if [[ "$progress_stage_active" != true ]]; then
    return
  fi
  if (( progress_stage_percent < target - 1 )); then
    if [[ "$progress_spinner_visible" == true ]]; then
      progress_spinner_visible=false
      progress_render
    fi
    return
  fi
  local frames_len=${#progress_spinner_frames}
  progress_spinner_visible=true
  progress_spinner_index=$(( (progress_spinner_index + 1) % frames_len ))
  progress_spinner_char=${progress_spinner_frames:progress_spinner_index:1}
  progress_render
}

progress_set_next_fake_duration_ms() {
  local value="${1:-0}"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    progress_next_fake_duration_ms="$value"
  else
    progress_next_fake_duration_ms=0
  fi
}

progress_set_next_fake_slack_percent() {
  local value="${1:-0}"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    progress_next_fake_slack_percent="$value"
  else
    progress_next_fake_slack_percent=0
  fi
}

detect_time_source() {
  if [[ -n "$telemetry_time_source" ]]; then
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    telemetry_time_source="python"
  elif command -v perl >/dev/null 2>&1; then
    telemetry_time_source="perl"
  else
    telemetry_time_source="date"
  fi
}

now_ms() {
  detect_time_source
  case "$telemetry_time_source" in
    python)
      python3 - <<'PY'
import time, sys
sys.stdout.write(str(int(time.time() * 1000)))
PY
      ;;
    perl)
      perl -MTime::HiRes=time -e 'printf("%.0f\n", time() * 1000)'
      ;;
    date)
      local seconds
      seconds=$(date +%s)
      printf '%d\n' "$(( seconds * 1000 ))"
      ;;
  esac
}

telemetry_begin_stage() {
  if [[ -n "$telemetry_current_name" ]]; then
    telemetry_end_stage
  fi
  telemetry_current_name="$1"
  telemetry_current_start_ms="$(now_ms)"
}

telemetry_end_stage() {
  if [[ -z "$telemetry_current_name" ]]; then
    return
  fi
  local end_ms
  end_ms="$(now_ms)"
  local duration=$(( end_ms - telemetry_current_start_ms ))
  telemetry_stage_names+=("$telemetry_current_name")
  telemetry_stage_durations+=("$duration")
  telemetry_current_name=""
  telemetry_current_start_ms=0
}

format_duration() {
  local ms="$1"
  local seconds=$(( ms / 1000 ))
  local remainder=$(( ms % 1000 ))
  printf '%d.%03ds' "$seconds" "$remainder"
}

print_telemetry_line() {
  telemetry_end_stage
  if (( ${#telemetry_stage_names[@]} == 0 )); then
    return
  fi
  local telemetry_line="Telemetry:"
  local idx=0
  local total=${#telemetry_stage_names[@]}
  while (( idx < total )); do
    local label="${telemetry_stage_names[$idx]}"
    local duration_ms="${telemetry_stage_durations[$idx]}"
    local formatted
    formatted="$(format_duration "$duration_ms")"
    if [[ "$telemetry_line" != "Telemetry:" ]]; then
      telemetry_line+=" |"
    fi
    telemetry_line+=" ${label}=${formatted}"
    ((idx++))
  done
  printf '%s\n' "$telemetry_line"
}

fake_progress_toward() {
  local target="$1"
  if [[ "$progress_stage_active" != true ]]; then
    return
  fi
  if (( target <= progress_stage_percent )); then
    return
  fi
  local cap=$(( target - 1 ))
  if (( cap <= progress_stage_percent )); then
    return
  fi
  if (( progress_stage_fake_duration_ms > 0 )); then
    local now_ms_value
    now_ms_value="$(now_ms)"
    local elapsed=$(( now_ms_value - progress_stage_start_ms ))
    (( elapsed < 0 )) && elapsed=0
    local slack=$progress_stage_fake_slack_percent
    if (( slack < 0 )); then
      slack=0
    fi
    if (( slack > cap )); then
      slack=$cap
    fi
    local core_cap=$(( cap - slack ))
    local allowed=0
    if (( core_cap > 0 )); then
      allowed=$(( core_cap * elapsed / progress_stage_fake_duration_ms ))
      if (( allowed > core_cap )); then
        allowed=$core_cap
      fi
    fi
    if (( slack > 0 && elapsed > progress_stage_fake_duration_ms )); then
      local extra_elapsed=$(( elapsed - progress_stage_fake_duration_ms ))
      local extra_unit=$(( progress_stage_fake_duration_ms / slack ))
      if (( extra_unit <= 0 )); then
        extra_unit=1
      fi
      local extra=$(( extra_elapsed / extra_unit ))
      if (( extra > slack )); then
        extra=$slack
      fi
      allowed=$(( allowed + extra ))
    fi
    if (( allowed > cap )); then
      allowed=$cap
    fi
    if (( allowed > progress_stage_percent )); then
      progress_update "$allowed"
    fi
    return
  fi
  local remaining=$(( cap - progress_stage_percent ))
  local step=1
  if (( remaining > 40 )); then
    step=$(( remaining / 6 ))
  elif (( remaining > 15 )); then
    step=3
  elif (( remaining > 7 )); then
    step=2
  fi
  local next=$(( progress_stage_percent + step ))
  if (( next > cap )); then
    next=$cap
  fi
  progress_update "$next"
}

pulse_progress_to() {
  local target="$1"
  local interval="${2:-0.08}"
  if (( target <= progress_stage_percent )); then
    progress_update "$target"
    return
  fi
  while (( progress_stage_percent < target )); do
    if (( progress_stage_percent >= target - 1 )); then
      break
    fi
    fake_progress_toward "$target"
    sleep "$interval"
  done
  progress_update "$target"
}

run_command_with_progress() {
  local target="$1" log_file="$2"; shift 2
  : >"$log_file"
  "$@" >"$log_file" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    fake_progress_toward "$target"
    progress_spinner_tick "$target"
    sleep 0.25
  done
  set +e
  wait "$pid"
  local status=$?
  set -e
  if (( status != 0 )); then
    progress_flush_line
    echo "Step '$progress_stage_label' failed (see $log_file)." >&2
    tail -n 50 "$log_file" >&2 || true
    exit "$status"
  fi
  progress_update "$target"
}

yt_dl_with_progress() {
  local log_file="$1"; shift
  : >"$log_file"
  set +e
  "$@" --newline 2>&1 | while IFS= read -r line; do
    printf '%s\n' "$line" >>"$log_file"
    if [[ "$line" =~ \[download\][[:space:]]+([0-9.]+)% ]]; then
      local pct=${BASH_REMATCH[1]%.*}
      if [[ -n "$pct" ]]; then
        progress_update "$pct"
      fi
    fi
  done
  local status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

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
url="${url//\\/}"

start_seconds=""
if [[ $url =~ [\?\&]t=([^&#]+) ]]; then
  tval="${BASH_REMATCH[1]}"
  if [[ $tval =~ ^([0-9]+)h([0-9]+)m([0-9]+)s?$ ]]; then
    start_seconds=$(( ${BASH_REMATCH[1]}*3600 + ${BASH_REMATCH[2]}*60 + ${BASH_REMATCH[3]} ))
  elif [[ $tval =~ ^([0-9]+)m([0-9]+)s?$ ]]; then
    start_seconds=$(( ${BASH_REMATCH[1]}*60 + ${BASH_REMATCH[2]} ))
  elif [[ $tval =~ ^([0-9]+)s?$ ]]; then
    start_seconds="${BASH_REMATCH[1]}"
  fi
fi

tmpdir="$(mktemp -d)"
cleanup() {
  progress_cleanup
  if [[ -z "${PRESERVE_TMPDIR:-}" ]]; then
    rm -rf "$tmpdir"
  else
    echo "PRESERVE_TMPDIR=1 set; leaving temp files at $tmpdir" >&2
  fi
}
trap cleanup EXIT

venv_dir="${XDG_CACHE_HOME:-$HOME/.cache}/yt-transcriber-whisper-env"
telemetry_begin_stage "Environment prep"
progress_start "Environment prep"
for dep in yt-dlp codex python3 ffmpeg pbcopy; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    progress_flush_line
    echo "Missing dependency: $dep" >&2
    exit 1
  fi
  sleep 0.02
  fake_progress_toward 8
done
pulse_progress_to 12

run_command_with_progress 35 "$tmpdir/venv.log" \
  bash -c 'python3 -m venv "$1" >/dev/null 2>&1 || true' _ "$venv_dir"
if [[ ! -x "$venv_dir/bin/python" ]]; then
  progress_flush_line
  echo "Failed to create python venv at $venv_dir" >&2
  exit 1
fi

if [[ ! -f "$venv_dir/whisper_installed.ok" ]]; then
  run_command_with_progress 55 "$tmpdir/pip-upgrade.log" \
    "$venv_dir/bin/python" -m pip install --quiet --upgrade pip
  run_command_with_progress 75 "$tmpdir/whisper-install.log" \
    "$venv_dir/bin/python" -m pip install --quiet openai-whisper
  touch "$venv_dir/whisper_installed.ok"
else
  pulse_progress_to 75
fi

if [[ ! -f "$venv_dir/whisper_base_downloaded.ok" ]]; then
  run_command_with_progress 100 "$tmpdir/whisper-model.log" \
    "$venv_dir/bin/python" - <<'PY'
import whisper
whisper.load_model("base")
PY
  touch "$venv_dir/whisper_base_downloaded.ok"
else
  pulse_progress_to 100
fi
progress_finish
telemetry_end_stage

yt_log="$tmpdir/yt-dlp.log"
telemetry_begin_stage "Download"
progress_start "Download"
attempt=1
max_attempts=2
while (( attempt <= max_attempts )); do
  if yt_dl_with_progress "$yt_log" yt-dlp \
    --no-warnings \
    --hls-prefer-native \
    -f 'bestaudio/best' \
    -x --audio-format mp3 \
    -o "$tmpdir/%(title)s.%(ext)s" \
    "$url"; then
    break
  fi
  if (( attempt == max_attempts )); then
    progress_flush_line
    echo "yt-dlp failed after $attempt attempt(s). See $yt_log" >&2
    exit 1
  fi
  progress_flush_line
  echo "yt-dlp failed (attempt $attempt). Retrying..." >&2
  ((attempt++))
  progress_start "Download"
done
progress_finish
telemetry_end_stage

mp3="$(find "$tmpdir" -maxdepth 1 -type f -name '*.mp3' -print -quit)"
if [[ -z "${mp3:-}" ]]; then
  progress_flush_line
  echo "No MP3 was created; check the URL and yt-dlp output." >&2
  exit 1
fi

if [[ -n "${start_seconds:-}" ]]; then
  trimmed_mp3="$tmpdir/trimmed.mp3"
  if ! ffmpeg -nostdin -loglevel error -y -ss "$start_seconds" -i "$mp3" -acodec copy "$trimmed_mp3"; then
    progress_flush_line
    echo "Failed to trim audio at t=$start_seconds seconds." >&2
    exit 1
  fi
  mp3="$trimmed_mp3"
fi

transcription_progress_fake_duration_ms=""
if [[ -n "${TRANSCRIPTION_PROGRESS_FAKE_DURATION_MS:-}" && "${TRANSCRIPTION_PROGRESS_FAKE_DURATION_MS}" =~ ^[0-9]+$ ]]; then
  transcription_progress_fake_duration_ms="${TRANSCRIPTION_PROGRESS_FAKE_DURATION_MS}"
fi

if [[ -z "$transcription_progress_fake_duration_ms" ]]; then
  if command -v ffprobe >/dev/null 2>&1; then
    audio_duration_seconds=""
    if duration_output=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$mp3" 2>/dev/null); then
      duration_output="${duration_output//$'\r'/}"
      duration_output="${duration_output%%$'\n'*}"
      if [[ "$duration_output" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        audio_duration_seconds="$duration_output"
      fi
    fi
    if [[ -n "$audio_duration_seconds" ]]; then
      transcription_progress_ms_per_audio_second="${TRANSCRIPTION_PROGRESS_MS_PER_AUDIO_SECOND:-80}"
      transcription_progress_min_fake_duration_ms="${TRANSCRIPTION_PROGRESS_MIN_FAKE_DURATION_MS:-20000}"
      transcription_progress_max_fake_duration_ms="${TRANSCRIPTION_PROGRESS_MAX_FAKE_DURATION_MS:-240000}"
      if [[ -n "$transcription_progress_ms_per_audio_second" ]]; then
        transcription_progress_fake_duration_ms="$({
          python3 - "$audio_duration_seconds" \
            "$transcription_progress_ms_per_audio_second" \
            "$transcription_progress_min_fake_duration_ms" \
            "$transcription_progress_max_fake_duration_ms" <<'PY'
import math, sys
try:
    duration = float(sys.argv[1])
    ms_per_sec = float(sys.argv[2])
    min_ms = int(float(sys.argv[3]))
    max_ms = int(float(sys.argv[4]))
except (ValueError, IndexError):
    sys.exit(1)
if ms_per_sec <= 0:
    sys.exit(1)
ms = int(duration * ms_per_sec)
if ms < min_ms:
    ms = min_ms
if ms > max_ms:
    ms = max_ms
print(ms)
PY
        })" || transcription_progress_fake_duration_ms=""
      fi
    fi
  fi
fi

if [[ -z "$transcription_progress_fake_duration_ms" ]]; then
  default_fake_duration="${TRANSCRIPTION_PROGRESS_DEFAULT_FAKE_DURATION_MS:-60000}"
  if [[ "$default_fake_duration" =~ ^[0-9]+$ ]]; then
    transcription_progress_fake_duration_ms="$default_fake_duration"
  else
    transcription_progress_fake_duration_ms=60000
  fi
fi

transcription_progress_fake_slack_percent="${TRANSCRIPTION_PROGRESS_FAKE_SLACK_PERCENT:-1}"
if [[ ! "$transcription_progress_fake_slack_percent" =~ ^[0-9]+$ ]]; then
  transcription_progress_fake_slack_percent=1
fi
if (( transcription_progress_fake_slack_percent > 99 )); then
  transcription_progress_fake_slack_percent=99
fi

transcript_file="$tmpdir/transcript.txt"
codex_log="$tmpdir/codex.log"
progress_set_next_fake_duration_ms "$transcription_progress_fake_duration_ms"
progress_set_next_fake_slack_percent "$transcription_progress_fake_slack_percent"
telemetry_begin_stage "Transcription"
progress_start "Transcription"
run_command_with_progress 100 "$codex_log" \
  env COD_MP3="$mp3" COD_TRANSCRIPT="$transcript_file" COD_VENV="$venv_dir" COD_LOG="$codex_log" \
  sh -c '
    codex exec \
      --model gpt-5.1-codex-mini \
      -c model_reasoning_effort=low \
      --dangerously-bypass-approvals-and-sandbox \
      --skip-git-repo-check \
      --output-last-message "$COD_TRANSCRIPT" \
      "Transcribe the audio file at: $COD_MP3

- Language: English
- Use the existing Python venv at: $COD_VENV
- Use whisper model='\''base'\'' only (the model file is pre-downloaded). Do NOT download medium/large.
- If whisper is missing, install it inside that venv only (do NOT use global pip).
- Tooling allowed: run shell commands or Python if helpful (e.g., whisper or ffmpeg).
- Prefer a single Python command to print the transcript; avoid long planning.
- Output only the final transcript text with no extra commentary." \
      >"$COD_LOG" 2>&1
  '
progress_finish
telemetry_end_stage

transcript="$(cat "$transcript_file")"
printf "%s\n" "$transcript"
printf "%s" "$transcript" | pbcopy
print_telemetry_line
