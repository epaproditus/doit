from __future__ import annotations

import unittest

from runner.memory_dedupe import best_duplicate_memory, memory_similarity_score


class MemoryDedupeTests(unittest.TestCase):
    def test_near_duplicate_memory_selects_existing_row(self) -> None:
        existing = {
            "id": "mem-1",
            "title": "San Francisco address",
            "body": "User currently lives at 123 Market Street in San Francisco.",
        }
        candidate = {
            "title": "Current San Francisco address",
            "body": "User's current address is 123 Market St, San Francisco.",
        }

        self.assertGreaterEqual(memory_similarity_score(existing, candidate), 0.62)
        self.assertEqual(best_duplicate_memory([existing], candidate), existing)

    def test_distinct_memory_does_not_merge(self) -> None:
        existing = {
            "id": "mem-1",
            "title": "Preferred signoff",
            "body": "User wants email signoffs to be Gabe.",
        }
        candidate = {
            "title": "Wife",
            "body": "User's wife is Alessandra.",
        }

        self.assertLess(memory_similarity_score(existing, candidate), 0.62)
        self.assertIsNone(best_duplicate_memory([existing], candidate))


if __name__ == "__main__":
    unittest.main()
