# Cross-platform build phase

Optional; add it only when the user chose it in Decide. Goal: a developer
on macOS or Linux builds, tests, and runs the migrated parts with the
`dotnet` CLI alone.

## The progress filter

Create one solution filter (for example `<Product>.CrossPlatform.slnf`)
listing only projects that build with `dotnet build` on the new TFM. Add a
project the moment it qualifies; never add one that needs Visual Studio
MSBuild. The filter is the progress bar and the CI target: a non-Windows
CI job builds and tests it on every request, so a regression shows up the
day it lands.

Until a non-Windows runner exists, run the same `dotnet build` /
`dotnet test` on the filter from the Windows runner. That proves the
SDK-only build; it does not prove the code runs on Linux. Say which one
the evidence shows.

`net4*` targets still compile off Windows through the
`Microsoft.NETFramework.ReferenceAssemblies` package, which keeps
multi-targeted libraries buildable everywhere; they cannot run there.

## Portability sweep

Each is a trunk-safe task when the Windows default stays the same:

- Hard-coded paths (`D:\...`, `C:\...`, UNC shares) → configuration with
  the current value as the Windows default; build paths with
  `Path.Combine`, never `\`.
- File-name case: Linux file systems are case-sensitive; references to
  views, resources, and config files must match on-disk case.
- Windows-only APIs from `breaking-changes.md`: replace, or isolate
  behind an interface with a Windows implementation.
- Local dependencies (database, cache, queue) that live on a shared
  Windows host → a `compose.yaml` the developer starts locally, with
  connection strings from configuration or user secrets.
- Scripts: PowerShell-only dev scripts get a cross-platform equivalent
  (`pwsh`, `dotnet` tool, or a task runner).

Done when a clean clone on macOS or Linux builds and tests the filter and
starts each migrated host by following the repo's own docs, with no step
that needs Windows.
