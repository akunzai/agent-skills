# Capturing evidence, by platform

A seed list. The agent proposes from it based on what the project
actually is, the developer chooses, and the decision goes into
`verification.md` so it is not relitigated on the next change.

Everything here is checked for availability at run time. When a skill or
binary is absent, fall back to the underlying tool and write the
fallback into the document, so a later agent knows which path is live.

| Project | Recording | Stills |
| --- | --- | --- |
| Website | `to-walkthrough-video`, else Playwright's built-in video | Playwright screenshots, before/after and at breakpoints |
| Terminal or TUI | `tcut`, else asciinema | `tcut` frame export |
| Electron | Playwright's Electron support — treat as a website | same |
| iOS simulator | `xcrun simctl io booted recordVideo` | `xcrun simctl io booted screenshot` |
| Android | `adb shell screenrecord` | `adb exec-out screencap -p` |
| macOS desktop GUI | `screencapture -v`, else the UI test framework's artifacts | `screencapture` |
| Backend or library | none | test output, plus evidence the dependency received the call |

The iOS, Android, and macOS rows are untested here. Propose them as
candidates and confirm with the developer before writing one into a
project.

## When nothing fits

Write "this project has no automated visual evidence path" into
`verification.md` and move on. An improvised capture method that nobody
has run is a liability: the next agent will follow it, fail, and treat
the failure as an application bug.
