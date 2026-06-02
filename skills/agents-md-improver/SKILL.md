---
name: agents-md-improver
description: Create, audit, and improve AGENTS.md files in repositories to provide persistent context for agentic assistants. Use when the user asks to create, check, audit, update, improve, or maintain AGENTS.md, or mentions project memory optimization. Includes optional Claude Code compatibility via CLAUDE.md symbolic linking.
---

# AGENTS.md Improver

Audit, evaluate, create, and maintain AGENTS.md files across a repository to optimize project memory and context for AI assistants.

## Quick start

Run this flow to check or create AGENTS.md:
1. Scan for existing `AGENTS.md` and `CLAUDE.md` files, and check if `CLAUDE.md` is already a symbolic link pointing to `AGENTS.md`.
2. Ask the user (via interactive prompts or user questions) if they want to maintain Claude Code compatibility. **If `CLAUDE.md` is already a symbolic link pointing to `AGENTS.md`, skip this step and automatically proceed under the assumption that compatibility is desired.**
3. Choose the target `AGENTS.md` explicitly before editing.
4. Generate or improve `AGENTS.md` with build/test/run commands, code styles, and workflows.
5. If Claude compatibility is active or selected, establish/verify the symbolic link from `CLAUDE.md` to `AGENTS.md` and explain it in `AGENTS.md`.

## Workflows

### 1. Discovery & Quality Assessment
Check for file locations:
```bash
find . -name "AGENTS.md" -o -name "CLAUDE.md" -o -name ".claude.md" 2>/dev/null | head -50
```
Evaluate existing files using [references/quality-criteria.md](references/quality-criteria.md) rubrics. Output a Quality Report before editing.

Choose the target `AGENTS.md` explicitly:
- If exactly one `AGENTS.md` exists, use it.
- If multiple files exist, prefer the nearest `AGENTS.md` that governs the user's requested path or current working directory; otherwise ask before editing.
- If none exists, create the root `AGENTS.md` unless the user requested a narrower package/module path.

### 2. Interactive Compatibility Check
Before writing:
- **Check if `CLAUDE.md` is already a symbolic link to `AGENTS.md`** (e.g., using `ls -la CLAUDE.md` or checking file properties).
- **If already a symbolic link**: Skip the confirmation prompt entirely and automatically proceed under the assumption that compatibility is desired.
- **If `CLAUDE.md` already exists and is not the intended symlink**: Do not replace it blindly. Read it, summarize any unique instructions, propose how to migrate them into `AGENTS.md`, and ask for explicit approval before moving or replacing the file.
- **Otherwise**: Prompt the user:
  "Do you want to maintain Claude Code compatibility? (This will symlink CLAUDE.md to AGENTS.md and add an explanation block)"

### 3. Creation & Updates
- Build/update `AGENTS.md` following templates in [references/templates.md](references/templates.md).
- If compatibility is active or selected:
  - Create the symlink only when `CLAUDE.md` is absent or already the intended symlink.
  - If a regular `CLAUDE.md` exists, preserve its contents until the user approves migration and replacement.
  - Add the explanation block to `AGENTS.md`.
  - Add `CLAUDE.md` overrides (if any) to `AGENTS.md` or as separate imports.

### 4. Knowledge Writeback (on problem-solving)
When solving a problem reveals non-obvious knowledge (e.g. a gotcha, hidden config, env var quirk,
non-intuitive framework behavior), the agent MUST:
1. **Extract reusable insight**: Distill the raw finding into a concise, durable rule (not a bug-fix transcript).
2. **Propose the writeback**: Present the candidate snippet to the user and ask:
   > "This insight may be worth preserving. Shall I add it to `AGENTS.md`?"
3. **Write on approval only**: Update the most relevant `AGENTS.md` only after explicit user confirmation.
4. **Apply quality filters** before writing (see [references/quality-criteria.md](references/quality-criteria.md)):
   - Must be non-derivable from the codebase alone.
   - Must not be a drifting metric or overly generic rule.
   - Must be concise (prefer one bullet point).

## Advanced features

For quality assessment rubrics, detailed grading criteria, and red flags, see [references/quality-criteria.md](references/quality-criteria.md).
For complete AGENTS.md starter templates and imports guide, see [references/templates.md](references/templates.md).
For step-by-step mock execution cases and interactive prompts, see [references/examples.md](references/examples.md).
