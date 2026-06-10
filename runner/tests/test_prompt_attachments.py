"""Image-attachment plumbing in the prompt builders.

The /v1/runs API is text-only, but Hermes' built-in `vision_analyze` tool can
fetch any URL. So our integration is just: append signed URLs to the end of
the task prompt with a one-line nudge.

These tests pin that contract so a future refactor doesn't silently drop
attachments before they reach the agent.
"""
from __future__ import annotations

import unittest

from runner.prepare import build_prepare_prompt
from runner.prompt import build_prompt, build_resume_prompt


URL_A = "https://supabase.test/storage/v1/object/sign/todo-attachments/u/t/a.jpg?token=A"
URL_B = "https://supabase.test/storage/v1/object/sign/todo-attachments/u/t/b.jpg?token=B"


class BuildPromptAttachmentTests(unittest.TestCase):
    def test_no_attachments_keeps_prompt_unchanged(self) -> None:
        without = build_prompt("Send an email", "")
        with_none = build_prompt("Send an email", "", attachment_urls=None)
        with_empty = build_prompt("Send an email", "", attachment_urls=[])
        self.assertEqual(without, with_none)
        self.assertEqual(without, with_empty)
        self.assertNotIn("Attachments (images):", without)

    def test_attachments_block_is_appended_with_each_url(self) -> None:
        prompt = build_prompt(
            "Caption these photos",
            "",
            attachment_urls=[URL_A, URL_B],
        )
        self.assertIn("Attachments (images):", prompt)
        self.assertIn(f"- {URL_A}", prompt)
        self.assertIn(f"- {URL_B}", prompt)
        self.assertIn("vision_analyze", prompt)
        # The block is at the end so the agent sees the task framing first.
        self.assertTrue(prompt.rstrip().endswith("looking at them."))

    def test_resume_prompt_inlines_attachments_after_resume_block(self) -> None:
        prompt = build_resume_prompt(
            title="Caption these photos",
            detail="",
            interaction={
                "prompt": "Use this caption?",
                "payload": {"options": [{"id": "send", "label": "Send"}]},
                "response": {"option_id": "send", "text": ""},
            },
            attachment_urls=[URL_A],
        )
        self.assertIn("You previously asked the user:", prompt)
        # Both the resume context and the attachments block must survive.
        self.assertIn("option_id=send", prompt)
        self.assertIn("Attachments (images):", prompt)
        self.assertIn(f"- {URL_A}", prompt)
        # Attachments block comes after the resume context.
        self.assertLess(
            prompt.index("option_id=send"),
            prompt.index("Attachments (images):"),
        )

    def test_blank_urls_are_dropped(self) -> None:
        prompt = build_prompt(
            "Anything",
            "",
            attachment_urls=["", "   ", URL_A],
        )
        self.assertIn(f"- {URL_A}", prompt)
        # Empty / whitespace-only entries don't render as bullets.
        self.assertNotIn("- \n", prompt)
        self.assertNotIn("-   ", prompt)


class FollowupAttachmentClarityTests(unittest.TestCase):
    """Phase 7: label new vs processed attachments; frame image-only sends."""

    def test_first_run_flat_block_is_unchanged(self) -> None:
        # No processed urls → today's flat format, byte-identical.
        flat = build_prompt("Log this receipt", "", attachment_urls=[URL_A])
        explicit = build_prompt(
            "Log this receipt",
            "",
            attachment_urls=[URL_A],
            processed_attachment_urls=[],
        )
        self.assertEqual(flat, explicit)
        self.assertNotIn("Previously processed", flat)
        self.assertNotIn("Newly attached", flat)

    def test_followup_labels_processed_and_new_attachments(self) -> None:
        from runner.prompt import build_followup_prompt

        prompt = build_followup_prompt(
            "Log this receipt",
            "",
            messages=["here's another one"],
            attachment_urls=[URL_B],
            processed_attachment_urls=[URL_A],
        )
        self.assertIn("Previously processed (do not re-process unless asked):", prompt)
        self.assertIn("Newly attached since the last run:", prompt)
        # Old receipt under "processed", new receipt under "newly attached".
        self.assertLess(
            prompt.index("Previously processed"),
            prompt.index(f"- {URL_A}"),
        )
        self.assertLess(
            prompt.index(f"- {URL_A}"),
            prompt.index("Newly attached since the last run:"),
        )
        self.assertLess(
            prompt.index("Newly attached since the last run:"),
            prompt.index(f"- {URL_B}"),
        )

    def test_image_only_followup_gets_new_attachment_framing(self) -> None:
        from runner.prompt import build_followup_prompt

        prompt = build_followup_prompt(
            "Log this receipt",
            "",
            messages=[],
            attachment_urls=[URL_B],
            processed_attachment_urls=[URL_A],
        )
        self.assertIn(
            "The user sent new image attachment(s) with no message", prompt
        )
        self.assertIn("do not redo work already completed", prompt)
        self.assertIn("Newly attached since the last run:", prompt)

    def test_empty_messages_without_attachments_keeps_bare_fallback(self) -> None:
        from runner.prompt import build_followup_prompt

        prompt = build_followup_prompt("Log this receipt", "", messages=[])
        self.assertNotIn("The user sent new image attachment(s)", prompt)
        self.assertNotIn("Attachments (images):", prompt)


