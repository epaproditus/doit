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
