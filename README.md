# yt-cdx-transcriber

One-command YouTube audio transcriber that:
- Downloads audio with `yt-dlp`.
- Sends it to `codex exec` (GPT-5.1 Codex mini) to run Whisper in an isolated venv.
- Streams a progress bar with realistic pacing instead of stalling at 99%.
- Prints the English transcript, copies it to the macOS clipboard (`pbcopy`), and emits per-stage telemetry so you know where the time went.

## Requirements
- macOS (for `pbcopy`).
- `yt-dlp`
- `codex` CLI (logged in and allowed to use `--dangerously-bypass-approvals-and-sandbox`).
- `python3`
- `ffmpeg` (includes `ffprobe`, which the progress heuristics use when available).

## Install
```bash
chmod +x transcribe_youtube.sh
```

## Usage
Recommended (no escaping issues):
```bash
./transcribe_youtube.sh 'https://www.youtube.com/watch?v=oQmKB3AyaXw'
```

Piping works too:
```bash
echo https://www.youtube.com/watch?v=oQmKB3AyaXw | ./transcribe_youtube.sh -
```

zsh tip: if you do escape `?`/`=` (e.g., `\?`, `\=`) the script strips the backslashes automatically.

## What it does
1. Creates/uses a cached virtualenv at `~/.cache/yt-transcriber-whisper-env`.
2. Installs `openai-whisper` once and prefetches the `base` model to avoid large downloads.
3. Downloads bestaudio as MP3 via `yt-dlp`.
4. Calls `codex exec` with a small prompt that asks Codex to transcribe using the prepared venv.
5. Prints the transcript, copies it to the clipboard, and prints a telemetry line such as `Telemetry: Environment prep=4.556s | Download=19.234s | Transcription=77.687s`.

## Output example

```
In this video I'm going to talk a little bit about how I've set up this second brain personal knowledge management system... (rest of transcript omitted)

Telemetry: Environment prep=4.556s | Download=19.234s | Transcription=77.687s
```

The transcript is both shown in your terminal and copied to the clipboard, so you can paste it straight into your Zettelkasten or PKM tool.

## Progress + telemetry tweaks

The transcription stage estimates how long Whisper will run by measuring the MP3 duration (via `ffprobe`), then eases the progress bar from 0–99% during that window and uses the final 1% for slack. Tune the heuristics with environment variables:

- `TRANSCRIPTION_PROGRESS_FAKE_DURATION_MS`: hard-code a fake duration (set to `0` to disable pacing and fall back to the legacy instant progress).
- `TRANSCRIPTION_PROGRESS_MS_PER_AUDIO_SECOND`: multiplier turning audio seconds into fake milliseconds (`80` default).
- `TRANSCRIPTION_PROGRESS_MIN_FAKE_DURATION_MS` / `TRANSCRIPTION_PROGRESS_MAX_FAKE_DURATION_MS`: safety rails for very short/long clips.
- `TRANSCRIPTION_PROGRESS_FAKE_SLACK_PERCENT`: percent of the bar reserved for work beyond the estimate (`1` default).
- `TRANSCRIPTION_PROGRESS_DEFAULT_FAKE_DURATION_MS`: fallback when no duration is available (`60000` default).

## Notes
- yt-dlp may print transient `nsig extraction` warnings; they’re suppressed in output, but downloads still succeed.
- The first run may take longer due to whisper model download; subsequent runs are faster.
- Logs from `codex exec` are captured to a temp file and shown only on failure.

## License
MIT
