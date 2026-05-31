"""Tests for the per-user Hermes session id + simplified todo prompt.

These guard the contract that lets Hermes' built-in memory + session_search
actually span every todo for one user:

    * Every todo for the same user shares one Hermes session id.
    * Different users get different session ids.
    * Per-todo input no longer re-injects the user's memories — Hermes loads
      them from USER.md/MEMORY.md at session start.
    * Image attachments survive the runner -> prompt -> Hermes input pipeline.

Pure stdlib — no Supabase / Hermes / network.
"""
from __future__ import annotations

import unittest
from typing import Any

from runner.prompt import (
    build_prompt as _build_prompt,
    build_resume_prompt as _build_resume_prompt,
    prep_session_id_for_user as _prep_session_id_for_user,
    session_id_for_user as _session_id_for_user,
)


class SessionIdTests(unittest.TestCase):
    def test_same_user_two_todos_share_session(self) -> None:
        user_id = "11111111-1111-1111-1111-111111111111"
        self.assertEqual(
            _session_id_for_user(user_id),
            _session_id_for_user(user_id),
        )

    def test_different_users_get_different_sessions(self) -> None:
        self.assertNotEqual(
            _session_id_for_user("user-a"),
            _session_id_for_user("user-b"),
        )

    def test_session_id_is_prefixed_for_easy_grepping(self) -> None:
        self.assertTrue(
            _session_id_for_user("abc").startswith("doit-user-"),
            "session ids should be identifiable in Hermes session lists",
        )

    def test_prep_session_is_separate_from_main_session(self) -> None:
        # Preparation runs with a strict no-tools system prompt; sharing the
        # main user session would pollute its conversation history. Memory
        # is still per-profile so the prep session still sees user facts.
        user = "abc"
        self.assertNotEqual(
            _prep_session_id_for_user(user),
            _session_id_for_user(user),
        )
        self.assertTrue(
            _prep_session_id_for_user(user).startswith("doit-prep-user-"),
        )


class PromptBuilderTests(unittest.TestCase):
    def test_prompt_marks_each_request_as_a_new_todo(self) -> None:
        prompt = _build_prompt("Send a test email", "")
        # Stable session means task boundaries have to come from the prompt.
        self.assertTrue(prompt.startswith("New todo task:"))
        self.assertIn("Send a test email", prompt)
        self.assertIn("Original user request:", prompt)

    def test_prompt_does_not_inject_user_memories(self) -> None:
        # The whole point of leaning on Hermes native memory: per-todo input
        # should not enumerate the user's facts (Hermes' frozen snapshot
        # already does that).
        prompt = _build_prompt("Buy groceries", "milk + eggs")
        self.assertNotIn("Visible user memories", prompt)
        self.assertIn("milk + eggs", prompt)

    def test_prompt_keeps_original_request_as_source_of_truth(self) -> None:
        prompt = _build_prompt(
            "Send a test email",
            "",
            original_title="Send a test email to gabemitchell93@gmail.com",
            preparation_summary="Send a simple test email.",
            connection_slug="gmail",
        )
        self.assertIn("source of truth", prompt)
        self.assertIn("Send a test email to gabemitchell93@gmail.com", prompt)
        self.assertIn("Prepared title:\nSend a test email", prompt)
        self.assertIn("Preparation summary:\nSend a simple test email.", prompt)
        self.assertIn("Expected connection/toolkit:\ngmail", prompt)

    def test_resume_prompt_includes_user_response(self) -> None:
        prompt = _build_resume_prompt(
            title="Send a test email",
            detail="",
            original_title="Send a test email to gabe@test.com",
            interaction={
                "prompt": "Send this draft?",
                "payload": {
                    "options": [
                        {"id": "send", "label": "Send"},
                        {"id": "cancel", "label": "Cancel"},
                    ],
                },
                "response": {"option_id": "send", "text": ""},
            },
        )
        self.assertIn("Send this draft?", prompt)
        self.assertIn("Send", prompt)
        self.assertIn("option_id=send", prompt)
        self.assertIn("Send a test email to gabe@test.com", prompt)
        self.assertTrue(prompt.startswith("New todo task:"))


class _FakeAttachmentDB:
    """Minimal stand-in for runner.db.DB for attachment-resolution tests.

    Returns rows in insertion order. ``sign_attachment_url`` formats a
    deterministic signed URL so tests can assert against it without standing
    up Supabase Storage.
    """

    def __init__(self, rows: list[dict[str, Any]]) -> None:
        self._rows = rows

    def list_todo_attachments(self, todo_id: str) -> list[dict[str, Any]]:
        return [r for r in self._rows if r.get("todo_id") == todo_id]

    def sign_attachment_url(self, storage_path: str, **_: Any) -> str | None:
        if storage_path.endswith(".broken"):
            return None
        return f"https://signed.test/{storage_path}?token=abc"


class RunnerAttachmentPipelineTests(unittest.TestCase):
    """The runner is supposed to look up attachment rows, sign each path,
    and pass the signed URLs into the prompt builder. We exercise both ends
    of that handoff with a fake DB.
    """

    def test_resolve_returns_signed_urls_in_order(self) -> None:
        from runner.runner import _resolve_attachment_urls  # late import

        db = _FakeAttachmentDB(
            [
                {"todo_id": "T1", "storage_path": "u/T1/a.jpg"},
                {"todo_id": "T1", "storage_path": "u/T1/b.jpg"},
                {"todo_id": "T2", "storage_path": "u/T2/x.jpg"},
            ]
        )
        urls = _resolve_attachment_urls(db, "T1")
        self.assertEqual(
            urls,
            [
                "https://signed.test/u/T1/a.jpg?token=abc",
                "https://signed.test/u/T1/b.jpg?token=abc",
            ],
        )

    def test_resolve_drops_rows_that_fail_to_sign(self) -> None:
        from runner.runner import _resolve_attachment_urls

        db = _FakeAttachmentDB(
            [
                {"todo_id": "T1", "storage_path": "u/T1/a.jpg"},
                {"todo_id": "T1", "storage_path": "u/T1/missing.broken"},
            ]
        )
        urls = _resolve_attachment_urls(db, "T1")
        self.assertEqual(urls, ["https://signed.test/u/T1/a.jpg?token=abc"])

    def test_resolved_urls_appear_in_hermes_input(self) -> None:
        from runner.runner import _resolve_attachment_urls

        db = _FakeAttachmentDB(
            [{"todo_id": "T1", "storage_path": "u/T1/a.jpg"}]
        )
        urls = _resolve_attachment_urls(db, "T1")
        prompt = _build_prompt("Look at this", "", attachment_urls=urls)
        self.assertIn("Attachments (images):", prompt)
        self.assertIn("https://signed.test/u/T1/a.jpg?token=abc", prompt)
        self.assertIn("vision_analyze", prompt)


if __name__ == "__main__":
    unittest.main()
