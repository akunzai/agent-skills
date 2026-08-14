---
name: agents-md
description: >-
  AGENTS.md: create, audit, or maintain the file; keep Claude Code CLAUDE.md
  symlink compatibility. Use when the user mentions AGENTS.md, CLAUDE.md,
  project memory, instruction budget, or progressive disclosure of agent
  instructions.
---

# AGENTS.md

https://agents.md/ is the format baseline: plain Markdown, no required fields.
Nested files are optional. The closest `AGENTS.md` to the edited files has
precedence; some tools also load ancestor files, so keep root facts repo-wide
and package facts in the package file. Repo evidence and the user's explicit
instructions govern the content.

## Instruction budget

Every line loads on every turn. Keep the file an index, not a manual. A line
earns its place when it is relevant to every single task, or when looking it
up in the environment is expensive.

Root file holds:

- One-sentence project description (what this repo is, and why work happens here)
- Package manager, when it is not the ecosystem default
- Build/test/typecheck commands that are non-standard or costly to discover
- Context pointers to domain docs, schemas, gold-standard tests, and skills
- Self-Reflection so later agents write discoveries back

Everything else lives behind a pointer: a domain doc, a nested `AGENTS.md`, or
a skill. Hand-author from repo evidence; skip init-script dumps.

**Progressive Disclosure**: keep `AGENTS.md` lean (< 100 lines). Offload SOPs
and single-domain rules to `@path` or a skill.

**Trust Model Judgment**: keep project-specific, non-derivable constraints.
Generic style and hygiene already live in the model.

**Single Source of Truth**: `package.json`, configs, and the tree are the live
source. Restate a fact here only when the lookup is expensive (a cache). Point
rather than copy.

**Rich References**: point at schemas and gold-standard tests instead of prose
specs. Describe capabilities and stable domain terms; skip file-by-file maps
(paths drift).

Write pointers in light-touch language: a conversational reference, not ALL-CAPS
or "ALWAYS".

## Workflows

### 1. Discovery & Quality Assessment

```bash
find . -name "AGENTS.md" -o -name "CLAUDE.md" -o -name ".claude.md" 2>/dev/null | head -50
```

Choose the target `AGENTS.md` explicitly:

- If exactly one `AGENTS.md` exists, use it.
- If multiple files exist, prefer the nearest `AGENTS.md` that governs the
  user's requested path or current working directory; otherwise ask before
  editing.
- In nested repositories or monorepos, the closest `AGENTS.md` to the edited
  files has precedence for that subtree (nested files are optional).
- If none exists, create the root `AGENTS.md` unless the user requested a
  narrower package/module path.

Done when the target path is named.

Then grade that file with [references/quality-criteria.md](references/quality-criteria.md):
Micromanagement Audit, Bloat, contradictions, every-task placement, and stale
caches. Emit a Quality Report before any edit.

Done when the report is in the conversation and no edit has started.

### 2. Interactive Compatibility Check

Before writing:

- **Check if `CLAUDE.md` is already a symbolic link to `AGENTS.md`** (e.g., using
  `ls -la CLAUDE.md` or checking file properties).
- **If already a symbolic link**: Skip the confirmation prompt entirely and
  automatically proceed under the assumption that compatibility is desired.
- **If `CLAUDE.md` already exists and is not the intended symlink**: Read it,
  summarize any unique instructions, propose how to migrate them into
  `AGENTS.md`, and ask for explicit approval before moving or replacing the file.
- **Otherwise**: Prompt the user:
  "Do you want to maintain Claude Code compatibility? (This will symlink CLAUDE.md to AGENTS.md and add an explanation block)"

Done when the next action is known and a regular `CLAUDE.md` is still intact
unless the user approved replacement.

### 3. Creation & Updates

Load [references/templates.md](references/templates.md) for this branch.

- Build or slim the file as an index: one-sentence description, non-default
  package manager, non-standard commands, pointers.
- Apply **Progressive Disclosure**: offload multi-step SOPs and single-domain
  rules.
- On a bloated existing file, group leftovers by domain, ask which of any
  contradictory pair to keep, and flag no-ops / vague / obvious lines for
  deletion.
- If compatibility is active or selected:
  - Create the symlink only when `CLAUDE.md` is absent or already the intended
    symlink.
  - If a regular `CLAUDE.md` exists, preserve its contents until the user
    approves migration and replacement.
  - Add the concise explanation block (`CLAUDE.md is a symbolic link...`) to
    `AGENTS.md`.
  - Add `CLAUDE.md` overrides (if any) to `AGENTS.md` or as separate imports.
- Include the `Self-Reflection` section rules in `AGENTS.md` so all future
  agents follow them.

Done when every remaining root line passes the every-task test or is a pointer.

### 4. Self-Reflection (on problem-solving)

When solving a problem reveals non-obvious knowledge (e.g., a gotcha, hidden
config, env var quirk), the agent MUST:

1. **Candidate**: Distill into a concise, non-derivable rule (≤ 2 bullets,
   context-tagged, no drifting metrics or micromanagement — gates in
   [references/quality-criteria.md](references/quality-criteria.md)).
2. **Promote**: Present the candidate to the user for explicit confirmation,
   then write it to a dedicated file — never inline in `AGENTS.md` itself:
   - If an existing topic doc already covers the subject, merge into it.
   - Otherwise create `docs/<topic>.md` (kebab-case, named from the content).
   - If the insight doesn't fit any topic, fall back to `docs/lessons-learned.md`.
   - Add or update a single `@path` reference line per file under Pointers —
     never a standalone "Lessons Learned" heading.
3. **Prune**: Periodically review the referenced files and drop entries once
   stale (library/version upgraded past the tagged context, now enforced by a
   linter/type/test, duplicated across files, or a one-off debugging
   transcript). Propose deletions to the user rather than applying a fixed
   entry-count cap.
4. **Legacy migration**: If `AGENTS.md` still carries an old-format
   `Knowledge Writeback` (or similarly named) rule bullet, or an inline
   `## Lessons Learned` section, propose updating the rule bullet to this
   Self-Reflection wording and migrating any inline entries out to the
   appropriate topic/fallback file(s), replacing the section with reference
   line(s) — pending user confirmation.

Done when a candidate is in front of the user, or nothing met the gates.

## References

- Audit rubric: [references/quality-criteria.md](references/quality-criteria.md)
- Starter templates: [references/templates.md](references/templates.md)
- Mock runs: [references/examples.md](references/examples.md)
