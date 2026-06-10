"""Tests for browse.sh skill preflight decisions."""
from __future__ import annotations

import unittest

from runner.browse_skill import browse_skill_query_for_todo, should_prefetch_browse_skill


class BrowseSkillPreflightTests(unittest.TestCase):
    def test_prefetches_for_any_non_empty_task(self) -> None:
        self.assertTrue(should_prefetch_browse_skill("Check prices on google.com for flights"))
        self.assertTrue(should_prefetch_browse_skill("Find the cheapest SFO to JFK flight"))
        self.assertTrue(should_prefetch_browse_skill("Find me a rental car in Denver next Friday"))
        self.assertTrue(should_prefetch_browse_skill("Summarize my grocery list into categories"))

    def test_skips_empty_task(self) -> None:
        self.assertFalse(should_prefetch_browse_skill(""))
        self.assertFalse(should_prefetch_browse_skill("   "))

    def test_query_combines_relevant_todo_fields(self) -> None:
        query = browse_skill_query_for_todo(
            {
                "original_title": "Book a hotel",
                "title": "Find a hotel",
                "detail": "Near Union Square",
                "preparation_summary": "Use public hotel sites",
                "connection_slug": "",
            }
        )

        self.assertIn("Book a hotel", query)
        self.assertIn("Near Union Square", query)
        self.assertIn("Use public hotel sites", query)


if __name__ == "__main__":
    unittest.main()
