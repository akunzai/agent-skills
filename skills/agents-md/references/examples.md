# Examples & Shell Patterns for `agents-md`

This file documents example flows and mock transcripts for executing the `agents-md` skill.

---

## Example 1: Creating a brand new AGENTS.md with Claude compatibility

### Scenario
The codebase does not contain an `AGENTS.md` or `CLAUDE.md`. The agent discovers this and guides the user.

### Flow

1. **Discovery & Assessment**
   The agent runs the discovery command:
   ```bash
   find . -name "AGENTS.md" -o -name "CLAUDE.md" -o -name ".claude.md" 2>/dev/null | head -50
   ```
   No files are found. The agent reports:
   > **AGENTS.md Quality Report**: Score: F (No AGENTS.md file found).

2. **Compatibility Query**
   The agent prompts the user to determine if they want to maintain Claude Code compatibility:
   
   > **Interactive Prompt**:
   > "Would you like to maintain compatibility with Claude Code by symlinking CLAUDE.md to AGENTS.md?"
   > - **Option 1 (Recommended)**: Yes, create CLAUDE.md as a symlink and explain it in AGENTS.md
   > - **Option 2**: No, only create AGENTS.md

3. **Symlink and File Setup**
   If the user selects "Yes...", the agent runs:
   ```bash
   ln -s AGENTS.md CLAUDE.md
   ```
   And writes `AGENTS.md` from repo evidence — one-sentence description, non-default package manager, non-standard commands, pointers — plus the compatibility explanation block:

   ```markdown
   # Project Developer Guidelines

   This is a <one-sentence project description>.

   ## Commands
   - Test one file: npm test -- <filepath>

   ## Claude Code Compatibility

   `CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md` directly.
   ```

---

## Example 2: Auditing and Slimming Down an Over-Constrained AGENTS.md

### Scenario
An `AGENTS.md` exists but is over-constrained with defensive micromanagement ("always write clean code", "never use null"), bloated prose tutorials, and unpruned stale gotchas.

### Flow

1. **Discovery & Assessment**
   The agent finds `./AGENTS.md` and audits it against [quality-criteria.md](quality-criteria.md).
   
2. **Quality Assessment Report**
   The agent outputs:
   > ### AGENTS.md Quality Report
   > **Current Score**: C (60/100) - Over-Constrained & Monolithic SOP Bloat
   > **Gaps & Red Flags Identified**:
   > - **Micromanagement Audit Failure**: Contains defensive generic rules ("Write clean functions", "Add JSDoc to every line") which cause attention dilution.
   > - **Prose Specs**: Contains a 30-line text tutorial on React state instead of pointing to Rich References.
   > - **Legacy Inline Lessons Learned**: An inline `## Lessons Learned` section (old writeback format) holds 8 entries — several stale and missing context tags — that should be promoted to dedicated Self-Reflection reference files instead.
   > - **SOP Bloat**: Includes a 12-step DB migration script directly in root `AGENTS.md`.
   > - **Instruction budget**: Language-specific rules and a file-by-file map fail the every-task test.

3. **Apply Improvements (Progressive Disclosure & Context Offloading)**
   The agent rewrites `AGENTS.md` to function as an index (< 100 lines):
   - Asks which of any contradictory pair to keep, then deletes no-ops / vague / obvious lines.
   - Removes generic micromanagement (Trust Model Judgment).
   - Replaces prose specs and path maps with Rich References and capabilities.
   - Offloads DB Migration SOP to `@docs/db-migration.md`.
   - Migrates the inline `Lessons Learned` entries out per Self-Reflection: merges each into an existing topic doc where one covers the subject, otherwise creates `docs/<topic>.md` (or `docs/lessons-learned.md` as fallback), drops stale/duplicate entries, and replaces the section with `@path` reference line(s) under Pointers.

---

## Example 3: Auditing an Existing AGENTS.md where CLAUDE.md is already a symlink

### Scenario
An `AGENTS.md` exists and `CLAUDE.md` is already a symbolic link pointing to `AGENTS.md`.

### Flow

1. **Discovery & Symlink Verification**
   The agent scans the workspace root and finds `./CLAUDE.md` is already a symbolic link to `./AGENTS.md` (e.g., using `ls -la` or checking file properties).
   
2. **Quality Assessment Report**
   The agent evaluates the file and outputs the Quality Report.

3. **No Prompt Confirmation**
   The agent skips the interactive query entirely since compatibility is already active.

4. **Apply Improvements**
   The agent updates `AGENTS.md` directly while preserving or standardizing the Claude Code Compatibility section.

---

## Example 4: Existing CLAUDE.md is not a symlink

### Scenario
A repository has `AGENTS.md` and a regular `CLAUDE.md` file with separate instructions.

### Flow

1. **Discovery & Safety Check**
   The agent detects that `CLAUDE.md` exists and is not the intended symlink to `AGENTS.md`.

2. **Preserve Before Replacing**
   The agent reads `CLAUDE.md`, compares it with `AGENTS.md`, and summarizes unique instructions that would be lost if the file were replaced.

3. **Explicit Migration Proposal**
   The agent asks the user whether to migrate the unique instructions into `AGENTS.md` and replace `CLAUDE.md` with a symlink.

4. **Apply Only After Approval**
   After approval, the agent updates `AGENTS.md`, moves or removes the old `CLAUDE.md` according to the agreed plan, and creates the symlink with:
   ```bash
   ln -s AGENTS.md CLAUDE.md
   ```

---

## Example 5: Refactor a ball-of-mud `AGENTS.md`

### Scenario
A large root file mixes TypeScript style, deploy SOP, testing, and two contradictory package-manager lines.

### Flow

1. **Find contradictions** — surface both package-manager lines and ask which to keep.
2. **Extract essentials** — one-sentence project description, non-default package manager, non-standard commands, every-task facts.
3. **Group the rest** — TypeScript → `docs/TYPESCRIPT.md`, testing → `docs/TESTING.md`, deploy SOP → `docs/deploy.md`.
4. **Rewrite the root** as a light-touch index with markdown links / `@path` pointers.
5. **Flag for deletion** — generic hygiene, vague lines, and any init-script dump.

---

## Example 6: Monorepo root vs package

### Scenario
A workspace has a root `AGENTS.md` and `packages/api/AGENTS.md`.

### Flow

1. Discovery lists both files. The agent names the target from the user's path.
2. Root keeps repo purpose, workspace tool, and a pointer to package files.
3. `packages/api/AGENTS.md` keeps that package's one-sentence description, stack, and domain pointers.
4. Neither file repeats the other. The closest file still wins for files under `packages/api`.
