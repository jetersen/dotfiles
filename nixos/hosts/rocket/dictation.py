"""Record local microphone audio, transcribe on Vulkan, and copy the result."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


def notify(message):
    subprocess.run(["notify-send", "Dictation", message], check=False)


def transcribe(model, recording, output):
    subprocess.run(
        ["whisper-cli", "-m", model, "-f", str(recording), "-l", "auto",
         "-nt", "-np", "-otxt", "-of", str(output)],
        check=True,
    )
    return Path(str(output) + ".txt").read_text().strip()


def cancel(*_):
    raise SystemExit(0)


def main():
    signal.signal(signal.SIGTERM, cancel)
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="dictation-", dir=os.environ["XDG_RUNTIME_DIR"]) as directory:
        recording = Path(directory) / "recording.wav"
        # SIGINT finishes recording. SIGTERM (systemctl stop) cancels the session.
        recorder = subprocess.Popen([
            "pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", str(recording),
        ])
        signal.signal(signal.SIGINT, lambda *_: recorder.send_signal(signal.SIGINT) if recorder.poll() is None else None)
        try:
            notify("Listening. Press Super+Shift+D again to finish (maximum five minutes).")
            try:
                recorder.wait(timeout=300)
            except subprocess.TimeoutExpired:
                recorder.send_signal(signal.SIGINT)
                recorder.wait(timeout=10)
            if recorder.returncode not in (0, -signal.SIGINT):
                raise RuntimeError("Microphone recording failed")
            notify("Transcribing on the GPU…")
            text = transcribe(sys.argv[1], recording, Path(directory) / "transcript")
            if text:
                subprocess.run(["wl-copy", "--type", "text/plain", "--", text], check=True)
                notify("Copied transcript. Press Ctrl+V to paste.")
            else:
                notify("No speech detected. Clipboard unchanged.")
        finally:
            if recorder.poll() is None:
                recorder.terminate()
                recorder.wait(timeout=10)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        notify("Dictation failed. See journalctl --user -u dictation.")
        print(error, file=sys.stderr)
        sys.exit(1)
