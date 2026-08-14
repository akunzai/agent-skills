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

## 2. Monorepo split

Root file — repo-wide facts only:

```markdown
This is a monorepo of <services>.
This project uses <workspace tool>.
See each package's AGENTS.md for package-specific guidance.
```

Package file — that package's purpose, stack, and pointers:

```markdown
This package is a <one-sentence description>.
Follow docs/<package>-conventions.md for design patterns.
```

## 3. Claude Code compatibility

If the user requests compatibility with Claude Code, append:

```markdown
## Claude Code Compatibility

`CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. Edit `AGENTS.md` directly.
```

Create the symbolic link in the repository root only when `CLAUDE.md` is absent
or already points to `AGENTS.md`:

```bash
ln -s AGENTS.md CLAUDE.md
```

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
