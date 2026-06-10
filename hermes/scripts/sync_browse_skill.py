#!/usr/bin/env python3
"""Install a browse.sh skill into Hermes' local skill directory.

Hermes' native ``hermes skills install browse-sh/...`` source can lag the
browse.sh catalog. The browse CLI can still discover skills reliably, and the
catalog exposes enough metadata to install the skill directly into
``~/.hermes/skills`` where Hermes can load it.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

BROWSE_API = "https://browse.sh/api/skills"
FRONTMATTER_RE = re.compile(r"^---\s*\n(?P<body>.*?)\n---\s*\n", re.DOTALL)
NAME_RE = re.compile(r"^name:\s*['\"]?(?P<name>[A-Za-z0-9_-]+)['\"]?\s*$", re.MULTILINE)
TOKEN_RE = re.compile(r"[a-z0-9]+")
DOMAIN_RE = re.compile(r"\b(?:[a-z0-9-]+\.)+[a-z]{2,}\b", re.IGNORECASE)
STOPWORDS = {
    "a",
    "about",
    "and",
    "any",
    "are",
    "can",
    "could",
    "for",
    "from",
    "have",
    "into",
    "list",
    "me",
    "my",
    "next",
    "of",
    "on",
    "please",
    "the",
    "this",
    "to",
    "you",
}
ACTION_TERMS = {
    "book",
    "browse",
    "buy",
    "check",
    "cheap",
    "cheapest",
    "compare",
    "find",
    "get",
    "locate",
    "order",
    "price",
    "prices",
    "purchase",
    "rent",
    "reserve",
    "search",
}
QUERY_TERMS_TO_DROP = STOPWORDS | ACTION_TERMS | {"summarize", "summary"}
TRACKING_TERMS = {"status", "track", "tracking"}
SEARCHING_TERMS = {"book", "booking", "cheap", "cheapest", "compare", "itinerary", "price", "prices", "search"}


def _json_response(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True))


def _slug_safe(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9_-]+", "-", value)
    value = re.sub(r"-+", "-", value).strip("-")
    return value or "browse-skill"


def _fetch_json(url: str, timeout: float = 30.0) -> dict[str, Any]:
    req = urllib.request.Request(url, headers={"User-Agent": "doit-browse-skill-sync/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return json.loads(res.read().decode("utf-8"))


def _fetch_text(url: str, timeout: float = 30.0) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "doit-browse-skill-sync/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return res.read().decode("utf-8")


def _run_browse_find(query: str, timeout: float) -> list[dict[str, Any]]:
    try:
        proc = subprocess.run(
            ["browse", "skills", "find", query],
            check=True,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"browse skills find failed: {exc}") from exc
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("browse skills find did not return JSON") from exc
    skills = payload.get("skills")
    return skills if isinstance(skills, list) else []


def _tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text.lower())


def _singularize(token: str) -> str:
    if len(token) > 4 and token.endswith("ies"):
        return f"{token[:-3]}y"
    if len(token) > 3 and token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def _pluralize(token: str) -> str:
    if token.endswith("y") and len(token) > 2:
        return f"{token[:-1]}ies"
    if token.endswith("s"):
        return token
    return f"{token}s"


def _meaningful_query_tokens(query: str) -> list[str]:
    return [
        token
        for token in _tokens(query)
        if len(token) >= 3 and token not in QUERY_TERMS_TO_DROP
    ]


def _query_candidates(query: str) -> list[str]:
    candidates: list[str] = []

    def add(value: str) -> None:
        value = value.strip()
        if value and value not in candidates:
            candidates.append(value)

    add(query)
    for domain in DOMAIN_RE.findall(query.lower()):
        add(domain)
    tokens = _meaningful_query_tokens(query)
    # Prefer phrases over isolated words so "rental car" reaches browse.sh
    # before "rental". Pluralizing the final token handles flight/flights and
    # car/cars without maintaining a domain taxonomy.
    for size in (3, 2):
        for idx in range(0, max(len(tokens) - size + 1, 0)):
            phrase_tokens = tokens[idx: idx + size]
            add(" ".join(phrase_tokens))
            add(" ".join([*phrase_tokens[:-1], _pluralize(phrase_tokens[-1])]))
    for token in tokens:
        add(token)
        add(_pluralize(token))
    # Keep worst-case CLI calls bounded for broad prompts.
    return candidates[:24]


def _skill_terms(skill: dict[str, Any]) -> set[str]:
    values: list[str] = []
    for key in ("name", "title", "description", "category", "hostname", "slug"):
        value = skill.get(key)
        if isinstance(value, str):
            values.append(value)
    tags = skill.get("tags")
    if isinstance(tags, list):
        values.extend(str(tag) for tag in tags)
    return {_singularize(token) for token in _tokens(" ".join(values)) if len(token) >= 3}


def _query_terms(query: str) -> set[str]:
    return {_singularize(token) for token in _meaningful_query_tokens(query)}


def _has_browser_intent(query: str) -> bool:
    lowered = query.lower()
    if DOMAIN_RE.search(lowered):
        return True
    terms = {_singularize(token) for token in _tokens(lowered)}
    return bool(terms & ACTION_TERMS)


def _skill_match_score(query: str, skill: dict[str, Any]) -> int:
    if not _has_browser_intent(query):
        return 0
    lowered = query.lower()
    hostname = str(skill.get("hostname") or "").lower()
    if hostname and hostname in lowered:
        return 50
    query_terms = _query_terms(query)
    if not query_terms:
        return 0
    skill_terms = _skill_terms(skill)
    overlap = query_terms & skill_terms
    if not overlap:
        return 0
    query_action_terms = {_singularize(token) for token in _tokens(lowered)} & ACTION_TERMS
    score = len(overlap) * 10
    if query_action_terms & {"book", "buy", "cheap", "compare", "find", "price", "purchase", "search"}:
        if skill_terms & SEARCHING_TERMS:
            score += 10
    if skill_terms & {"track", "tracking"} and not (
        ({_singularize(token) for token in _tokens(lowered)} & TRACKING_TERMS)
    ):
        score -= 20
    return max(score, 0)


def _is_confident_match(query: str, skill: dict[str, Any]) -> bool:
    return _skill_match_score(query, skill) >= 10


def _skill_from_query(query: str, timeout: float) -> dict[str, Any] | None:
    best_skill: dict[str, Any] | None = None
    best_score = 0
    seen: set[str] = set()
    for candidate in _query_candidates(query):
        skills = _run_browse_find(candidate, timeout)
        for skill in skills:
            identity = str(skill.get("slug") or skill.get("name") or skill)
            if identity in seen:
                continue
            seen.add(identity)
            score = _skill_match_score(query, skill)
            if score > best_score:
                best_score = score
                best_skill = skill
    return best_skill if best_score >= 10 else None


def _skill_from_slug(slug: str) -> dict[str, Any]:
    try:
        return _fetch_json(f"{BROWSE_API}/{slug}")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"browse.sh did not know skill slug {slug!r}") from exc


def _github_api_dir_from_source(source_url: str | None) -> str | None:
    if not source_url:
        return None
    match = re.match(
        r"https://github\.com/(?P<owner>[^/]+)/(?P<repo>[^/]+)/blob/(?P<branch>[^/]+)/(?P<path>.+/)[^/]+$",
        source_url,
    )
    if not match:
        return None
    return (
        f"https://api.github.com/repos/{match.group('owner')}/{match.group('repo')}"
        f"/contents/{match.group('path').rstrip('/')}?ref={match.group('branch')}"
    )


def _download_github_dir(api_url: str, dest: Path) -> bool:
    try:
        entries = _fetch_json(api_url)
    except Exception:
        return False
    if not isinstance(entries, list):
        return False
    wrote_any = False
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        entry_type = entry.get("type")
        name = entry.get("name")
        if not name:
            continue
        if entry_type == "file" and entry.get("download_url"):
            (dest / name).write_text(_fetch_text(entry["download_url"]))
            wrote_any = True
        elif entry_type == "dir" and entry.get("url"):
            subdir = dest / name
            subdir.mkdir(parents=True, exist_ok=True)
            wrote_any = _download_github_dir(entry["url"], subdir) or wrote_any
    return wrote_any


def _skill_md(skill: dict[str, Any]) -> str:
    if isinstance(skill.get("skillMd"), str) and skill["skillMd"].strip():
        return skill["skillMd"]
    url = skill.get("skillMdUrl")
    if isinstance(url, str) and url:
        return _fetch_text(url)
    raise RuntimeError("Skill did not include SKILL.md content or URL")


def _skill_name(skill_md: str, skill: dict[str, Any], slug: str) -> str:
    match = FRONTMATTER_RE.search(skill_md)
    if match:
        name_match = NAME_RE.search(match.group("body"))
        if name_match:
            return _slug_safe(name_match.group("name"))
    frontmatter = skill.get("frontmatter")
    if isinstance(frontmatter, dict) and isinstance(frontmatter.get("name"), str):
        return _slug_safe(frontmatter["name"])
    name = skill.get("name")
    if isinstance(name, str) and name:
        return _slug_safe(name.split("/")[-1])
    return _slug_safe(slug.split("/")[-1])


def _metadata(skill: dict[str, Any], slug: str, name: str) -> dict[str, Any]:
    return {
        "source": "browse.sh",
        "slug": slug,
        "name": name,
        "updated": skill.get("updated") or skill.get("lastUpdated") or skill.get("updatedAt"),
        "source_url": skill.get("sourceUrl"),
        "skill_md_url": skill.get("skillMdUrl"),
    }


def _same_install(dest: Path, metadata: dict[str, Any]) -> bool:
    marker = dest / ".doit-browse-skill.json"
    if not marker.exists() or not (dest / "SKILL.md").exists():
        return False
    try:
        existing = json.loads(marker.read_text())
    except json.JSONDecodeError:
        return False
    return (
        existing.get("slug") == metadata.get("slug")
        and existing.get("updated") == metadata.get("updated")
        and existing.get("skill_md_url") == metadata.get("skill_md_url")
    )


def install_skill(
    *,
    query: str | None,
    slug: str | None,
    hermes_skills_dir: Path,
    force: bool,
    timeout: float,
) -> dict[str, Any]:
    if not query and not slug:
        raise RuntimeError("Provide --query or --slug")

    skill = _skill_from_slug(slug) if slug else _skill_from_query(query or "", timeout)
    if not skill:
        return {"installed": False, "reason": "no_confident_match", "query": query, "slug": slug}

    resolved_slug = str(slug or skill.get("slug") or "")
    if not resolved_slug and skill.get("domain") and skill.get("id"):
        resolved_slug = f"{skill['domain']}/{skill['id']}"
    if not resolved_slug:
        raise RuntimeError("Resolved skill had no slug")

    # Enrich results from `browse skills find`, which have metadata but not full markdown.
    detailed = skill
    if not detailed.get("skillMd") and not detailed.get("skillMdUrl"):
        with_context = _skill_from_slug(resolved_slug)
        with_context.update({k: v for k, v in skill.items() if k not in with_context or with_context[k] in (None, "")})
        detailed = with_context

    skill_md = _skill_md(detailed)
    name = _skill_name(skill_md, detailed, resolved_slug)
    metadata = _metadata(detailed, resolved_slug, name)
    dest = hermes_skills_dir.expanduser() / name

    if dest.exists() and not force and _same_install(dest, metadata):
        return {"installed": False, "reason": "already_current", "name": name, "slug": resolved_slug}

    hermes_skills_dir.expanduser().mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{name}.", dir=str(hermes_skills_dir.expanduser())) as tmp_name:
        tmp = Path(tmp_name)
        source_url = detailed.get("sourceUrl") if isinstance(detailed.get("sourceUrl"), str) else skill.get("sourceUrl")
        github_dir = _github_api_dir_from_source(source_url)
        wrote_any = _download_github_dir(github_dir, tmp) if github_dir else False
        if not wrote_any:
            (tmp / "SKILL.md").write_text(skill_md)
        elif not (tmp / "SKILL.md").exists():
            (tmp / "SKILL.md").write_text(skill_md)
        (tmp / ".doit-browse-skill.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
        if dest.exists():
            shutil.rmtree(dest)
        tmp.rename(dest)

    return {"installed": True, "name": name, "slug": resolved_slug, "path": str(dest)}


def _restart_hermes_units() -> None:
    units = subprocess.run(
        ["systemctl", "list-units", "--type=service", "--all", "--no-legend"],
        check=True,
        text=True,
        capture_output=True,
    )
    names = [
        line.split()[0]
        for line in units.stdout.splitlines()
        if line.split() and line.split()[0].startswith("hermes-")
    ]
    if names:
        subprocess.run(["sudo", "systemctl", "restart", *names], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--query", help="Natural-language query to find a browse.sh skill.")
    group.add_argument("--slug", help="Exact browse.sh slug, e.g. google.com/search-flights-ts4g1f.")
    parser.add_argument(
        "--hermes-skills-dir",
        type=Path,
        default=Path.home() / ".hermes" / "skills",
        help="Hermes local skills directory.",
    )
    parser.add_argument("--timeout", type=float, default=30.0, help="Timeout for browse discovery.")
    parser.add_argument("--force", action="store_true", help="Overwrite an existing install.")
    parser.add_argument("--restart", action="store_true", help="Restart hermes-* systemd units after install.")
    args = parser.parse_args()

    try:
        result = install_skill(
            query=args.query,
            slug=args.slug,
            hermes_skills_dir=args.hermes_skills_dir,
            force=args.force,
            timeout=args.timeout,
        )
        if args.restart and result.get("installed"):
            _restart_hermes_units()
        _json_response(result)
    except Exception as exc:
        _json_response({"installed": False, "error": str(exc)})
        sys.exit(1)


if __name__ == "__main__":
    main()
