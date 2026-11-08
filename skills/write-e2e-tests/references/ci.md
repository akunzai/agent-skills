# CI job

Write a job only after *repo* confirmation. Follow the project's
Node/toolchain install (mise, aube, pnpm, npm). Browser in
`playwright install --with-deps` matches the converted spec: the
*toolchain* scaffold choice if this run created `playwright.config`,
otherwise the browser already declared in the existing config
(`firefox` / `chromium` in `use` / `projects`). Use the project's
checkout action and Playwright image pins when they exist; the snippets
below are a starting shape, not a version spec.

## Which file

- `.github/workflows/` exists — add a job to an existing workflow, or a
  new `e2e.yml` if no workflow is a fit.
- `.gitlab-ci.yml` exists — add an `e2e` job there.
- Both exist — propose both in one confirm; write only the platforms
  the user ticks.
- Neither exists — propose GitHub Actions if `origin` is GitHub, GitLab
  CI if GitLab. No remote and user declines — skip.

## GitHub Actions

```yaml
e2e:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v7
    - name: Install toolchain
      run: # project's mise / setup-node / package-manager install
    - run: playwright install --with-deps firefox
    - run: playwright test
    - if: ${{ !cancelled() }}
      uses: actions/upload-artifact@v4
      with:
        name: playwright-report
        path: playwright-report/
```

Prefix `playwright` with the project's runner (`aube exec --`, `pnpm exec`,
`npx`, …). Swap `firefox` for `chromium` when the spec's config uses
Chromium.

## Performance & reporters

In `playwright.config`:

- **Concurrency**: Set `workers: process.env.CI ? 2 : undefined` to leverage
  standard 2-4 vCPU hosted runners instead of dropping to sequential 1-worker runs.
- **Browser matrix pruning**: For routine PR and push CI pipelines, scope
  tests to a single primary browser (e.g. Chromium) rather than full
  multi-browser matrices (`chromium`, `firefox`, `webkit`). Reserve cross-browser
  runs for nightly or release workflows to cut ~150-200 MB in browser
  downloads and halve CI test duration.
- **Failure reporters** (Playwright >= 1.65): Use `['failures']` for instant
  terminal output on errors without progress bars, and
  `['html', { onlyFailures: true }]` to record only unexpected or flaky runs,
  drastically cutting artifact payload size.

## GitLab CI

```yaml
e2e:
  image: mcr.microsoft.com/playwright:focal
  script:
    - # project's package-manager install
    - playwright install --with-deps firefox
    - playwright test
  artifacts:
    when: always
    paths:
      - playwright-report/
```

Use a Playwright image that matches the project's pinned Node when one
is already in the file; otherwise keep the install line and the
project's usual image.
