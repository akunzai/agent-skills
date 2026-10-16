# Project names identify shared project memories

Project memories are synchronized across macOS and Windows, where the same
project has different local paths. Use the project root directory name as the
memory identity, removing the local-path hash suffix so copies with the same
name share a Project Memory Space. This deliberately trades automatic isolation
of unrelated same-name projects for a simpler, portable identity; users who need
isolation give their project directories distinct names.

Preserve the directory name exactly, including case, spaces, and non-ASCII
characters; copies intended to share memories must use the same spelling.
Keep the existing project-root resolution: linked Git worktrees share the main
repository's memory, Git subdirectories resolve to the repository root, and a
non-Git directory identifies itself. Only the hash suffix is removed.

Agents offer a one-time migration of all hash-suffixed project directories.
The user confirms the complete source-to-destination plan, including backup
and removal of the old directories. Preserve attachments and nested structure;
verify both the recovery backup and destinations before removing the exact
confirmed sources. Backups remain outside the active project directory tree.
After verification and cleanup, a store-wide completion marker syncs across
machines and disables future legacy scans and prompts. This avoids repeated
checks but requires updating all agents before migration: later writes by old
agents need an explicitly requested migration. The resolver resolves only the
new path without moving, merging, deleting, or falling back automatically.
When old directories contain notes with the same filename, preserve both under
distinct filenames for manual review instead of overwriting either one.
