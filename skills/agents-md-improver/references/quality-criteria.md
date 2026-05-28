# Quality Criteria & Assessment Rubrics for `AGENTS.md`

This document defines the metrics and evaluation checklist used to assess and score the quality of `AGENTS.md` (and `CLAUDE.md`) files in repositories.

---

## 1. Quality Assessment Checklist

An effective instruction file provides precise, developer-level constraints that the AI cannot guess merely by browsing the codebase.

### Evaluation Criteria

| Criterion | Weight | Assessment Questions |
|---|---|---|
| **Commands & Workflows** | High | Are the exact build, test, and run commands listed? Are single-file/single-test execution methods explained? |
| **Architecture Clarity** | High | Does the file outline the core design blocks and directory mappings? Can the agent understand module relations immediately? |
| **Non-Obvious Patterns** | Medium | Are gotchas, environment variables, or custom configuration patterns documented? |
| **Conciseness** | Medium | Is the file dense, clear, and free from redundant tutorials or boilerplate explanations? |
| **Currency** | High | Does it reflect the *current* state of the codebase, libraries, and frameworks? |

---

## 2. Quality Scores

### Grade A (90-100): Highly Actionable & Current
- The file is concise (under 100 lines) and dense.
- Has exact command strings for building, testing, linting, and formatting.
- Documents single-test commands to save agent time and resources.
- Outlines directory layouts and core logic files.
- Up-to-date with current technologies used in the repository.

### Grade B (70-89): Minor Gaps
- Commands and basic patterns are well-documented.
- Missing single-file test options or minor architectural pointers.
- Slight verbosity or minor boilerplate.

### Grade C (50-69): Basic Information Only
- Contains basic build commands.
- Lacks architecture overview, styles, or linting commands.
- Outdated tech descriptions or minor stale paths.

### Grade D (30-49): Sparse & Drifted
- Missing essential run or test commands.
- Contains extremely vague instructions like "write clean code" or "make it perfect".
- Significant parts of the document do not match the current codebase.

### Grade F (0-29): Critically Flawed / Missing
- File does not exist, or is completely broken.
- Commands lead to immediate errors upon execution.

---

## 3. Red Flags & Anti-Patterns (To Be Eliminated)

When auditing `AGENTS.md`, look for and immediately eliminate these elements:

*   **Derivable State / Drifting Metrics**: Do not hardcode metrics that constantly change, such as:
    - `"The codebase has 25 unresolved issues"`
    - `"Current test coverage is 85%"`
    These drift instantly and lead to stale instructions.
*   **Overly Generic Rules**: Avoid boilerplate statements like:
    - `"Always write comments."`
    - `"Do not introduce syntax errors."`
    - `"Use clean functions."`
    AI agents already know these by default; putting them in `AGENTS.md` wastes token space and dilutes critical instructions.
*   **Stale File Paths**: Documenting file-by-file structures. If files are renamed, the document drifts. Link to high-level folders instead.
*   **Verbose Explanations**: Long prose describing concepts (e.g. explaining how React state works). Focus on *constraints* and *rules*, not tutorials.

---

## 4. Knowledge Writeback Criteria

When an agent proposes writing back a newly discovered insight, evaluate it against these gates:

### ✅ Write-back eligible (must meet ALL)
| Gate | Description |
|---|---|
| **Non-derivable** | Cannot be inferred by reading source code or docs alone |
| **Durable** | Will remain valid across multiple sessions / changes |
| **Actionable** | Constrains or guides a concrete agent decision |
| **Concise** | Fits in ≤ 2 bullet points |

### ❌ Do NOT write back
- Step-by-step debugging transcripts ("First I tried X, then Y…")
- One-off workarounds specific to a single bug instance
- Information already derivable from `package.json`, `tsconfig.json`, etc.
- Metrics that will drift (counts, percentages, timestamps)

