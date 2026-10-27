# Blocker families

Check each family during Assess; count the files and projects each
touches. Verify package support against NuGet (supported frameworks on the
package page, or `dotnet package search`) rather than memory.

| Family | Signal | Replacement |
| --- | --- | --- |
| ASP.NET MVC 5 / Web API 2 | `System.Web.Mvc`, `System.Web.Http`, `Global.asax` | ASP.NET Core; see `framework-to-modern.md` |
| OWIN / Katana | `Microsoft.Owin*`, `IAppBuilder` | ASP.NET Core middleware and authentication handlers |
| WCF server | `ServiceHost`, `.svc` | CoreWCF, or gRPC / HTTP APIs |
| WCF client | `System.ServiceModel` client proxies | `System.ServiceModel.*` 6.x+ packages |
| Remoting, AppDomain creation, Code Access Security | `MarshalByRefObject` across domains, `AppDomain.CreateDomain` | Process isolation, `AssemblyLoadContext` |
| BinaryFormatter | `BinaryFormatter`, `[Serializable]` persisted | Removed in .NET 9. System.Text.Json, MessagePack, or protobuf. Persisted data changes format: for a cache, read an undecodable value as a miss rather than flushing, and trace which keys hold the only copy of state (locks, tokens, job progress) before cutover |
| System.Drawing | `System.Drawing.*` | Windows-only since .NET 6. SkiaSharp (MIT) or ImageSharp (check its license) |
| Windows-only APIs | Registry, EventLog, WMI, `System.DirectoryServices`, COM | `Microsoft.Windows.Compatibility` on a `-windows` TFM, or a portable replacement |
| WinForms / WPF | `System.Windows.Forms`, `PresentationFramework` | Run on `net10.0-windows`; not cross-platform |
| JavaScriptSerializer | `System.Web.Script.Serialization` | Newtonsoft.Json or System.Text.Json |
| WebClient / HttpWebRequest | obsolete warnings SYSLIB0014 | `HttpClient` via `IHttpClientFactory` |
| `ServicePointManager` TLS setting | `ServicePointManager.SecurityProtocol`, `SecurityProtocolType.Ssl3` | Delete the line on the new runtime and let the OS choose. With `Ssl3` in the mask the setter throws `NotSupportedException` at runtime, and the build shows only a `CS0618` easily lost among others; without it the setting does nothing for `HttpClient` or `SslStream` (SYSLIB0014). Callers often catch and log the exception, so the feature fails while tests stay green: grep for it rather than waiting for a test |
| SqlClient | `System.Data.SqlClient` | `Microsoft.Data.SqlClient`; `Encrypt` defaults to true |
| Crypto namespaces | `System.Security.Cryptography.Pkcs` / `.Xml` | Separate NuGet packages |
| ADAL | `Microsoft.IdentityModel.Clients.ActiveDirectory` | MSAL (`Microsoft.Identity.Client`) |
| ELMAH | `Elmah`, `elmah.corelibrary` | `ElmahCore` or the host's logging plus exception middleware |
| Binary references | `<Reference HintPath=...>` to checked-in DLLs | A maintained package, or retire the feature; each is a task |
| Old major versions | Quartz 2.x, Lucene.Net 3.x, Common.Logging adapters | Quartz 3.x (API change), Lucene.Net 4.8 (index format change: rebuild indexes), `Microsoft.Extensions.Logging`. Where the storage schema or format changes, keep old and new side by side (a new table prefix, a new index folder) and create the new one idempotently at startup, so both builds coexist through rollout and rollback without a manual database step |
| ICU globalization on Windows | Culture-sensitive string sorting or matching: `OrderBy` on strings, `string.Compare`, `StartsWith` / `IndexOf(string)` without a `StringComparison`; the app ships on Windows | Not a build error: .NET 5+ loads ICU on Windows where .NET Framework used NLS, so sort order and matching change silently (zh-TW puts Han before Latin). Tests on the new runtime pass, and characterization tests written on it pin the new order: compare old and new hosts' output. For a Windows deployment, restore parity with `<RuntimeHostConfigurationOption Include="System.Globalization.UseNls" Value="true" />` in the root `Directory.Build.props`, conditioned on `.NETCoreApp`; Linux has no NLS and ignores it. NLS mode loses IANA time zone ids in `TimeZoneInfo` |
| Out-of-support hosts | netcoreapp2.x/3.1, net5–7, ASP.NET Core 2.x | Retarget; follow each version's breaking-change list on learn.microsoft.com |

Keep: Newtonsoft.Json, log4net, NHibernate 5.3+, EF6 6.3+, Dapper, and
most `netstandard2.0` packages run on modern .NET. Replacing them is an
optional follow-up, not an upgrade task.

For modern-to-modern upgrades, read Microsoft's "Breaking changes in .NET
<N>" page for every major version crossed and check each entry against
the code.
