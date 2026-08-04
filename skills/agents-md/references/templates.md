# Templates & Formatting for `AGENTS.md`

This document provides starter structures, formatting rules, and progressive disclosure configurations for `AGENTS.md` files.

Reference the open AGENTS.md format at https://agents.md/. AGENTS.md is plain Markdown acting as an **Index-Driven Entrypoint**; common useful sections include project overview, build/test commands, code style, testing instructions, and security considerations. Keep root files under 100 lines. Offload multi-step SOPs to dedicated Skills or auxiliary Markdown files (*Context Offloading*).

---

## 1. Progressive Disclosure Starter Template

Use this starter template when creating a new `AGENTS.md` file. Prefer **Rich References** (pointers to type schemas and gold-standard tests) over long prose specifications.

```markdown
# [Project Name] Developer Guidelines

## Quick Commands
- Build: <command> (e.g., npm run build)
- Test All: <command> (e.g., pytest)
- Single Test: <command> <filepath> (e.g., npx vitest run src/utils.test.ts)
- Lint/Format: <command> (e.g., npx eslint .)

## Rich References & Core Schemas
- Domain Schemas: @src/types/index.ts
- API Contracts: @src/api/schema.ts
- Gold-Standard Test Spec: @tests/example.spec.ts

## Architecture Overview
- `/src`: Main application logic
  - `/src/components`: UI components
  - `/src/hooks`: Custom React hooks
- `/tests`: Automated test suites

## Code Style & Conventions
- <Language/framework conventions verified from repo files, e.g. package manifests, config files, and existing code>
- <Formatting/linting conventions backed by config or nearby code>
- <Module boundaries or file organization rules that are specific to this repository>

## Workflows & Context Offloading
- **Single-Test Run**: Always target single test files during iteration for speed.
- **Complex SOPs**: For database migration or deployment procedures, see @docs/deploy-sop.md or invoke relevant skills.

## Self-Reflection
- **Candidate**: Distill non-obvious gotchas, hidden configurations, or project patterns into concise, non-derivable rules (≤ 2 bullets, context-tagged, no drifting metrics). Propose the candidate to the user before writing anything.
- **Promote**: On confirmation, write it to a dedicated file — never inline in `AGENTS.md` itself. Merge into an existing topic doc if one covers the subject, otherwise create `docs/<topic>.md`; fall back to `docs/lessons-learned.md` for miscellaneous items. Add or update a single `@path` reference line per file under Rich References.
- **Prune**: Drop entries once stale (obsolete version, now enforced by a linter/type/test, duplicated elsewhere, or a debugging transcript) — not by a fixed entry count.
```

Don't add a Rich Reference line for a lessons-learned or topic file in a brand-new `AGENTS.md` — there's no history to document yet. Add it later, per Section 4 below, once the first candidate is confirmed and promoted.

---

## 2. Claude Code Compatibility Section

If the user requests compatibility with Claude Code, append this concise section to the bottom of `AGENTS.md`:

```markdown
## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md` directly.
```

Create the symbolic link in the repository root only when `CLAUDE.md` is absent or already points to `AGENTS.md`:
```bash
ln -s AGENTS.md CLAUDE.md
```

If `CLAUDE.md` already exists and is not the intended symlink, do not replace it blindly. Read it, summarize any unique instructions, propose a migration into `AGENTS.md`, and ask for explicit approval before moving or replacing the file.

---

## 3. Advanced Imports & Progressive Disclosure (Lazy Loading)

To maintain modularity and avoid overloading `AGENTS.md` with every detail, use imports for auxiliary guidelines (supported by agent systems including Claude Code):

```markdown
# Auxiliary Instructions (Loaded On-Demand)
- Deployment SOP: @docs/deploy.md
- Database Migration: @docs/db-migration.md
- Personal Overrides: @~/.claude/my-project-instructions.md
```
- `@path/to/file` tells the agent to load the referenced file on-demand (*Lazy Loading*).
- Keep root `AGENTS.md` lean (< 100 lines) by offloading deep specs to sub-documents.

---

## 4. Self-Reflection Reference Files (Optional)

Create these files only once the project has accumulated non-obvious institutional knowledge discovered through problem-solving (see Section 4 of `SKILL.md`). Always include context tags (e.g. library version or OS scope).

Write the entry into the relevant file — merge into an existing topic doc if one covers the subject, otherwise create `docs/<topic>.md`; use `docs/lessons-learned.md` as the fallback for miscellaneous items:

```markdown
- [Node 20+] Running `npm test` without `--forceExit` hangs in CI due to an unclosed DB connection in `src/db/client.ts`.
```

Then reference the file from `AGENTS.md`'s Rich References section — never inline the entry in `AGENTS.md` itself:

```markdown
## Rich References & Core Schemas
- Lessons Learned: @docs/lessons-learned.md
```

> [!IMPORTANT]
> **Pruning Hygiene**: Periodically review these files and drop entries once stale — obsolete package version, now enforced by a linter/type/test, duplicated elsewhere, or a one-off debugging transcript. There is no fixed entry-count cap; prune by relevance, not size.
