# Local toolchain

Follow the target project's package manager. One manager per project.

| Evidence | Add `@playwright/test` | Run binaries |
| --- | --- | --- |
| `aube` on PATH or `mise.toml` pins `aube` | `aube add -D @playwright/test` | `aube exec -- playwright …` |
| `pnpm-lock.yaml` | `pnpm add -D @playwright/test` | `pnpm exec playwright …` |
| `package-lock.json` | `npm install -D @playwright/test` | `npx playwright …` |
| `yarn.lock` | `yarn add -D @playwright/test` | `yarn playwright …` |
| `bun.lock` / `bun.lockb` | `bun add -d @playwright/test` | `bunx playwright …` |

**aube and a new project (no lockfile yet):** a bare `aube add` writes
`aube-lock.yaml`, which Dependabot cannot maintain. Seed an empty
`pnpm-lock.yaml` (or `package-lock.json` if the project already uses one)
before adding the dependency, so aube writes into that format instead — see
the `aube` skill's "Keep a Dependabot-compatible lockfile" convention. Skip
only when the user confirms Dependabot coverage doesn't matter here.

Prefer `playwright.config.ts` when the project is TypeScript, otherwise
`playwright.config.js`. Leave an existing `playwright.config.*` in place.

## New config

Default browser is Firefox. Switch to Chromium only if the user confirmed
that in *toolchain*. `testDir` is `e2e/` unless the project already has
an e2e or Playwright test directory — use that.

```ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'e2e',
  use: {
    ...devices['Desktop Firefox'],
  },
});
```

Chromium switch: `devices['Desktop Chrome']`.

## Browser binaries

Install both, even when the spec will run on one:

```bash
playwright install firefox chromium
```

Prefix with the project's runner from the table. Webwright launches
Firefox; the converted spec uses the browser chosen in *toolchain*.

## Webwright skill

Install the way this environment already installs skills — typically
`npx skills add microsoft/webwright`
(https://github.com/microsoft/Webwright). The skill file is
`~/.agents/skills/webwright/SKILL.md` (user) or
`.agents/skills/webwright/SKILL.md` at the git root (project).
Workspace paths live in that `SKILL.md`. Node `@playwright/test` does
not satisfy webwright's browser runtime.
