"""Source-preservation and stable identity checks for the T3 search adapter."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "nixos/hosts/rocket/agent-observability"))

import io
import unittest
import urllib.parse
from unittest.mock import patch

from t3_search import conversation, import_batch, post_import


class ConversationTests(unittest.TestCase):
    def test_export_preserves_identity_links_and_excludes_streaming_messages(self):
        thread = {
            "id": "thread-1",
            "title": "Example",
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-02T00:00:00Z",
            "settledOverride": "settled",
        }

        def message(mid, role, text, streaming=False):
            return {
                "id": mid,
                "role": role,
                "text": text,
                "streaming": streaming,
                "createdAt": "2026-01-01T00:00:00Z",
            }

        result = conversation(
            thread,
            [
                message("u", "user", "Question"),
                message("a", "assistant", "Answer"),
                message("live", "assistant", "Partial", True),
            ],
            "environment",
        )
        self.assertEqual(result["id"], "t3-thread-1")
        self.assertEqual(list(result["mapping"]), ["u", "a"])
        self.assertEqual(result["mapping"]["a"]["parent"], "u")
        self.assertEqual(result["mapping"]["u"]["children"], ["a"])
        self.assertIn(
            "t3-thread://v2/environment/thread-1",
            result["mapping"]["u"]["message"]["content"]["parts"][0],
        )
        self.assertIn("marked settled", result["title"])
        self.assertEqual(result["current_node"], "a")
        self.assertEqual(thread["title"], "Example")

    def test_unmarked_is_reviewable_not_claimed_incomplete(self):
        thread = {
            "id": "thread-2",
            "title": "Example",
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
        }
        self.assertIn("review in T3", conversation(thread, [], "e")["title"])


class RefreshTests(unittest.TestCase):
    def test_changed_copy_retries_only_refused_t3_conversation(self):
        for reason in ["diverged", "shorter_export"]:
            with self.subTest(reason=reason):
                batch = [{"id": "t3-changed"}, {"id": "t3-unchanged"}]
                calls = []

                def post(items, replace=()):
                    calls.append((items, list(replace)))
                    if len(calls) == 1:
                        return {
                            "errors": 1,
                            "refusals": [{"session_id": "chatgpt:t3-changed", "reason": reason}],
                        }
                    return {"errors": 0}

                import_batch(batch, post=post)
                self.assertEqual(calls[0], (batch, []))
                self.assertEqual(calls[1], ([batch[0]], ["chatgpt:t3-changed"]))

    def test_user_trashed_copy_is_not_resurrected(self):
        calls = []

        def post(items, replace=()):
            calls.append(items)
            return {
                "errors": 1,
                "refusals": [{"session_id": "chatgpt:t3-hidden", "reason": "trashed"}],
            }

        import_batch([{"id": "t3-hidden"}], post=post)
        self.assertEqual(len(calls), 1)

    def test_unknown_or_unrelated_failure_never_authorizes_replacement(self):
        for result in [
            {"errors": 1},
            {"errors": 1, "refusals": [{"session_id": "chatgpt:t3-other", "reason": "diverged"}]},
            {
                "errors": 1,
                "refusals": [{"session_id": "chatgpt:t3-current", "reason": "transient"}],
            },
            {"errors": 2, "refusals": [{"session_id": "chatgpt:t3-current", "reason": "diverged"}]},
        ]:
            with self.subTest(result=result):
                calls = []

                def post(items, replace=()):
                    calls.append(items)
                    return result

                with self.assertRaises(RuntimeError):
                    import_batch([{"id": "t3-current"}], post=post)
                self.assertEqual(len(calls), 1)

    def test_failed_replacement_remains_an_error(self):
        results = iter(
            [
                {
                    "errors": 1,
                    "refusals": [{"session_id": "chatgpt:t3-current", "reason": "diverged"}],
                },
                {"errors": 1},
            ]
        )
        with self.assertRaises(RuntimeError):
            import_batch([{"id": "t3-current"}], post=lambda *args, **kwargs: next(results))

    def test_replacement_uses_supported_exact_session_query_parameter(self):
        sid = "chatgpt:t3-identifier/with:punctuation"
        with patch(
            "t3_search.urllib.request.urlopen", return_value=io.BytesIO(b'{"errors":0}')
        ) as opened:
            post_import([{"id": "t3-identifier/with:punctuation"}], replace=[sid])
        query = urllib.parse.urlsplit(opened.call_args.args[0].full_url).query
        self.assertEqual(urllib.parse.parse_qs(query), {"replace": [sid]})


if __name__ == "__main__":
    unittest.main()
