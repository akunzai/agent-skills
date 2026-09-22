---
name: dotnet-upgrade
description: >-
  Upgrade a .NET codebase to a newer .NET: .NET Framework 4.x to modern
  .NET, an out-of-support netcoreapp/net5+ to the current LTS, or
  netstandard libraries that only pretend to be portable. Use to assess,
  plan, execute, or resume a long-running upgrade while product work keeps
  shipping on the main branch.
---

# .NET Upgrade

A long upgrade outlives any one session and runs beside product work that
keeps landing on trunk. Two ideas carry the whole skill:

- **Trunk-safe**: a change is trunk-safe when the old target's build output
  and runtime behaviour stay the same. Trunk-safe work merges to the main
  branch early, in small requests, so the long-lived upgrade branch only
  holds what cannot coexist with the old app.
- **Cold start**: every session, including one after context compaction,
  begins by reading the upgrade state, never by remembering it.

## Upgrade state

Before anything else, find or create the state surface. Read
[`references/state.md`](references/state.md): it decides where the plan,
decisions, and progress live, and holds the resume protocol. An upgrade
already in progress resumes at the task its state names; skip to Execute.

## 1. Assess (read-only)

Inventory the repository. Done when every `*.csproj`, including the ones
no `*.sln`/`*.slnx`/`*.slnf` builds, has a row with:

- target framework(s), SDK-style or legacy format, project kind (web host,
  API, console, library, test, desktop), and the solutions that build it
- its dependency tier: tier 1 has no project references; tier N+1 depends
  only on lower tiers. Flag cycles.
- its blockers, graded by how many files each touches. Check the families
  in [`references/breaking-changes.md`](references/breaking-changes.md).

Then record four findings the table does not show:

1. **Prior migration work.** Search git history for retargets, multi-target
   commits, DI or config rewrites, and projects on newer TFMs. Continue
   that direction rather than restarting it, and name its author so the
   user can coordinate.
2. **Fake portability.** A `netstandard2.0` project that still references
   `System.Web`, GAC assemblies, `ref/*.dll` binaries, or Framework-only
   packages builds only under Framework MSBuild. Count these as Framework.
3. **Verification gap.** What the tests cover versus what the upgrade
   touches. Web controllers, views, auth, session, and serialization
   usually have none; these become runtime checks in staging.
4. **Deployment.** How each host ships today (IIS, service, container),
   and what CI can and cannot prove.

## 2. Decide (one confirmation)

Put every open option to the user in one round, each with your
recommendation, and record the answers in the state surface. Where the
repo keeps ADRs, the target and platform decision is an ADR, and any doc
that contradicts it is corrected in the same trunk-safe change.

- Target TFM and platform goal: `net10.0` cross-platform, or
  `net10.0-windows` where Windows-only APIs stay.
- Scope: projects excluded or retired.
- Web host approach, per [`references/framework-to-modern.md`](references/framework-to-modern.md).
- Branch strategy: trunk-safe work to trunk, the rest on one long-lived
  branch synced from trunk by merge.
- Acceptance: which gates prove done, including a staging run when tests
  do not cover the runtime surface.
- Optional cross-platform build (developers on macOS or Linux build and
  run the app): if chosen, add the phase in
  [`references/cross-platform.md`](references/cross-platform.md).

## 3. Plan

Write the task list into the state surface. Each task names its tier or
milestone, whether it is **trunk-safe** or **branch-only**, and a
`Done when:` line a reviewer can check without reading code. Order:

1. Prerequisites: SDK pin in `global.json`, CI toolchain, cleanup of dead
   projects and solution entries.
2. SDK-style conversion on the **current** TFM, leaf-first, one project
   per task. Never combine it with a retarget: the two fail differently.
3. Retarget tier by tier. Libraries with Framework consumers multi-target
   (`net472;net10.0`); after each tier, every higher tier still builds and
   passes tests on the old target.
4. Hosts: APIs and consoles, then web apps.
5. Cutover: staging validation, switch, drop the old target.

## 4. Execute

Per task:

1. Cold start: re-read the decisions and the task.
2. Research the specific APIs and packages before editing.
3. Edit. A package or API with no drop-in replacement gets a
   `// STUB:<package-or-api> | task:<id>` marker so `git grep "// STUB:"`
   is the registry of deferred work; each marker becomes its own task.
4. Gate: the touched projects **and their dependents** build on every
   target they carry, with no new warnings, and their tests pass. A test
   that fails where the upgrade did not intend a behaviour change means
   production code is wrong; fix the code, keep the test. When CI is the
   evidence, confirm the job actually ran on the change: path-filtered
   jobs often skip toolchain files (`global.json`, `Directory.*.props`,
   CI config), and a skipped job is no evidence. Prefer a
   `check-runner` worker for build and test commands and a
   `log-summarizer` for long build logs.
5. Record what changed, the gate evidence, and any deviation from the
   task, then commit. Trunk-safe tasks go out as their own small request.

Three identical gate failures in a row stop the task: report the error
and its likely cause to the user.

## 5. Sync and cut over

Merge trunk into the upgrade branch on a fixed cadence and after every
trunk release, then rerun the gate. Where the approach duplicates a host
(new project beside the old one), check the migration ledger on every
sync: an already-migrated old file changed on trunk means the port is now
stale.

Cutover is done when every acceptance gate from Decide passes on the
upgrade branch, the `// STUB:` registry is empty or accepted by the user,
and a rollback path to the last old-target release is written down.
