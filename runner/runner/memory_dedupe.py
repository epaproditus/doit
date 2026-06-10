from __future__ import annotations

import re
from typing import Any


_MEMORY_STOPWORDS = {
    "a",
    "an",
    "and",
    "around",
    "as",
    "at",
    "be",
    "because",
    "but",
    "by",
    "can",
    "could",
    "for",
    "from",
    "has",
    "have",
    "in",
    "is",
    "it",
    "may",
    "my",
    "not",
    "of",
    "on",
    "or",
    "the",
    "their",
    "this",
    "to",
    "user",
    "users",
    "was",
    "with",
}


def memory_similarity_score(existing: dict, candidate: dict) -> float:
    """Deterministic duplicate score for extracted memory rows."""
    existing_text = f"{existing.get('title') or ''} {existing.get('body') or ''}"
    candidate_text = f"{candidate.get('title') or ''} {candidate.get('body') or ''}"
    existing_tokens = _memory_tokens(existing_text)
    candidate_tokens = _memory_tokens(candidate_text)
    if not existing_tokens or not candidate_tokens:
        return 0.0
    intersection = existing_tokens & candidate_tokens
    union = existing_tokens | candidate_tokens
    jaccard = len(intersection) / len(union)
    containment = len(intersection) / min(len(existing_tokens), len(candidate_tokens))
    exact_bonus = 0.15 if _canonical_memory_text(existing.get("body")) == _canonical_memory_text(candidate.get("body")) else 0.0
    return min(1.0, max(jaccard, containment * 0.8) + exact_bonus)


def best_duplicate_memory(existing_rows: list[dict], candidate: dict) -> dict | None:
    best: tuple[float, dict] | None = None
    for row in existing_rows:
        score = memory_similarity_score(row, candidate)
        if best is None or score > best[0]:
            best = (score, row)
    if best is None:
        return None
    return best[1] if best[0] >= 0.62 else None


def _memory_tokens(text: str) -> set[str]:
    raw = re.findall(r"[a-z0-9]+", (text or "").lower())
    return {token for token in raw if len(token) > 2 and token not in _MEMORY_STOPWORDS}


def _canonical_memory_text(value: Any) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", str(value or "").lower()))
