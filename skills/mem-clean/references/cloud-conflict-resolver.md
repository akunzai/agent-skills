# Cloud Sync Conflict Resolution

This reference defines how to detect, analyze, and safely resolve cloud synchronization conflicts inside memory directories.

## 1. Conflict File Patterns

Cloud sync engines (e.g., Google Drive, iCloud, Syncthing) create duplicate conflict copies when files are edited concurrently:
- `MEMORY (Conflict).md` or `AGENTS (Conflict).md` / `CLAUDE (Conflict).md`
- `MEMORY (John's conflicted copy).md`
- `memories/2026-06-02 (conflicted copy).md` (under global `~/.agents/`)

## 2. Interactive Resolution Workflow

1. **Scan**: Look for filenames matching `*Conflict*` or `*conflicted*` inside the `~/.agents/` directory.
2. **Extract Diff**: Use `diff -u` or similar line-by-line comparison tools to identify unique entries in both files.
3. **Draft Merge Plan**: Consolidate the entries. Ensure that the latest, correct guidelines are preserved while keeping redundant entries discarded.
4. **Confirm**: Present the merged result and the deletion list to the user:
   > *"I found a sync conflict in MEMORY.md. I've drafted a merged file combining the unique entries. Would you like me to commit the merge and clean up the conflict copy?"* (or `AGENTS.md` / `CLAUDE.md`)
5. **Clean up**: Delete the conflict copy only after the user approves and the merged data has been safely written to the primary file.
