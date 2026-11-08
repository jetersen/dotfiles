from contextlib import nullcontext
import importlib.util
import math
import shutil
import struct
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
import wave
from unittest.mock import patch, Mock

spec = importlib.util.spec_from_file_location(
    "dictation", Path(__file__).resolve().parents[1] / "nixos/hosts/rocket/dictation.py"
)
dictation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dictation)


class DictationTests(unittest.TestCase):
    def run_session(self, text="hello", failure=False, timeout=False,
                    recorder_code=0, finish=False, invalid_audio=False, recording_failure=False,
                    typing_failure=False, empty_audio=False):
        recorder = Mock(returncode=recorder_code)
        recorder.poll.return_value = None
        handlers = {}
        typed = []
        notices = []

        def start_recorder(command):
            recording = Path(command[command.index("silence") - 1])
            if invalid_audio:
                recording.write_bytes(b"invalid")
            else:
                with wave.open(str(recording), "wb") as audio:
                    audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                    audio.writeframes(b"\x00\x00" * (0 if empty_audio else 1600))
            return recorder

        def wait_recorder(**kwargs):
            if timeout and recorder.wait.call_count == 1:
                raise subprocess.TimeoutExpired("rec", 300)
            if finish:
                handlers[signal.SIGINT]()
            recorder.poll.return_value = recorder_code
            return recorder_code

        recorder.wait.side_effect = wait_recorder

        def run(command, **kwargs):
            # Every path, including typing failures, must leave clipboard history alone.
            self.assertNotIn(Path(command[0]).name, ["wl-copy", "wl-paste", "systemd-run"])
            if command[0] == "whisper-cli":
                if failure:
                    raise subprocess.CalledProcessError(1, command)
                Path(command[-1] + ".txt").write_text(text)
            elif command[0] == "wtype":
                if typing_failure:
                    raise subprocess.CalledProcessError(1, command)
                typed.append(command[-1])
            elif command[0] == "notify-send":
                notices.append(command[-1])
            return subprocess.CompletedProcess(command, 0)

        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime), \
                 patch.object(dictation.sys, "argv", ["dictation.py", "model"]), \
                 patch.object(dictation, "paused_media", side_effect=nullcontext), \
                 patch.object(dictation.signal, "signal", side_effect=handlers.__setitem__), \
                 patch.object(dictation.subprocess, "Popen", side_effect=start_recorder), \
                 patch.object(dictation.subprocess, "run", side_effect=run):
                if failure or recording_failure:
                    with self.assertRaises(subprocess.CalledProcessError if failure else RuntimeError):
                        dictation.main()
                else:
                    dictation.main()
            self.assertEqual(list(Path(runtime).iterdir()), [])
        if typing_failure:
            self.assertEqual(typed, [])
            self.assertIn("Automatic typing failed. Focus a text field and dictate again.", notices)
        return typed, recorder

    def test_transcript_typed_and_private_files_removed(self):
        typed, _ = self.run_session("  hello world\n")
        self.assertEqual(typed, ["hello world"])

    def test_empty_transcript_inserts_nothing(self):
        self.assertEqual(self.run_session(" \n")[0], [])

    def test_failed_transcription_inserts_nothing_and_removes_audio(self):
        self.assertEqual(self.run_session(failure=True)[0], [])

    def test_recording_limit_finishes_with_sigint(self):
        _, recorder = self.run_session(timeout=True, recorder_code=-signal.SIGINT)
        recorder.send_signal.assert_called_once_with(signal.SIGINT)

    def test_requested_stop_accepts_recorder_sigint(self):
        typed, recorder = self.run_session(recorder_code=-signal.SIGINT, finish=True)
        self.assertEqual(typed, ["hello"])
        recorder.send_signal.assert_called_once_with(signal.SIGINT)

    def test_unexpected_recorder_failure_inserts_nothing(self):
        self.assertEqual(self.run_session(recorder_code=1, recording_failure=True)[0], [])

    def test_requested_stop_still_rejects_invalid_audio(self):
        self.assertEqual(self.run_session(recorder_code=-signal.SIGINT, finish=True,
                                         invalid_audio=True, recording_failure=True)[0], [])

    def test_silence_only_recording_inserts_nothing(self):
        self.assertEqual(self.run_session(empty_audio=True)[0], [])

    def test_typing_failure_has_no_clipboard_fallback(self):
        self.assertEqual(self.run_session(typing_failure=True)[0], [])

    def test_cancel_exits_cleanly(self):
        with self.assertRaises(SystemExit) as result:
            dictation.cancel()
        self.assertEqual(result.exception.code, 0)


