import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch, Mock

spec = importlib.util.spec_from_file_location(
    "dictation", Path(__file__).resolve().parents[1] / "nixos/hosts/rocket/dictation.py"
)
dictation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dictation)


class DictationTests(unittest.TestCase):
    def run_session(self, text="hello", failure=False, timeout=False):
        recorder = Mock(returncode=0)
        recorder.poll.return_value = 0
        if timeout:
            recorder.wait.side_effect = [subprocess.TimeoutExpired("pw-record", 300), 0]
        copied = []

        def run(command, **kwargs):
            if command[0] == "whisper-cli":
                if failure:
                    raise subprocess.CalledProcessError(1, command)
                Path(command[-1] + ".txt").write_text(text)
            elif command[0] == "wl-copy":
                copied.append(command[-1])
            return subprocess.CompletedProcess(command, 0)

        with tempfile.TemporaryDirectory() as runtime:
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime), \
                 patch.object(dictation.sys, "argv", ["dictation.py", "model"]), \
                 patch.object(dictation.signal, "signal"), \
                 patch.object(dictation.subprocess, "Popen", return_value=recorder), \
                 patch.object(dictation.subprocess, "run", side_effect=run):
                if failure:
                    with self.assertRaises(subprocess.CalledProcessError):
                        dictation.main()
                else:
                    dictation.main()
            self.assertEqual(list(Path(runtime).iterdir()), [])
        return copied, recorder

    def test_transcript_copied_and_private_files_removed(self):
        copied, _ = self.run_session("  hello world\n")
        self.assertEqual(copied, ["hello world"])

    def test_empty_transcript_preserves_clipboard(self):
        self.assertEqual(self.run_session(" \n")[0], [])

    def test_failed_transcription_preserves_clipboard_and_removes_audio(self):
        self.assertEqual(self.run_session(failure=True)[0], [])

    def test_recording_limit_finishes_with_sigint(self):
        _, recorder = self.run_session(timeout=True)
        recorder.send_signal.assert_called_once_with(signal.SIGINT)

    def test_cancel_exits_cleanly(self):
        with self.assertRaises(SystemExit) as result:
            dictation.cancel()
        self.assertEqual(result.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
