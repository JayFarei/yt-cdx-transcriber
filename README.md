# yt-cdx-transcriber

One-command YouTube audio transcriber that:
- Downloads audio with `yt-dlp`.
- Sends it to `codex exec` (GPT-5.1 Codex mini) to run Whisper in an isolated venv.
- Prints the English transcript and copies it to the macOS clipboard (`pbcopy`).

## Requirements
- macOS (for `pbcopy`).
- `yt-dlp`
- `codex` CLI (logged in and allowed to use `--dangerously-bypass-approvals-and-sandbox`).
- `python3`
- `gh` only if you plan to publish; not needed to run the script.

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
5. Prints the transcript and copies it to the clipboard.

## Notes
- yt-dlp may print transient `nsig extraction` warnings; they’re suppressed in output, but downloads still succeed.
- The first run may take longer due to whisper model download; subsequent runs are faster.
- Logs from `codex exec` are captured to a temp file and shown only on failure.

## License
MIT
