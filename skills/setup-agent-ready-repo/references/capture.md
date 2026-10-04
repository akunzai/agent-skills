# Capturing evidence, by platform

A seed list. The agent proposes from it based on what the project
actually is, the developer chooses, and the decision goes into
`verification.md` so it is not relitigated on the next change.

Everything here is checked for availability at run time. When a skill or
binary is absent, fall back to the underlying tool and write the
fallback into the document, so a later agent knows which path is live.

| Project | Recording | Stills |
| --- | --- | --- |
| Website | `record-walkthrough`, else Playwright's built-in video | Playwright screenshots, before/after and at breakpoints |
| Terminal or TUI | `tcut`, else asciinema | `tcut` frame export |
| Electron | Playwright's Electron support — treat as a website | same |
| iOS simulator | `xcrun simctl io booted recordVideo` | `xcrun simctl io booted screenshot` |
| Android | `adb shell screenrecord` (the `android` CLI has no recorder) | `adb exec-out screencap -p`; to target elements, `android screen capture -a` then `android screen resolve` |
| macOS desktop GUI | `screencapture -v`, else the UI test framework's artifacts | `screencapture` |
| Windows desktop GUI | `ffmpeg -f gdigrab -i desktop` (or `-i title=<window>`), else the UI test framework's artifacts | `ffmpeg -f gdigrab -frames:v 1 -update 1`, else PowerShell `System.Drawing` `CopyFromScreen` |
| Linux desktop GUI | X11: `ffmpeg -f x11grab -i $DISPLAY`; Wayland (wlroots): `wf-recorder`; else the UI test framework's artifacts | X11: `ffmpeg -f x11grab -frames:v 1 -update 1`; Wayland (wlroots): `grim` |
| Backend or library | none | test output, plus evidence the dependency received the call |

Gotchas for the native rows; propose them as candidates and confirm with
the developer before writing one into a project:

- macOS: `screencapture` fails with `could not create image from display`
  unless the terminal has Screen Recording permission. Full-screen capture
  records the whole desktop; prefer `-l <windowid>`.
- iOS simulator: stop `recordVideo` with SIGINT and wait for exit, or the
  file is not finalized.
- Android: `android screen resolve` returns pixel coordinates usable by
  `adb shell input tap`. `android layout` may fail to install its
  instrumentation APK; fall back to `screen capture -a`.
- Linux:
  - X11 headless: `xvfb-run` hangs if background GUI apps remain alive; start
    `Xvfb :99 -screen 0 1280x720x24 &`, export `DISPLAY=:99`, and pass
    `-update 1` to `ffmpeg -frames:v 1` to satisfy the image2 muxer.
  - Wayland headless (wlroots): start Sway with `WLR_BACKENDS=headless
    WLR_LIBINPUT_NO_DEVICES=1 sway --unsupported-gpu &` and wait for `$SWAYSOCK`.
    Stop `wf-recorder` with SIGINT (`kill -INT <pid>`) and wait for exit, or the
    MP4 container is not finalized. GNOME and KDE Wayland require another path
    (PipeWire/portal).
- Windows:
  - `gdigrab` and `System.Drawing.CopyFromScreen` require an active interactive
    desktop session (Session 1+). Running in Session 0 (service accounts,
    background daemons, WinRM, Azure Run Command) fails with `The handle is
    invalid` or `Failed to capture image (error 5)`. Headless automation must
    configure AutoLogon and run commands in the interactive console session
    (e.g., Task Scheduler with `/it`).
  - Pass `-update 1` to `ffmpeg -frames:v 1` for stills to satisfy the image2
    muxer.

## UI locale

Browser automation starts in `en-US` whatever the developer's own browser
says, so a localized app is captured in English unless the capture sets
a locale. Look for evidence the UI ships more than one language: a
locale or resource directory holding several languages (`locales/`,
`i18n/`, `*.resx` per culture, `messages_*.properties`), an i18n library
(`i18next`, `next-intl`, `vue-i18n`, `react-intl`), or code reading
`Accept-Language`, a `?locale=` parameter or a locale cookie.

Found: propose the language requests are written in as the UI locale
when the UI ships it, else the UI's default, and let the developer
confirm. Then read how the app picks its locale and write down what
overrides the browser language. A leftover cookie or local-storage value
that outranks it turns a correctly configured capture back into English,
and nothing in the capture command shows why.

Not found: record that the UI has one language and ask nothing.

## Capture rules already written elsewhere

A request or issue document the repo already had may name its own
capture tool — "use Playwright's built-in video", say — written before
`verification.md` existed. Two rules in two files disagree, and an agent
follows whichever it read last. Replace that passage with one line
pointing at `verification.md`'s Capturing evidence, show the diff, and
wait for confirmation like any other edit.

## When nothing fits

Write "this project has no automated visual evidence path" into
`verification.md` and move on. An improvised capture method that nobody
has run is a liability: the next agent will follow it, fail, and treat
the failure as an application bug.
