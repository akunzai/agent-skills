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
- **Knowledge Writeback**: When discovering non-obvious gotchas, propose adding context-tagged rules to a `## Lessons Learned` section (see Section 4 below for format and pruning hygiene).
```

Don't include a `## Lessons Learned` section in a brand-new `AGENTS.md` — it has no history to document yet. Add it later, per Section 4 below, once real gotchas surface.

---

## 2. Claude Code Compatibility Section

If the user requests compatibility with Claude Code, append this exact section to the bottom of `AGENTS.md`:

```markdown
## Claude Code Compatibility

> [!NOTE]
> This repository maintains compatibility with Claude Code. The file `CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. 
> All commands, style guides, and workflows defined in `AGENTS.md` apply to both Antigravity (and other agentic assistants) and Claude Code.
> **DO NOT** delete the `CLAUDE.md` symbolic link or edit it independently; all guidelines must be updated directly in `AGENTS.md`.
```

Create the symbolic link in the repository root only when `CLAUDE.md` is absent or already points to `AGENTS.md`:
```bash
ln -s AGENTS.md CLAUDE.md
```

If `CLAUDE.md` already exists and is not the intended symlink, do not replace it blindly. Read it, preserve any unique instructions, propose a migration into `AGENTS.md`, and ask for explicit approval before moving or replacing the file.

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

## 4. Lessons Learned & Active Pruning Section (Optional)

Add this section to `AGENTS.md` only when the project has accumulated non-obvious institutional knowledge discovered through problem-solving. Always include context tags (e.g. library version or OS scope).

```markdown
## Lessons Learned (Actively Pruned, max 5 entries)
- [Node 20+] Running `npm test` without `--forceExit` hangs in CI due to an unclosed DB connection in `src/db/client.ts`.
```

> [!IMPORTANT]
> **Active Pruning Hygiene**: Keep this section under 5 bullet points. If it exceeds 5 entries, perform a pruning check:
> 1. Delete gotchas for obsolete package versions.
> 2. Promote durable architectural rules into Rich References (types or static linter rules).

