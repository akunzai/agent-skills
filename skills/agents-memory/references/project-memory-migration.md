# Migrate project memory directories

Project memories now use `projects/<project-name>/` instead of
`projects/<project-name>-<path-hash>/`. The resolver does not read, move, or
merge old directories. Note filenames and global memories are unchanged.

## One-time migration of all projects

Before project memory use, check only whether
`~/.agents/memories/.project-name-migration-v1` exists. If it does, use the new
paths directly: skip legacy directory scans, comparisons, and migration prompts.
This store-wide completion marker syncs with Google Drive across machines.

If the marker is absent, inventory all directories directly under
`~/.agents/memories/projects/`, not just the current project. A name ending in
`-` and six lowercase hexadecimal characters is a legacy candidate; remove
only that final suffix to propose its destination. Preserve the rest of the
name literally, including spaces and glob characters. Treat matches as
candidates, not proof: a new project's name might legitimately have this form.
Resolve ambiguous mappings, including a destination that is also a source,
with the user before copying.

Present one migration plan covering every candidate: source-to-destination
mappings, note and attachment counts, nested directories, and filename
conflicts, without quoting note contents. Include hidden files and empty
directories; resolve nested symlinks explicitly before copying. Apply the
skill's security rules when inspecting or describing notes. Ask the user to
confirm the complete mappings and approve backup, copying, verification, and
removal of the old directories as one batch. Wait before creating destinations
or copying notes. If declined, leave the old directories
and marker untouched and continue the requested task at the new location;
explain that old notes remain unmigrated. If deferred, wait before dependent
memory work.

After approval, perform the copy steps below for all confirmed sources.
Preserve both notes on a filename conflict using an unused destination name.
Keep every source until all copies and the recovery backup verify against the
complete source contents and directory structure. Recheck sources immediately
before cleanup; if any changed, stop and preserve them. Remove only the
confirmed old directories covered by that verified backup, leaving backups
outside `projects/`. The upfront approval includes this cleanup; if the
approved plan covered copying alone, obtain cleanup approval first.
On interruption or failure, leave the marker absent and report unfinished
sources; a retry compares contents, including renamed copies, to avoid copying
notes already preserved. Retain the verified recovery backup after cleanup.

Create the completion marker only after the whole inventory is resolved and
every file is verified at its confirmed destination and all confirmed old
directories have been removed. If the initial
inventory contains no candidates, create the marker directly. The marker
records completion for the entire memory store, never for one project:

```bash
mkdir -p "$HOME/.agents/memories"
touch "$HOME/.agents/memories/.project-name-migration-v1"
```

Before starting the batch, update agents on all machines and let Drive finish
syncing. Resume memory writes only after the copied notes and marker sync.
Older agents writing to legacy directories after completion require an explicit
new migration request; the completion marker deliberately disables detection.

## Copy steps

1. Stop memory writes on all machines and let Google Drive finish syncing.
   Back up the project memory directories and verify their complete contents
   and structure before copying.
2. Identify the old directories belonging to the same project. Do not infer
   project identity from the name prefix alone: unrelated same-name projects
   may need distinct project directory names first.
3. Copy all files and nested directories into the name-only directory. Run these
   commands in Bash (including Git Bash on Windows), replacing the example
   project name and hash with your actual directory names:

   ```bash
   old="$HOME/.agents/memories/projects/demo-a1b2c3"
   new="$HOME/.agents/memories/projects/demo"
   mkdir -p "$new"
   cp -ipR "$old/." "$new/"
   ```

   If prompted to overwrite, answer `n`. Keep the incoming note under a new,
   distinct topic filename for manual review, for example:

   ```bash
   cp -i "$old/2026-10-17-build.md" "$new/2026-10-17-build-from-windows.md"
   ```

   Use an unused destination filename and answer `n` to any overwrite prompt.
4. Repeat for every confirmed project directory. Verify all files and directory
   structures against both the destinations and the recovery backup. Once the
   approved cleanup checks pass, remove the exact confirmed old directories;
   preserve the backup and all destination files. Create the completion marker
   only after cleanup succeeds, then let notes, cleanup, and marker sync before
   resuming writes on other machines.

Copies that should share memory must use exactly the same project directory
name, including case, spaces, and non-ASCII characters. Linked Git worktrees
continue to use their main repository's name.
