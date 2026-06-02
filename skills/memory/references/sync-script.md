# Git Worktree Memories Synchronization

This reference explains how to use the automated sync script to seamlessly synchronize daily logs (`.memories/`) across multiple machines without polluting the main branch or messing up your editor's workspace.

## 1. Core Mechanics

Instead of switching your active working branch (which triggers editor resets and file reloading), the automated script uses **Git Worktrees** in the background:
- It creates a dedicated, isolated branch named `project-memories` with no parent history (an orphan branch).
- It checks out this branch into a hidden workspace folder `.git/memories-worktree/`.
- Daily notes are backed up, pushed, pulled, and merged strictly inside this directory, maintaining a 100% clean and stateless active repo branch tree.

## 2. Command Line Operations

You can run the script manually from the repository root:

### Upload & Push Local Notes
To backup and push today's `.memories/` to the remote repository:
```bash
./skills/memory/scripts/sync.sh push
```

### Download & Pull Remote Notes
To fetch and merge remote daily notes into your local `.memories/` directory:
```bash
./skills/memory/scripts/sync.sh pull
```

## 3. Automation Guidelines for AI Agents

Whenever you start a session or detect active git operations in a cross-device project environment:
- Proactively offer to execute `./skills/memory/scripts/sync.sh pull` to pull down notes recorded on other devices.
- Before ending a session or after promoting candidate memories, execute `./skills/memory/scripts/sync.sh push` to persist today's notes for other workspaces.
