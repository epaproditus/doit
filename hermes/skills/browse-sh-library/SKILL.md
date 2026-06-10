---
name: browse-sh-library
description: Discover and install browse.sh catalog skills for site-specific browser automation.
---

# browse.sh Library

Use this skill when a task needs a site-specific browser workflow and no installed browse.sh skill already matches.

## Workflow

1. Check installed skills first with `skills_list`.
2. If no installed skill matches, discover catalog skills with:

   ```bash
   browse skills find "<short task or domain query>"
   ```

3. Install the best catalog match into Hermes' local skill directory with Doit's bridge:

   ```bash
   python3 /opt/doit/hermes/scripts/sync_browse_skill.py --query "<short task or domain query>"
   ```

   If you already know the exact browse.sh slug, use:

   ```bash
   python3 /opt/doit/hermes/scripts/sync_browse_skill.py --slug "domain.com/skill-id"
   ```

4. Retry `skills_list` and `skill_view` for the installed skill.
5. Follow the skill's `browse ...` CLI commands with the terminal tool. Browserbase is the remote browser backend.

Do not use `hermes skills install browse-sh/...` for browse.sh catalog skills. The Doit bridge installs browse.sh skills into `~/.hermes/skills`, which is where Hermes can load local skills.
