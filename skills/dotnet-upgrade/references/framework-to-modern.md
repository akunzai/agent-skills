# .NET Framework to modern .NET

Read when any project targets `net4*`, is a legacy (non-SDK) project, or is
a `netstandard` library that Assess flagged as fake-portable.

## SDK-style conversion

- Convert on the current TFM, leaf-first, one project per task. Keep the
  TFM, assembly name, root namespace, and package versions unchanged.
- Move `packages.config` to `PackageReference`; drop what SDK-style adds
  implicitly (`AssemblyInfo` attributes it generates, explicit `Compile`
  items, framework `Reference`s the SDK supplies).
- `upgrade-assistant` or `try-convert` may do the mechanical rewrite; the
  gate is still the build and tests on the old target.
- Legacy ASP.NET web application projects (`ProjectTypeGuids` containing
  `{349C5851-65DF-11DA-9384-00065B846F21}`) cannot become SDK-style
  ASP.NET Core projects in place; they move through the web host approach
  below.

## Libraries

- A library with Framework consumers multi-targets (`net472;net10.0`)
  until its last Framework consumer is gone. Condition Framework-only
  packages on `'$(TargetFramework)' == 'net472'`, and branch code with
  `#if NETFRAMEWORK`. At cutover, delete only the `NETFRAMEWORK` branches.
- Fake-portable `netstandard2.0` libraries: replace `System.Web` usage with
  abstractions the host supplies (`HttpUtility` → `System.Net.WebUtility`,
  `HttpContext.Current` → an injected accessor), move `SelectListItem`-style
  MVC types out of the library, and remove GAC `Reference`s. A library is
  done when it builds with `dotnet build -f net10.0` on a machine without
  Visual Studio.
- Code tied to one host framework (System.Web, MVC 5, OWIN,
  `System.Configuration`) splits into a portable core and a thin adapter
  per runtime, so the core multi-targets and each entry point references
  its own adapter.
- Retire `netstandard2.0` itself once no Framework consumer remains;
  retarget to the new TFM.

## Host entry points

Each host gets a second entry point on trunk so the runtime switch is a
deployment, not a merge:

- **Multi-target the host** (`net472;net10.0`) when its code compiles for
  both: consoles, services, and ASP.NET Core 2.x apps on Framework. One
  project yields two outputs; deploy either.
- **A new project beside the old one** when the host frameworks differ,
  as with MVC 5 or Web API 2 versus ASP.NET Core. It builds and tests in
  CI but is not deployed until its cutover; the web host approach below
  says how its controllers port.
- **No second entry point** only where neither fits, for example a small
  app cheaper to rewrite in place. That host, and only that host, goes on
  the long-lived upgrade branch. A branch that holds every host switch
  instead must merge trunk on every cadence, doubles the line to build and
  test, and silently drops trunk fixes to files already ported; offer it
  only with that cost stated.

While an old host and its replacement run at the same time against shared
state (a distributed cache, a session store, auth cookies, queued
messages), each must read what the other writes. Treating an unreadable
value as a cache miss is not enough when both write the same keys: each
keeps evicting the other's values. Keep a format both can read, or
separate the keys, until the old host is gone. Cut a web app over whole
rather than splitting its routes across both runtimes, unless the user
chose the side-by-side-in-production approach below and its shared auth
ticket.

## Configuration, DI, and ambient state

- `web.config` / `app.config` → `appsettings.json` plus
  `IOptions<T>`; custom config sections become option classes; transforms
  become per-environment files. Keep the old files while the old host
  ships.
- An XML-configured container (Spring.NET, Unity, Castle, Autofac modules)
  moves to `Microsoft.Extensions.DependencyInjection` when registrations
  are mostly singleton/transient/scoped. Heavy interceptors, child scopes,
  or decorators justify keeping the container behind its MS DI adapter.
- `HttpContext.Current`, `CallContext`, and thread-static state → an
  `AsyncLocal<T>` holder or `IHttpContextAccessor`.
- Keep EF6 on 6.3+ (it runs on modern .NET) and migrate to EF Core as a
  separate effort; two sources of breaking change at once hide each other.
  NHibernate 5.3+ runs on modern .NET unchanged.

## Web host approach

Pick one per web app with the user:

| Approach | Fits | Cost |
| --- | --- | --- |
| **In-place rewrite** on the fallback upgrade branch | Small apps (few controllers, little trunk churn) | Trunk changes to ported files merge silently into the old copy and are lost |
| **New host on trunk** (default for large apps) | Many controllers or active product work | A new ASP.NET Core project lands on trunk, undeployed and unrouted; controllers port one at a time |
| **Side-by-side in production** (YARP + System.Web adapters) | Continuous deployment with incremental release | Two hosts in production, shared auth cookie via a shared Data Protection key ring, shared database schema rules |

For the new-host and side-by-side approaches, keep a **migration ledger**:
one row per old controller or view with the new file that replaces it and
the commit it was ported from. A CI job (or the sync step) diffs each
ported old file against its recorded commit; a change means the port is
stale.

Port order inside a web app: baseline inventory of routes, filters,
modules, and `Global.asax` events (it becomes the acceptance checklist) →
host and config → DI → controllers without auth → middleware → auth →
authenticated controllers → views and static assets.

Mapping notes:

- `Global.asax` events, `IHttpModule`, `IHttpHandler`, `DelegatingHandler`
  → middleware, in the same order.
- Forms auth → cookie authentication; a fixed `machineKey` ticket shared
  with the old app needs the interop ticket format or a forced re-login.
- `ApiController` / `IHttpActionResult` → `ControllerBase` /
  `ActionResult<T>`. `[ApiController]` binds complex parameters from the
  body, and `Json()` uses System.Text.Json with camelCase; configure
  Newtonsoft (`AddNewtonsoftJson`) to keep the old wire format.
- Razor: `@helper` is unsupported (use partials, tag helpers, or local
  functions), child actions → view components, `Ajax.*` helpers → unobtrusive
  AJAX or fetch, `System.Web.Optimization` bundles → static files plus a
  front-end bundler or `WebOptimizer`.
- Third-party UI suites (Kendo, DevExpress, Syncfusion) need the vendor's
  ASP.NET Core package and license; confirm the license before planning
  the view port.
- Session state → `ISession` over a distributed cache; stored objects must
  be serializable to bytes.
- ASP.NET Core 2.x apps running on .NET Framework mostly need a TFM change
  plus the 2.x → current hosting and routing updates (`WebHost` →
  `WebApplication`, endpoint routing).
