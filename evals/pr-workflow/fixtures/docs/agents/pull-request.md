# Pull requests

## Description shape

1. A plain-language opening: what changed and why.
2. A visual, chosen by what changed:

   | Change | Visual |
   | --- | --- |
   | Flow or state transition | Mermaid `flowchart` / `stateDiagram` |
   | CLI or terminal output | Before/after terminal capture |
   | Appearance | Before/after screenshots |
   | Shell script or skill prose only | None; test output instead |

   When a change includes CLI output and an internal flow, the CLI capture
   wins over a flowchart.
3. A collapsed technical trailer with affected paths and verification commands.
