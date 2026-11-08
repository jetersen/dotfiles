"""Record local microphone audio, transcribe on Vulkan, and copy the result."""

from contextlib import contextmanager
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import wave


def notify(message):
    subprocess.run(["notify-send", "Dictation", message], check=False)


def transcribe(model, recording, output):
    subprocess.run(
        ["whisper-cli", "-m", model, "-f", str(recording), "-l", "auto",
         "-nt", "-np", "-otxt", "-of", str(output)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    return Path(str(output) + ".txt").read_text().strip()


def copy_transcript(text):
    clipboard = shutil.which("wl-copy")
    if clipboard is None:
        raise RuntimeError("wl-copy is unavailable")
    # Wayland clipboard data lives in wl-copy. Run it in a separate service so
    # dictation's cgroup cleanup cannot kill it after this process exits.
    subprocess.run([
        "systemd-run", "--user", "--quiet", "--collect",
        "--description=Dictation clipboard", "--service-type=forking",
        "--", clipboard, "--type", "text/plain", "--", text,
    ], check=True)


def media_command(*arguments):
    try:
        result = subprocess.run(
            ["playerctl", *arguments], capture_output=True, text=True, timeout=2,
        )
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


@contextmanager
def paused_media():
    paused = []
    try:
        players = media_command("--list-all") or ""
        for player in players.splitlines():
            selector = "--player=" + player
            if media_command(selector, "status") != "Playing":
                continue
            if media_command(selector, "pause") is not None:
                paused.append(selector)
        yield
    finally:
        for selector in paused:
            # Leave closed players and user-resumed playback alone.
            if media_command(selector, "status") == "Paused":
                media_command(selector, "play")


def cancel(*_):
    raise SystemExit(0)


def recording_command(recording):
    return [
        "rec", "-q", "-r", "16000", "-c", "1", "-b", "16", str(recording),
        # Keep quiet beginnings; only use silence detection to end recording.
        "silence", "0", "1", "3.5", "0.5%",
    ]


def main():
    signal.signal(signal.SIGTERM, cancel)
    os.umask(0o077)
    with paused_media(), tempfile.TemporaryDirectory(prefix="dictation-", dir=os.environ["XDG_RUNTIME_DIR"]) as directory:
        recording = Path(directory) / "recording.wav"
        # SIGINT finishes recording. SIGTERM (systemctl stop) cancels the session.
        recorder = subprocess.Popen(recording_command(recording))
        stop_requested = False

        def finish_recording(*_):
            nonlocal stop_requested
            if recorder.poll() is None:
                stop_requested = True
                recorder.send_signal(signal.SIGINT)

        signal.signal(signal.SIGINT, finish_recording)
        try:
            # SoX opens its audio input before creating the output file.
            # Do not announce readiness while it is still connecting to the mic.
            deadline = time.monotonic() + 5
            while not recording.exists() and recorder.poll() is None:
                if time.monotonic() >= deadline:
                    raise RuntimeError("Microphone did not become ready")
                time.sleep(0.01)
            if recorder.poll() is None:
                notify("Listening. Stops after 3.5 seconds of silence; press Super+T to finish sooner.")
            try:
                recorder.wait(timeout=300)
            except subprocess.TimeoutExpired:
                finish_recording()
                recorder.wait(timeout=10)
            if recorder.returncode != 0 and not (stop_requested and recorder.returncode == -signal.SIGINT):
                raise RuntimeError(f"Microphone recording failed (exit {recorder.returncode})")
            try:
                with wave.open(str(recording)) as audio:
                    if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 16000):
                        raise RuntimeError("Microphone recording has an unexpected format")
                    print(f"Captured {audio.getnframes() / audio.getframerate():.2f}s after silence filtering", flush=True)
                    if audio.getnframes() == 0:
                        notify("No speech detected. Clipboard unchanged.")
                        return
            except (wave.Error, EOFError) as error:
                raise RuntimeError("Microphone recording is not a valid WAV") from error
            notify("Transcribing on the GPU…")
            text = transcribe(sys.argv[1], recording, Path(directory) / "transcript")
            if text:
                copy_transcript(text)
                try:
                    subprocess.run(["wtype", "--", text], check=True)
                    notify("Transcript inserted.")
                except (OSError, subprocess.SubprocessError):
                    notify("Copied transcript. Automatic typing failed; press Ctrl+V to paste.")
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
