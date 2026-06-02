---
name: memory
description: Unified autopilot memory governance system for both project and user scopes. Automatically searches past context, captures daily notes, and proactively triggers promotion, pruning, or sync-check reviews with user confirmation. Use as the master memory manager.
---

# Unified Memory Autopilot

A unified, self-governing memory system that automatically retrieves, structures, and prunes project and user-level developer knowledge.

## Directory Structure

- **User Scope (Global Workspace)**: `~/.agents/`
  - Global durable preferences: `~/.agents/MEMORY.md` (Do NOT commit to Git).
  - Global daily logs: `~/.agents/memories/YYYY-MM-DD.md`.
- **Project Scope (Local Repository)**: `<repo>/`
  - Local durable rules & memories: `<repo>/AGENTS.md` (or `CLAUDE.md`, MUST commit to Git).
  - Local daily logs: `<repo>/.memories/YYYY-MM-DD.md` (gitignored).

## Quick start

```bash
# Search global preferences or project rules (AGENTS.md or CLAUDE.md)
grep -rn "pattern" ~/.agents/ AGENTS.md CLAUDE.md

# Log a candidate to today's daily log (include time stamp)
mkdir -p .memories
echo "- [Candidate] Preferred database is PostgreSQL. [04:05]" >> .memories/2026-06-02.md
```

## Workflows

### The Autopilot Governance Loop

Coding agents must actively run this governance cycle during sessions and checkpoints:

- [ ] **1. Active Search & Retrieve**:
  - Automatically query memory files whenever preferences or conventions are unknown.
- [ ] **2. Proactive Capture**:
  - **Read [references/security.md](references/security.md)** before writing.
  - Log verified insights to today's log (`.memories/YYYY-MM-DD.md` locally or `memories/` globally) as `[Candidate]` entries **with a daily time stamp** (e.g., `[HH:MM]`).
- [ ] **3. Proactive Promotion Review (Interactive)**:
  - **Read [references/promote.md](references/promote.md)** to inspect validation criteria.
  - Scan daily logs for `[Candidate]` facts. Propose them to the user.
  - **Strip daily time stamps** during promotion to keep durable rules stateless and clean.
- [ ] **4. Proactive Pruning Review (Interactive)**:
  - **Read [references/prune.md](references/prune.md)** to inspect cleanup objectives and Override rules.
  - Scan `MEMORY.md` or `AGENTS.md` / `CLAUDE.md` for duplicates or retired setups. Propose the exact diff changes to the user and request confirmation.
- [ ] **5. Sync Conflict Resolution (Interactive)**:
  - **Read [references/sync-check.md](references/sync-check.md)** to inspect duplicate patterns and safe diff merge flows.
  - Check `~/.agents/` or project directory for conflicted sync copies. Draft a merge solution and request confirmation before clean deletion.