class _FakeSplitDB:
    """Stand-in for runner.db.DB attachment + terminal-step lookups."""

    def __init__(
        self,
        rows: list[dict],
        *,
        last_terminal_ts: str | None,
    ) -> None:
        self._rows = rows
        self._last_terminal_ts = last_terminal_ts

    def get_last_terminal_step_ts(self, todo_id: str) -> str | None:
        return self._last_terminal_ts

    def list_todo_attachments(self, todo_id: str) -> list[dict]:
        return self._rows

    def sign_attachment_url(self, storage_path: str, **_: object) -> str | None:
        return f"https://signed.test/{storage_path}?token=abc"


class ResolveAttachmentSplitTests(unittest.TestCase):
    def test_first_run_puts_everything_in_new(self) -> None:
        from runner.runner import _resolve_attachment_urls_split

        db = _FakeSplitDB(
            [
                {"storage_path": "u/t/a.jpg", "created_at": "2026-06-08T10:00:00+00:00"},
            ],
            last_terminal_ts=None,
        )
        processed, new = _resolve_attachment_urls_split(db, "T1")
        self.assertEqual(processed, [])
        self.assertEqual(new, ["https://signed.test/u/t/a.jpg?token=abc"])

    def test_rows_older_than_last_run_are_processed(self) -> None:
        from runner.runner import _resolve_attachment_urls_split

        db = _FakeSplitDB(
            [
                {"storage_path": "u/t/old.jpg", "created_at": "2026-06-08T10:00:00+00:00"},
                {"storage_path": "u/t/new.jpg", "created_at": "2026-06-09T09:00:00+00:00"},
            ],
            last_terminal_ts="2026-06-08T12:00:00+00:00",
        )
        processed, new = _resolve_attachment_urls_split(db, "T1")
        self.assertEqual(processed, ["https://signed.test/u/t/old.jpg?token=abc"])
        self.assertEqual(new, ["https://signed.test/u/t/new.jpg?token=abc"])

    def test_unparseable_timestamps_fall_back_to_new(self) -> None:
        from runner.runner import _resolve_attachment_urls_split

        db = _FakeSplitDB(
            [{"storage_path": "u/t/x.jpg", "created_at": "not-a-date"}],
            last_terminal_ts="2026-06-08T12:00:00+00:00",
        )
        processed, new = _resolve_attachment_urls_split(db, "T1")
        self.assertEqual(processed, [])
        self.assertEqual(len(new), 1)


class BuildPreparePromptAttachmentTests(unittest.TestCase):
    def test_prepare_prompt_includes_attachments_block(self) -> None:
        prompt = build_prepare_prompt(
            title="Send these receipts",
            detail="",
            attachment_urls=[URL_A, URL_B],
        )
        self.assertIn("Attachments (images):", prompt)
        self.assertIn(f"- {URL_A}", prompt)
        self.assertIn(f"- {URL_B}", prompt)

    def test_prepare_prompt_unchanged_without_attachments(self) -> None:
        without = build_prepare_prompt(title="Send a note", detail="")
        with_none = build_prepare_prompt(
            title="Send a note", detail="", attachment_urls=None
        )
        self.assertEqual(without, with_none)
        self.assertNotIn("Attachments (images):", without)


if __name__ == "__main__":
    unittest.main()
