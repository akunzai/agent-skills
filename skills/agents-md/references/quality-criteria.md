# Quality Criteria & Assessment Rubrics for `AGENTS.md`

Use this rubric when grading an existing `AGENTS.md` (or `CLAUDE.md`). Candidate
and prune gates for Self-Reflection live here; the Candidate → Promote → Prune
procedure lives in `SKILL.md`.

## 1. Quality Assessment Checklist

An effective file gives the agent only what it cannot cheaply recover from the
repo, and spends the **instruction budget** on every-task facts plus pointers.

### Evaluation Criteria

| Criterion | Weight | Assessment Questions |
|---|---|---|
| **Instruction budget** | High | Does every root line pass the every-task test or exist as a pointer? Is the one-sentence project description present? |
| **Progressive Disclosure** | High | Is `AGENTS.md` lean (< 100 lines)? Are domain rules and SOPs behind `@path` or a skill? |
| **Commands & package manager** | High | Is a non-default package manager named? Are only non-standard or expensive-to-discover commands cached? |
| **Rich References & SSOT** | High | Does it point to schemas and gold-standard tests instead of prose specs? Does it treat `package.json` / configs / the tree as the live source? |
| **Monorepo boundaries** | High | When nested files exist, does the root own shared policy, docs, and Self-Reflection while each autonomous child starts with its purpose and carries only local commands, decisions, and completion? Can independently cloned packages operate from their own root file? |
| **Capabilities** | High | Does it describe what the project does and its stable domain terms, rather than a file-by-file map? |
| **Micromanagement Audit** | High | Is it free of generic hygiene and defensive boilerplate the model already knows? |
| **Contradictions** | High | Are conflicting instructions named, and has the user chosen which version to keep? |
| **Non-Obvious Patterns** | Medium | Are gotchas context-tagged and non-derivable? |
| **Currency & Pruning** | Medium | Are Self-Reflection reference files pruned of stale workarounds? |

## 2. Quality Scores

### Grade A (90-100): Lean index
- Concise (< 100 lines) index: one-sentence description, non-default package manager, non-standard commands, pointers.
- Zero micromanagement; environment is the live source; capabilities over paths.
- Self-Reflection knowledge lives in dedicated topic files (or `lessons-learned.md`), referenced via `@path`, and is actively pruned.
- In a monorepo, root and nested files have distinct scopes; nested files exist only for autonomous local decisions.

### Grade B (70-89): Minor gaps / slight bloat
- Commands and basic patterns are documented, but some every-task lines are missing or some single-domain rules still sit in the root.
- Slight verbosity (> 100 lines) without proper offloading.

### Grade C (50-69): Verbose or micromanaged
- Generic hygiene rules, long prose instead of Rich References, or an init-script dump.
- Self-Reflection knowledge is left inline, or its reference files are unpruned.

### Grade D (30-49): Sparse, over-constrained, or drifted
- Missing the one-sentence description or the non-default package manager.
- File-by-file maps, drifting metrics, or rules that contradict `package.json` / configs.

### Grade F (0-29): Critically flawed / missing
- File does not exist, or listed commands fail immediately.

## 3. Red Flags

Eliminate these on sight:

*   **Micromanagement**: `"Always write comments."`, `"Do not introduce syntax errors."`, `"Use clean functions."` — the model already does this; the lines only dilute attention.
*   **SSOT / cache rot**: repeating `package.json`, `tsconfig.json`, or linter config.
*   **Ceremonial nesting**: empty "follow the root" files, copied root rules, or nested files created only because `src/` or `tests/` exists.
*   **Monolithic SOP Bloat**: multi-step deploy or migration scripts in the root file.
*   **Inline Lessons Learned**: gotchas written in `AGENTS.md` instead of a topic file referenced via `@path`.
*   **Drifting metrics**: `"25 unresolved issues"`, `"85% coverage"`.
*   **Prose tutorials**: explaining stock framework mechanics.
*   **File-by-file maps**: paths churn; describe capabilities and point at folders or schemas.
*   **Generated dump**: init-script or "useful for most scenarios" filler.
*   **Heavy-handed pointers**: ALL-CAPS or "ALWAYS" / "NEVER" where a light-touch reference would do.
*   **Unresolved contradictions**: two instructions that cannot both be followed.

## 4. Self-Reflection Criteria

### Candidate eligible (must meet ALL)

| Gate | Description |
|---|---|
| **Non-derivable** | Cannot be inferred by reading source or docs alone |
| **Context-Tagged** | Bounded by library version, OS, or env flags (e.g., `[Vite 5.x]`) |
| **Durable & Actionable** | Constrains a concrete agent decision across sessions |
| **Concise** | Fits in ≤ 2 bullet points |

### Reject at Candidate stage

- Step-by-step debugging transcripts
- One-off workarounds for a single bug
- Facts already in `package.json`, `tsconfig.json`, or the tree
- Metrics that will drift (counts, percentages, timestamps)

### Prune when ANY apply

- **Obsolete Version**: the library is past the tagged gotcha.
- **Derivable in Code**: a linter or type now enforces it.
- **Duplicate Coverage**: the same insight lives in another topic file → merge.
- **Transitory Transcript**: bug-fix logs ("First I tried X…").
