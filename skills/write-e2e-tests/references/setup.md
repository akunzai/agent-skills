# Local toolchain

Follow the target project's package manager. One manager per project.

| Evidence | Add `@playwright/test` | Run binaries |
| --- | --- | --- |
| `bun.lock` / `bun.lockb` | `bun add -d @playwright/test` | `bunx --bun playwright …` |
| `pnpm-lock.yaml` | `pnpm add -D @playwright/test` | `pnpm exec playwright …` |
| `package-lock.json` | `npm install -D @playwright/test` | `npx playwright …` |
| `yarn.lock` | `yarn add -D @playwright/test` | `yarn playwright …` |

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
    launchOptions: {
      args: [
        '--disable-gpu',
        '--disable-dev-shm-usage',
        '--disable-background-networking',
      ],
    },
  },
});
```

Chromium switch: `devices['Desktop Chrome']`.

When defining multiple browser projects, mark the primary project `default: true`
(Playwright >= 1.65) so local CLI runs default to the primary browser only, avoiding
redundant multi-browser runs until requested via `--project`.

When scaffolding a `webServer` for modern frontend SPAs (Vite, Next.js, etc.), run
pre-built preview servers in CI rather than live dev servers to eliminate on-demand
JIT compilation latency:

```ts
  webServer: {
    command: process.env.CI ? 'npm run build && npm run preview' : 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
```

If the SPA relies on client-side mock service workers (e.g. MSW enabled
conditionally via `import.meta.env.DEV`), a standard production `preview` build
will exclude mock handlers. For mock-dependent apps, either pass a mock build flag
(such as `VITE_ENABLE_MOCK=true`) or keep `npm run dev`.

## Browser binaries

Install both, even when the spec will run on one:

```bash
playwright install firefox chromium
```

Prefix with the project's runner from the table. CUAWright launches
Firefox; the converted spec uses the browser chosen in *toolchain*.

## CUAWright skill

Install with [Skills Manager](https://github.com/akunzai/skills-manager)
when its `skills` binary is on `PATH`:
`skills add microsoft/CUAWright --skill cuawright-web --yes` (add `-p` for
project scope). Otherwise
`npx skills add microsoft/CUAWright --skill cuawright-web`
([CUAWright](https://github.com/microsoft/CUAWright)). Either lands the skill at
`~/.agents/skills/cuawright-web/SKILL.md` (user) or
`.agents/skills/cuawright-web/SKILL.md` at the git root (project); when the
harness does not list a skill installed mid-session, read that file
directly. Workspace paths live in that `SKILL.md`. Node `@playwright/test` does
not satisfy cuawright-web's browser runtime.
