---
name: agents-md
description: Create, audit, and maintain AGENTS.md files in repositories to provide persistent context for agentic assistants. Use when the user mentions AGENTS.md or project memory optimization. Includes optional Claude Code compatibility via CLAUDE.md symbolic linking.
---

# AGENTS.md

Use the open AGENTS.md format reference at https://agents.md/ for baseline conventions: AGENTS.md is plain Markdown with no required fields. Nested files can scope instructions by directory but are optional (root file is sufficient). Repo evidence and explicit user instructions still govern the concrete content you write.

## Core Principles (Context Engineering)

Based on Anthropic's *"The new rules of context engineering for Claude 5 generation models"*:

1. **Progressive Disclosure (Index-Driven Entrypoint & Lazy Loading)**: Keep `AGENTS.md` lean (< 100 lines). Treat it as a high-level map rather than a manual. Offload detailed SOPs, multi-step workflows, and sub-module guidelines to separate files (`@path/to/file`) via **Lazy Loading / On-demand Loading** or dedicated Skills (*Context Offloading*).
2. **Trust Model Judgment**: Avoid defensive micromanagement or redundant negative constraints ("write clean code", "don't make syntax errors"). Rely on model reasoning for general software practices; restrict `AGENTS.md` to project-specific, non-derivable constraints.
3. **Single Source of Truth (SSOT)**: Avoid duplicating rules across system prompts, `package.json`, and `AGENTS.md`. Cross-reference rather than copy.
4. **Rich References over Text Specs**: Prefer pointers to type schemas (`@src/types/index.ts`) and gold-standard test suites (`@tests/feature.spec.ts`) over long prose descriptions.

## Workflows

### 1. Discovery & Quality Assessment
Check for file locations:
```bash
find . -name "AGENTS.md" -o -name "CLAUDE.md" -o -name ".claude.md" 2>/dev/null | head -50
```
Evaluate existing files using [references/quality-criteria.md](references/quality-criteria.md) rubrics, specifically performing a **Micromanagement Audit** and checking for **Bloat** (Slight Bloat / Monolithic SOP Bloat). Output a Quality Report before editing.

Choose the target `AGENTS.md` explicitly:
- If exactly one `AGENTS.md` exists, use it.
- If multiple files exist, prefer the nearest `AGENTS.md` that governs the user's requested path or current working directory; otherwise ask before editing.
- In nested repositories or monorepos, the closest `AGENTS.md` to the edited files has precedence for that subtree (nested files are optional).
- If none exists, create the root `AGENTS.md` unless the user requested a narrower package/module path.

### 2. Interactive Compatibility Check
Before writing:
- **Check if `CLAUDE.md` is already a symbolic link to `AGENTS.md`** (e.g., using `ls -la CLAUDE.md` or checking file properties).
- **If already a symbolic link**: Skip the confirmation prompt entirely and automatically proceed under the assumption that compatibility is desired.
- **If `CLAUDE.md` already exists and is not the intended symlink**: Do not replace it blindly. Read it, summarize any unique instructions, propose how to migrate them into `AGENTS.md`, and ask for explicit approval before moving or replacing the file.
- **Otherwise**: Prompt the user:
  "Do you want to maintain Claude Code compatibility? (This will symlink CLAUDE.md to AGENTS.md and add an explanation block)"

### 3. Creation & Updates
- Build/update `AGENTS.md` following Progressive Disclosure templates in [references/templates.md](references/templates.md).
- Apply **Progressive Disclosure** (Core Principle 1): keep `AGENTS.md` lean and offload multi-step SOPs to Skills or auxiliary files.
- If compatibility is active or selected:
  - Create the symlink only when `CLAUDE.md` is absent or already the intended symlink.
  - If a regular `CLAUDE.md` exists, preserve its contents until the user approves migration and replacement.
  - Add the concise explanation block (`CLAUDE.md is a symbolic link...`) to `AGENTS.md`.
  - Add `CLAUDE.md` overrides (if any) to `AGENTS.md` or as separate imports.
- Include the `Self-Reflection` section rules in `AGENTS.md` so all future agents follow them.

### 4. Self-Reflection (on problem-solving)
When solving a problem reveals non-obvious knowledge (e.g., a gotcha, hidden config, env var quirk), the agent MUST:
1. **Candidate**: Distill into a concise, non-derivable rule (≤ 2 bullets, context-tagged, no drifting metrics or micromanagement — see [references/quality-criteria.md](references/quality-criteria.md)).
2. **Promote**: Present the candidate to the user for explicit confirmation, then write it to a dedicated file — never inline in `AGENTS.md` itself:
   - If an existing topic doc already covers the subject, merge into it.
   - Otherwise create `docs/<topic>.md` (kebab-case, named from the content).
   - If the insight doesn't fit any topic, fall back to `docs/lessons-learned.md`.
   - Add or update a single `@path` reference line per file under `AGENTS.md`'s Rich References section — never a standalone "Lessons Learned" heading.
3. **Prune**: Periodically review the referenced files and drop entries once stale (library/version upgraded past the tagged context, now enforced by a linter/type/test, duplicated across files, or a one-off debugging transcript). Propose deletions to the user rather than applying a fixed entry-count cap.
4. **Legacy migration**: If `AGENTS.md` already contains an inline `## Lessons Learned` section from the old writeback format, propose migrating its entries out to the appropriate topic/fallback file(s) and replacing the section with reference line(s), pending user confirmation.

## Advanced features

For quality assessment rubrics, detailed grading criteria, and red flags, see [references/quality-criteria.md](references/quality-criteria.md).
For complete AGENTS.md starter templates and imports guide, see [references/templates.md](references/templates.md).
For step-by-step mock execution cases and interactive prompts, see [references/examples.md](references/examples.md).

