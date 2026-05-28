# Templates & Formatting for `AGENTS.md`

This document provides starter structures, formatting rules, and imports configuration for `AGENTS.md` files.

---

## 1. AGENTS.md Starter Template

Use this starter template when creating a new `AGENTS.md` file. Adjust the commands and folder layouts depending on the detected build and test frameworks.

```markdown
# [Project Name] Developer Guidelines

## Quick Commands
- Build: <command> (e.g., npm run build)
- Test: <command> (e.g., pytest)
- Lint/Format: <command> (e.g., npx eslint .)
- Run Dev: <command> (e.g., npm run dev)

## Architecture Overview
- `/src`: Main application logic
  - `/src/components`: UI components
  - `/src/hooks`: Custom React hooks
- `/tests`: Automated test suites

## Code Style & Conventions
- Use TypeScript for all new code. Always specify types; avoid `any`.
- Style components with Vanilla CSS; follow HSL variables defined in `/src/index.css`.
- Keep component files under 200 lines; split complex UI into sub-components.

## Workflows
- **Testing**: Before submitting a PR, always run tests locally. Prefer testing a single file for speed: `npm run test -- <filepath>`.
- **Git**: Branch name format: `feature/<desc>` or `bugfix/<desc>`.
```

---

## 2. Claude Code Compatibility Section

If the user requests compatibility with Claude Code, append this exact section to the bottom of `AGENTS.md`:

```markdown
## Claude Code Compatibility

> [!NOTE]
> This repository maintains compatibility with Claude Code. The file `CLAUDE.md` is a symbolic link pointing to `AGENTS.md`. 
> All commands, style guides, and workflows defined in `AGENTS.md` apply to both Antigravity (and other agentic assistants) and Claude Code.
> **DO NOT** delete the `CLAUDE.md` symbolic link or edit it independently; all guidelines must be updated directly in `AGENTS.md`.
```

And execute the symbol link creation command in the repository root:
```bash
ln -sf AGENTS.md CLAUDE.md
```

---

## 3. Advanced Imports and References

To maintain modularity and avoid overloading `AGENTS.md` with every detail, use imports for auxiliary guidelines (supported by agent systems including Claude Code):

```markdown
# Additional Instructions
- Git workflow: @docs/git-instructions.md
- Personal overrides: @~/.claude/my-project-instructions.md
```
- `@path/to/file` tells the agent to load the referenced file on-demand.
- Keep references to auxiliary files separated to save context token usage.

---

## 4. Lessons Learned Section (Optional)

Add this section to `AGENTS.md` only when the project has accumulated non-obvious institutional knowledge
discovered through problem-solving. Keep it short and prune stale entries regularly.

```markdown
## Lessons Learned
- <Short rule or gotcha, e.g. "Running `npm test` without `--forceExit` hangs in CI due to an open DB connection in `src/db/client.ts`">
- <Another non-obvious constraint discovered in practice>
```

> [!TIP]
> This section is a quality signal: if it grows beyond 5–7 bullets, consider promoting entries to
> the relevant section (Commands, Architecture, etc.) and deleting them here.

