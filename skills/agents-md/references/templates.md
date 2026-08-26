# Templates & Formatting for `AGENTS.md`

Starter skeletons only. Fill every placeholder from repo evidence. Skip
init-script dumps. https://agents.md/ is the format: plain Markdown acting as
an index. Keep the root file under 100 lines.

## 1. Root starter

```markdown
# [Project Name] Developer Guidelines

This is a <one-sentence project description>.

This project uses <package manager>.

## Commands
- <only non-standard or expensive-to-discover commands, e.g. a single-test invocation>

## Pointers
- Domain schemas: @src/types/index.ts
- Gold-standard test: @tests/example.spec.ts
- <Domain> conventions: docs/<domain>.md

## Self-Reflection
- **Candidate**: Distill a non-obvious gotcha into ≤ 2 context-tagged bullets. Propose it before writing.
- **Promote**: On confirmation, write it to a dedicated file — merge an existing topic doc, else `docs/<topic>.md`, else `docs/lessons-learned.md`. Add or update one `@path` line under Pointers.
- **Prune**: Drop entries once stale (obsolete version, now enforced, duplicated, or a transcript) — not by a fixed count.
```

Omit the package-manager line when it is the ecosystem default. Omit a
lessons-learned `@path` until the first candidate is confirmed and promoted.
Language-specific rules belong in `docs/<domain>.md`, reached by a light-touch
pointer (`For TypeScript conventions, see docs/TYPESCRIPT.md`).

Code style bullets belong here only when a nearby file or config proves them.

## 2. Monorepo hierarchy

Use the root file for repository-wide policy, shared references, cross-package
completion criteria, and Self-Reflection. A nested file belongs only at an
autonomous package or app boundary; it is not a required file in every
directory.

Root file — repo-wide facts only:

```markdown
This is a monorepo of <services>.
This project uses <workspace tool>.

When work is contained in an autonomous package, read its nearest AGENTS.md
for local guidance.

## Cross-package completion
- When changing a shared contract, validate every affected consumer.

## Self-Reflection
<the shared Self-Reflection rules>
```

Package file — only its local decisions:

```markdown
This package is a <one-sentence description>.

## Commands
- <a non-standard or costly-to-discover package command>

## Local invariants
- <a non-derivable constraint that differs from the root>

## Completion
- <the package-specific evidence required before work is done>
```

Do not copy root rules, shared `docs/` pointers, or Self-Reflection into the
package file. Do not create an empty package file that only redirects to the
root. Omit the Commands section when package configuration is enough; repeat
the package manager only when it differs from the root or ancestors do not load.
A subtree gets a deeper `AGENTS.md` only for a durable local decision (for
example, generated code or a security boundary). A package that can be cloned
or assigned independently needs a standalone root `AGENTS.md`.

## 3. Claude Code compatibility

Claude Code reads `CLAUDE.md`, not `AGENTS.md`. For every `AGENTS.md` whose
rules Claude Code should use, create a sibling `CLAUDE.md`: the repository root
and every nested package with local `AGENTS.md` rules. Use a symlink when no
Claude-specific instruction is needed. Document that convention once in the
root `AGENTS.md`:

```markdown
## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md` directly.
```

Create the sibling symlink only when `CLAUDE.md` is absent or already points to
`AGENTS.md`:

```bash
ln -s AGENTS.md CLAUDE.md
```

For Claude-specific local instructions, use a regular sibling `CLAUDE.md` that
imports the local file instead:

```markdown
@AGENTS.md

## Claude Code
- <a Claude-specific local instruction>
```

Do not import a parent `AGENTS.md` from a nested `CLAUDE.md`: Claude Code loads
the `CLAUDE.md` hierarchy, so that repeats root instructions.

If `CLAUDE.md` already exists and is not the intended symlink, do not replace it
blindly. Read it, summarize any unique instructions, propose a migration into
`AGENTS.md`, and ask for explicit approval before moving or replacing the file.

## 4. Pointers & lazy loading

```markdown
- Deployment SOP: @docs/deploy.md
- Database migration: @docs/db-migration.md
```

`@path/to/file` is the on-demand load. A domain doc may itself point deeper.

## 5. Self-Reflection entry shape

Create the topic file only after a confirmed candidate (see `SKILL.md` §4).
Gates live in [quality-criteria.md](quality-criteria.md).

```markdown
- [Node 20+] Running `npm test` without `--forceExit` hangs in CI due to an unclosed DB connection in `src/db/client.ts`.
```

Then add one pointer from the root file:

```markdown
- Lessons Learned: @docs/lessons-learned.md
```
