# Quality Criteria & Assessment Rubrics for `AGENTS.md`

This document defines the metrics and evaluation checklist used to assess and score the quality of `AGENTS.md` (and `CLAUDE.md`) files in repositories.

---

## 1. Quality Assessment Checklist

An effective instruction file provides precise, developer-level constraints that the AI cannot guess merely by browsing the codebase, while adhering to **Progressive Disclosure** and **Single Source of Truth (SSOT)**.

### Evaluation Criteria

| Criterion | Weight | Assessment Questions |
|---|---|---|
| **Commands & Workflows** | High | Are the exact build, test, and run commands listed? Are single-file/single-test execution methods explained? |
| **Progressive Disclosure** | High | Is `AGENTS.md` lean (< 100 lines)? Are auxiliary files loaded via **Lazy Loading / On-demand Loading** (`@path`) and complex SOPs offloaded via **Context Offloading**? |
| **Rich References & SSOT** | High | Does it point to type definitions/schemas and gold-standard tests instead of long text specs? Are rules non-redundant with `package.json`? |
| **Architecture Clarity** | High | Does the file outline the core design blocks and directory mappings? Can the agent understand module relations immediately? |
| **Non-Obvious Patterns** | Medium | Are gotchas, environment variables, or custom configuration patterns documented with context tags? |
| **Micromanagement Audit** | High | Is the file free from defensive boilerplate ("write clean code", "add comments") and generic negative constraints? |
| **Currency & Pruning** | Medium | Are Self-Reflection reference files (topic docs / `lessons-learned.md` fallback) actively pruned and free from stale/obsolete workarounds? |

---

## 2. Quality Scores

### Grade A (90-100): Lean, Actionable & Rich References
- Concise (< 100 lines) functioning as an Index-driven Entrypoint.
- Has exact command strings for building, testing, linting, and single-test execution.
- Uses Rich References: points directly to key type definitions (`@src/types.ts`) and gold-standard tests (`@tests/feature.spec.ts`).
- Zero micromanagement or defensive boilerplate; trusts model reasoning for standard programming.
- Self-Reflection knowledge lives in dedicated topic files (or the `lessons-learned.md` fallback), referenced from `AGENTS.md` via `@path`, actively pruned and free of stale entries.

### Grade B (70-89): Minor Gaps / Slight Bloat
- Commands and basic patterns are well-documented.
- Missing single-file test options or minor architectural pointers.
- Slight verbosity (> 100 lines) without proper *Context Offloading*.

### Grade C (50-69): Verbose or Micromanaged
- Contains basic build commands.
- Includes generic micromanagement rules ("write clean code", "always handle errors").
- Uses long prose descriptions instead of Rich References (types/tests).
- Self-Reflection knowledge is left inline in `AGENTS.md` (old format), or its reference files are unpruned and full of stale entries.

### Grade D (30-49): Sparse, Over-Constrained, or Drifted
- Missing essential run or test commands.
- Full of defensive negative constraints and vague instructions.
- Duplicate instructions conflicting with `package.json` or system prompts (violates SSOT).

### Grade F (0-29): Critically Flawed / Missing
- File does not exist, or is completely broken.
- Commands lead to immediate errors upon execution.

---

## 3. Red Flags & Anti-Patterns (To Be Eliminated)

When auditing `AGENTS.md`, look for and immediately eliminate these elements:

*   **Defensive Micromanagement & Generic Rules**: Eliminate boilerplate statements like:
    - `"Always write comments."`
    - `"Do not introduce syntax errors."`
    - `"Use clean functions."`
    - `"Always handle null pointers defensively."`
    Modern models handle these natively. Including them causes Attention Dilution and wastes context space.
*   **SSOT Violations (Redundant Rules)**: Duplicate configurations already present in `package.json`, `tsconfig.json`, or linter configs.
*   **Monolithic SOP Bloat**: Embedding 10-step deployment or migration scripts inside `AGENTS.md` instead of performing *Context Offloading* to dedicated Skills or `@docs/sop.md`.
*   **Inline Lessons Learned**: Gotchas or insights written directly inside `AGENTS.md` instead of being promoted to a dedicated topic file (or `lessons-learned.md` fallback) referenced via `@path`. Migrate on discovery per the Self-Reflection workflow.
*   **Derivable State / Drifting Metrics**: Hardcoded numbers that drift constantly:
    - `"The codebase has 25 unresolved issues"`
    - `"Current test coverage is 85%"`
*   **Verbose Prose Tutorials**: Long explanations of standard framework mechanics (e.g. explaining React `useEffect`).
*   **Stale File Paths**: Documenting file-by-file structures. If files are renamed, the document drifts. Link to high-level folders instead.

---

## 4. Self-Reflection Criteria

When evaluating a newly discovered insight or auditing existing reference files:

### ✅ Candidate eligible (must meet ALL)
| Gate | Description |
|---|---|
| **Non-derivable** | Cannot be inferred by reading source code or docs alone |
| **Context-Tagged** | Scope is bounded by library version, OS, or env flags (e.g., `[Vite 5.x]`) |
| **Durable & Actionable** | Constrains a concrete agent decision across sessions |
| **Concise** | Fits in ≤ 2 bullet points |

### ❌ Do NOT promote (reject at Candidate stage)
- Step-by-step debugging transcripts ("First I tried X, then Y…")
- One-off workarounds specific to a single bug instance
- Information already derivable from `package.json`, `tsconfig.json`, etc.
- Metrics that will drift (counts, percentages, timestamps)

### ✂️ Pruning Triggers (eliminate when ANY apply)
- **Obsolete Version**: The library/framework has been upgraded past the tagged gotcha version.
- **Derivable in Code**: The gotcha is now enforced statically by a linter rule or TypeScript type.
- **Duplicate Coverage**: The same insight already exists in another topic file or the fallback -> merge and delete the duplicate.
- **Transitory Transcript**: Bug-fix step-by-step logs ("First I tried X, then Y…").


