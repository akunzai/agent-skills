# Git Worktree Memories Synchronization

This reference explains how to use the automated sync script to seamlessly synchronize daily logs (`.memories/`) across multiple machines without polluting the main branch or messing up your editor's workspace.

## 1. Dynamic Discovery Algorithm (For AI Agents)

Since this skill can be loaded in different scopes, **DO NOT hardcode the script path**. Determine the absolute path dynamically:

1. **User Scope Check**: If loaded globally, the script is at `~/.agents/skills/memory/scripts/sync-memory.sh`.
2. **Project Scope Check**: If loaded locally, the script is at `<repo>/skills/memory/scripts/sync-memory.sh`.
3. **Fallback Discovery**: If both checks fail, use workspace file search tools to search for `sync-memory.sh` in the workspace or `~/.agents/` directory.

## 2. Core Mechanics

Instead of switching your active working branch (which triggers editor resets and file reloading), the automated script uses **Git Worktrees** in the background:
- It creates a dedicated, isolated branch named `project-memories` with no parent history (an orphan branch).
- It checks out this branch into a hidden workspace folder `.git/memories-worktree/`.
- **Anti-Loss Sync Rule (Incremental)**: When syncing, the script **first pulls** the latest remote commits, and then performs an **incremental copy** (leaving older daily logs in the worktree untouched) before push, ensuring zero daily note loss.

## 3. Command Line Operations

You can run the script manually depending on the scope:

### Upload & Push Local Notes
```bash
# Example: Executing globally
~/.agents/skills/memory/scripts/sync-memory.sh push
```

### Download & Pull Remote Notes
```bash
# Example: Executing globally
~/.agents/skills/memory/scripts/sync-memory.sh pull
```

## 4. Automation Guidelines for AI Agents

Whenever you start a session or detect active git operations in a cross-device project environment:
- Proactively offer to execute `sync-memory.sh pull` (using the discovered path) to pull down notes recorded on other devices.
- Before ending a session or after promoting candidate memories, execute `sync-memory.sh push` to persist today's notes for other workspaces.
