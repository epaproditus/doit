"""Tests for conditional prompt sections + the compact-prose rollback flag.

Phase 2a of the smaller-model plan: one shared prompt surface for every
model, with domain-specific sections (Figma / options / image / TTS)
appended only when task signals say they are relevant, and the compacted
core prose revertible via DOIT_COMPACT_PROMPTS=0.
"""
from __future__ import annotations

import os
import unittest
from unittest import mock

from runner.prompt import build_followup_prompt, build_prompt


def _build(title: str, detail: str = "", **kwargs) -> str:
    return build_prompt(title, detail, **kwargs)


_NUDGE_LINE = "Call session_search with the"


class RecallNudgeTests(unittest.TestCase):
    """Env-gated session_search nudge when the user references prior work."""

    def test_off_by_default(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("DOIT_RECALL_NUDGE", None)
            prompt = _build("Draft it like last time")
        self.assertNotIn(_NUDGE_LINE, prompt)

    def test_enabled_with_recall_phrase_appends_nudge(self) -> None:
        with mock.patch.dict(os.environ, {"DOIT_RECALL_NUDGE": "1"}):
            prompt = _build("Draft the weekly update like last time")
        self.assertIn(_NUDGE_LINE, prompt)

    def test_enabled_without_recall_phrase_unchanged(self) -> None:
        with mock.patch.dict(os.environ, {"DOIT_RECALL_NUDGE": "1"}):
            with_flag = _build("Send a test email to gabe@test.com")
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("DOIT_RECALL_NUDGE", None)
            without_flag = _build("Send a test email to gabe@test.com")
        self.assertEqual(with_flag, without_flag)
        self.assertNotIn(_NUDGE_LINE, with_flag)

    def test_followup_message_recall_phrase_appends_nudge(self) -> None:
        with mock.patch.dict(os.environ, {"DOIT_RECALL_NUDGE": "1"}):
            prompt = build_followup_prompt(
                "Weekly update",
                "",
                messages=["use the draft you made the other day"],
            )
        self.assertIn(_NUDGE_LINE, prompt)


class ConditionalSectionTests(unittest.TestCase):
    def test_plain_email_task_omits_domain_sections(self) -> None:
        prompt = _build("Send a test email to gabe@test.com")
        self.assertNotIn("Figma workflows:", prompt)
        self.assertNotIn("Comparison / booking options", prompt)
        self.assertNotIn("Visual deliverables (image):", prompt)
        # The core contract is always present.
        self.assertIn("[[DOIT_ARTIFACT]]", prompt)
        self.assertIn("Approval policy", prompt)

    def test_figma_slug_includes_figma_and_image_sections(self) -> None:
        prompt = _build("Export the home screen", connection_slug="figma")
        self.assertIn("Figma workflows:", prompt)
        self.assertIn("Visual deliverables (image):", prompt)

    def test_figma_in_text_includes_figma_section(self) -> None:
        prompt = _build("Pull the latest mockups from the doit Figma file")
        self.assertIn("Figma workflows:", prompt)

    def test_visual_wording_includes_image_section_only(self) -> None:
        prompt = _build("Take a screenshot of the pricing page")
        self.assertIn("Visual deliverables (image):", prompt)
        self.assertNotIn("Figma workflows:", prompt)

    def test_booking_wording_includes_options_section(self) -> None:
        prompt = _build("Find flights from SFO to JFK next Tuesday")
        self.assertIn("Comparison / booking options", prompt)
        self.assertIn("booking_option", prompt)

    def test_travel_topic_includes_options_section(self) -> None:
        prompt = _build("Plan my July trip", topic="travel")
        self.assertIn("Comparison / booking options", prompt)

    def test_listing_task_has_no_options_section(self) -> None:
        prompt = _build("List the Github repos you have access to.")
        self.assertNotIn("Comparison / booking options", prompt)

    def test_conditional_sections_shrink_the_prompt(self) -> None:
        # Golden-ish check: a plain task prompt must be meaningfully smaller
        # than a Figma+booking prompt — proof the conditional sections are
        # actually being omitted rather than always appended.
        plain = _build("Send a test email to gabe@test.com")
        loaded = _build(
            "Compare flights and update the Figma travel mockup",
            connection_slug="figma",
            topic="travel",
        )
        self.assertLess(len(plain), len(loaded) * 0.7)


class CompactFlagTests(unittest.TestCase):
    def test_compact_is_default(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("DOIT_COMPACT_PROMPTS", None)
            prompt = _build("Send a test email")
        self.assertIn("Artifacts (user-visible deliverables) — contract:", prompt)

    def test_flag_off_restores_legacy_prose(self) -> None:
        with mock.patch.dict(os.environ, {"DOIT_COMPACT_PROMPTS": "0"}):
            prompt = _build("Send a test email")
        self.assertIn("Artifacts (user-visible deliverables):", prompt)
        self.assertNotIn("— contract:", prompt)
        # Legacy approval prose markers.
        self.assertIn("The Doit `+` sheet now auto-runs every prepared task", prompt)

    def test_compact_prompt_is_smaller_than_legacy(self) -> None:
        with mock.patch.dict(os.environ, {"DOIT_COMPACT_PROMPTS": "1"}):
            compact = _build("Send a test email")
        with mock.patch.dict(os.environ, {"DOIT_COMPACT_PROMPTS": "0"}):
            legacy = _build("Send a test email")
        self.assertLess(len(compact), len(legacy))

    def test_both_variants_keep_critical_contracts(self) -> None:
        for flag in ("1", "0"):
            with mock.patch.dict(os.environ, {"DOIT_COMPACT_PROMPTS": flag}):
                prompt = _build("Send a test email")
            self.assertIn("[[DOIT_ARTIFACT]]", prompt)
            self.assertIn("[[DOIT_INTERACTION]]", prompt)
            self.assertIn("Approval policy", prompt)
            lowered = prompt.lower()
            self.assertIn("sending an email", lowered)
            self.assertIn("placeholder", lowered)


if __name__ == "__main__":
    unittest.main()