class MediaTests(unittest.TestCase):
    def check_session(self, changed=None, failure=False, pause_failure=False):
        states = {"zen": "Playing", "music": "Playing", "idle": "Paused"}
        actions = []

        def command(*arguments):
            if arguments == ("--list-all",):
                return "\n".join(states)
            player = arguments[0].split("=", 1)[1]
            action = arguments[1]
            if action == "status":
                return states[player]
            if action == "pause" and pause_failure and player == "music":
                return None
            actions.append((player, action))
            states[player] = "Paused" if action == "pause" else "Playing"
            return ""

        with patch.object(dictation, "media_command", side_effect=command):
            try:
                with dictation.paused_media():
                    self.assertEqual(states["zen"], "Paused")
                    self.assertEqual(states["idle"], "Paused")
                    if changed == "closed":
                        states["zen"] = None
                    elif changed == "state":
                        states["zen"] = "Playing"
                    if failure:
                        raise SystemExit(0)
            except SystemExit:
                if not failure:
                    raise
        self.assertNotIn(("idle", "play"), actions)
        self.assertNotIn(("idle", "pause"), actions)
        return states, actions

    def test_playing_players_resume_and_paused_players_stay_paused(self):
        states, _ = self.check_session()
        self.assertEqual(states, {"zen": "Playing", "music": "Playing", "idle": "Paused"})

    def test_cancellation_restores_playback(self):
        states, _ = self.check_session(failure=True)
        self.assertEqual(states["zen"], "Playing")
        self.assertEqual(states["music"], "Playing")

    def test_closed_player_is_not_resumed(self):
        states, actions = self.check_session(changed="closed")
        self.assertIsNone(states["zen"])
        self.assertNotIn(("zen", "play"), actions)

    def test_user_resumed_player_is_left_alone(self):
        _, actions = self.check_session(changed="state")
        self.assertNotIn(("zen", "play"), actions)

    def test_failed_pause_is_not_followed_by_play(self):
        _, actions = self.check_session(pause_failure=True)
        self.assertNotIn(("music", "play"), actions)

    def test_no_players_is_allowed(self):
        with patch.object(dictation, "media_command", return_value=None):
            with dictation.paused_media():
                pass


@unittest.skipUnless(shutil.which("sox"), "SoX required for silence integration test")
class SilenceTests(unittest.TestCase):
    def check_pauses(self, amplitude):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.wav"
            target = Path(directory) / "output.wav"
            samples = []
            # Speech after the long pause must never reach the output.
            for duration, speech in [(.5, False), (.5, True), (1, False),
                                     (.5, True), (5, False), (.5, True)]:
                samples.extend(
                    int(amplitude * math.sin(2 * math.pi * 440 * i / 16000)) if speech else 0
                    for i in range(int(duration * 16000))
                )
            with wave.open(str(source), "wb") as audio:
                audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                audio.writeframes(struct.pack("<" + "h" * len(samples), *samples))
            command = dictation.recording_command(target)
            effects = command[command.index("silence"):]
            subprocess.run(["sox", str(source), str(target), *effects], check=True)
            with wave.open(str(target)) as audio:
                duration = audio.getnframes() / audio.getframerate()
            self.assertGreater(duration, 2.4)
            self.assertLess(duration, 2.6)

    def test_short_pause_continues_and_long_pause_ends_recording(self):
        self.check_pauses(10000)

    def test_quiet_speech_below_old_three_percent_threshold_is_retained(self):
        self.check_pauses(600)

    def test_quiet_first_word_is_preserved_before_louder_speech(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.wav"
            target = Path(directory) / "output.wav"
            samples = []
            for duration, amplitude in [(.2, 100), (.6, 2000), (4, 0)]:
                samples.extend(
                    int(amplitude * math.sin(2 * math.pi * 440 * i / 16000))
                    for i in range(int(duration * 16000))
                )
            with wave.open(str(source), "wb") as audio:
                audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                audio.writeframes(struct.pack("<" + "h" * len(samples), *samples))
            command = dictation.recording_command(target)
            subprocess.run(["sox", str(source), str(target),
                            *command[command.index("silence"):]], check=True)
            with wave.open(str(target)) as audio:
                self.assertGreater(audio.getnframes() / audio.getframerate(), .8)
                beginning = struct.unpack("<" + "h" * 1600, audio.readframes(1600))
            self.assertGreater(max(map(abs, beginning)), 0)
            self.assertLessEqual(max(map(abs, beginning)), 101)


if __name__ == "__main__":
    unittest.main()
