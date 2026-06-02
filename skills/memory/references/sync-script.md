# Git Worktree Memories Synchronization

This reference explains how to use the automated sync script to seamlessly synchronize daily logs (`.memories/`) across multiple machines without polluting the main branch or messing up your editor's workspace.

## 1. Introspection Discovery Rule (For AI Agents)

Since this skill can be loaded in various scopes and directories depending on the active Agent (e.g., `~/.claude/`, `~/.gemini/`, or project-scope `<repo>/`), **DO NOT hardcode or guess absolute paths**. Locate the script using **Introspection**:

1. **Check Current Path**: Inspect the absolute file URI of the active `SKILL.md` or `sync-script.md` you are currently reading (e.g., `file:///Users/akunzai/.claude/skills/memory/SKILL.md`).
2. **Resolve Relative Location**: The executable sync script is always located relatively at `scripts/sync-memory.sh` within that exact directory.
3. **Execute Dynamically**: Use this resolved absolute path to execute the script in the sandbox.

## 2. Core Mechanics

Instead of switching your active working branch (which triggers editor resets and file reloading), the automated script uses **Git Worktrees** in the background:
- It creates a dedicated, isolated branch named `project-memories` with no parent history (an orphan branch).
- It checks out this branch into a hidden workspace folder `.git/memories-worktree/`.
- **Anti-Loss Sync Rule (Incremental)**: When syncing, the script **first pulls** the latest remote commits, and then performs an **incremental copy** (leaving older daily logs in the worktree untouched) before push, ensuring zero daily note loss.

## 3. Command Line Operations

You can run the script manually depending on the resolved path:

### Upload & Push Local Notes
```bash
# Example: Executing based on resolved path
/path/to/memory/scripts/sync-memory.sh push
```

### Download & Pull Remote Notes
```bash
# Example: Executing based on resolved path
/path/to/memory/scripts/sync-memory.sh pull
```

## 4. Automation Guidelines for AI Agents

Whenever you start a session or detect active git operations in a cross-device project environment:
- Proactively offer to execute `sync-memory.sh pull` (using the introspected path) to pull down notes recorded on other devices.
- Before ending a session or after promoting candidate memories, execute `sync-memory.sh push` to persist today's notes for other workspaces.
