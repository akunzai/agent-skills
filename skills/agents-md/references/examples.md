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
   And writes `AGENTS.md` incorporating the starter template along with the compatibility explanation block:

   ```markdown
   # Project Developer Guidelines

   ## Quick Commands
   - Build: npm run build
   - Test: npm test

   ## Claude Code Compatibility

   > [!NOTE]
   > This repository maintains compatibility with Claude Code. The file `CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. 
   > All commands, style guides, and workflows defined in `AGENTS.md` apply to both Antigravity and Claude Code.
   > **DO NOT** delete the `CLAUDE.md` symbolic link or edit it independently; all guidelines must be updated directly in `AGENTS.md`.
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

3. **Apply Improvements (Progressive Disclosure & Context Offloading)**
   The agent rewrites `AGENTS.md` to function as an Index-driven Entrypoint (< 100 lines):
   - Removes all generic micromanagement rules (trusts model reasoning).
   - Replaces prose specs with Rich References (`Domain Schemas: @src/types/index.ts`).
   - Offloads DB Migration SOP to `@docs/db-migration.md` (*Context Offloading*).
   - Migrates the inline `Lessons Learned` entries out per Self-Reflection: merges each into an existing topic doc where one covers the subject, otherwise creates `docs/<topic>.md` (or `docs/lessons-learned.md` as fallback), drops stale/duplicate entries, and replaces the section with `@path` reference line(s) under Rich References.

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
