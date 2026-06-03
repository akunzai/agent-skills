# Memory Pruning Specifications

This reference provides instructions on how to safely compress, clean, and resolve conflicts in durable global preferences (`MEMORY.md`) and local project conventions (`AGENTS.md` or `CLAUDE.md`).

## 1. Pruning Objectives

- **Reduce Bloat**: Keep durable files under 100 lines so that loading memory in every session remains fast and token-efficient.
- **Single Source of Truth**: Eliminate outdated preferences, redundant wording, and retired configurations.

## 2. Interactive Pruning Workflow

Scan `MEMORY.md` (global) or `AGENTS.md` (project, fallback to `CLAUDE.md` if `AGENTS.md` is absent) for the following issues:

- **Duplicates**: Multiple bullet points declaring the exact same preference in slightly different words.
- **Obsoletes**: Outdated dependencies or setups that are no longer part of the workspace.
- **Contradictions**: Overlapping or conflicting rules. If a decision overrides an old one, write `Replaces: - [Old rule from YYYY-MM-DD]` or simply delete the old entry.

### Interactive Confirmation
Before committing any changes to `MEMORY.md` or `AGENTS.md` / `CLAUDE.md`, present the exact diff or cleanup plan to the user:
> *"I noticed an outdated configuration in AGENTS.md (or CLAUDE.md). Would you like me to replace it with the new settings?"*
