"""Unit tests for the browse.sh-to-Hermes bridge script."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[2] / "hermes" / "scripts" / "sync_browse_skill.py"
SPEC = importlib.util.spec_from_file_location("sync_browse_skill", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
sync_browse_skill = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_browse_skill)


class SyncBrowseSkillTests(unittest.TestCase):
    def test_skill_name_prefers_frontmatter(self) -> None:
        skill_md = "---\nname: search-flights\n---\n\nUse browse to search flights."

        name = sync_browse_skill._skill_name(skill_md, {}, "google.com/search-flights-ts4g1f")

        self.assertEqual(name, "search-flights")

    def test_query_candidates_include_domain_and_keyword_fallbacks(self) -> None:
        candidates = sync_browse_skill._query_candidates(
            "Find a cheap flight on google.com from SFO to JFK"
        )

        self.assertEqual(candidates[0], "Find a cheap flight on google.com from SFO to JFK")
        self.assertIn("google.com", candidates)
        self.assertIn("flights", candidates)

    def test_query_candidates_include_rental_car_fallback(self) -> None:
        candidates = sync_browse_skill._query_candidates(
            "Find me a rental car in Denver next Friday"
        )

        self.assertIn("rental cars", candidates)

    def test_relevance_accepts_flight_skill(self) -> None:
        skill = {
            "hostname": "google.com",
            "name": "search-flights",
            "title": "Google Flights Cheapest-Itinerary Search",
            "description": "Search Google Flights for one-way or round-trip itineraries.",
            "tags": ["travel", "flights", "read-only"],
            "category": "travel",
        }

        self.assertTrue(
            sync_browse_skill._is_confident_match(
                "Can you find me a flight next Friday from SFO to Denver?",
                skill,
            )
        )

    def test_relevance_rejects_tracking_skill_for_flight_search(self) -> None:
        skill = {
            "hostname": "flightaware.com",
            "name": "track-flight",
            "title": "Track Flight Status",
            "description": "Track a known flight by flight number.",
            "tags": ["flight", "tracking", "status"],
        }

        self.assertFalse(
            sync_browse_skill._is_confident_match(
                "Can you find me a flight next Friday from SFO to Denver?",
                skill,
            )
        )

    def test_relevance_accepts_rental_car_skill(self) -> None:
        skill = {
            "hostname": "costcotravel.com",
            "name": "get-rental-car-price",
            "title": "Costco Travel Rental Car Price Lookup",
            "description": "Return rental-car prices for a pickup location and date.",
            "tags": ["travel", "rental-cars", "read-only"],
            "category": "travel",
        }

        self.assertTrue(
            sync_browse_skill._is_confident_match(
                "Find me a rental car in Denver next Friday",
                skill,
            )
        )

    def test_relevance_rejects_non_browser_grocery_summary(self) -> None:
        skill = {
            "hostname": "instacart.com",
            "name": "shop-groceries",
            "title": "Grocery Shopping",
            "description": "Search grocery delivery prices.",
            "tags": ["grocery", "shopping"],
        }

        self.assertFalse(
            sync_browse_skill._is_confident_match(
                "Summarize my grocery list into categories",
                skill,
            )
        )

    def test_relevance_rejects_unrelated_result(self) -> None:
        skill = {
            "hostname": "ticketmaster.com",
            "name": "search-concert-tickets",
            "title": "Concert Ticket Search",
            "description": "Find event tickets.",
            "tags": ["concerts", "tickets"],
        }

        self.assertFalse(
            sync_browse_skill._is_confident_match(
                "Find me a rental car in Denver next Friday",
                skill,
            )
        )

    def test_same_install_uses_marker_metadata(self) -> None:
        metadata = {
            "slug": "google.com/search-flights-ts4g1f",
            "updated": "2026-06-01T00:00:00Z",
            "skill_md_url": "https://browse.sh/skill.md",
        }
        with tempfile.TemporaryDirectory() as tmp_name:
            dest = Path(tmp_name) / "search-flights"
            dest.mkdir()
            (dest / "SKILL.md").write_text("---\nname: search-flights\n---\n")
            (dest / ".doit-browse-skill.json").write_text(json.dumps(metadata))

            self.assertTrue(sync_browse_skill._same_install(dest, metadata))
            self.assertFalse(sync_browse_skill._same_install(dest, {**metadata, "updated": "newer"}))


if __name__ == "__main__":
    unittest.main()
