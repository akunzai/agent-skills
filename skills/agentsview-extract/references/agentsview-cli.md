# agentsview CLI Quick Reference

`agentsview` is a CLI and MCP server for parsing, indexing, searching, and viewing agent transcripts (Antigravity, Claude Code, Cursor, Windsurf, etc.).

- [Primary Documentation & Quickstart](https://www.agentsview.io/quickstart/)
- [GitHub Repository](https://github.com/kenn-io/agentsview)

When using `agentsview-extract`, prefer executing `agentsview` CLI commands directly via shell execution.

## Installation & Verification

Verify whether `agentsview` is installed before executing CLI commands:

```bash
command -v agentsview || echo "agentsview not installed"
```

If `agentsview` is not installed, refer to [AgentsView Quickstart](https://www.agentsview.io/quickstart/) for official installation options (`brew install --cask agentsview`, `pip install agentsview`, `uvx agentsview`, script, or Docker).


## Common CLI Commands

### 1. Searching Transcripts
Search for specific error messages, package names, gotchas, or keywords across all agent sessions:

```bash
# Search for keyword or error string across all sessions
agentsview search "duckdb"

# Case-insensitive search
agentsview search -i "permission denied"

# Search within a specific project directory or workspace
agentsview search --project agent-skills "Gotcha"
```

### 2. Listing & Browsing Sessions
List recent agent sessions to locate relevant transcript IDs:

```bash
# List last 20 sessions
agentsview session list --limit 20

# Filter sessions by project name or agent provider
agentsview session list --project agent-skills
agentsview session list --provider antigravity
```

### 3. Viewing & Exporting Session Content
Inspect details or full message exchanges of a specific session:

```bash
# Get overview / metadata of a session
agentsview session get <session-id>

# Export or view raw messages of a session
agentsview session messages <session-id>
agentsview session export <session-id> --format markdown
```

### 4. System & Health Check
Verify `agentsview` installation and database index status:

```bash
agentsview doctor
agentsview stats
```

## MCP Tool Fallback

If `agentsview` is running as an MCP server and connected to the current agent session, call the corresponding MCP tools:
- `search_content(query="...")`: Full-text search across transcripts.
- `list_sessions(limit=20)`: Browse session list.
- `get_messages(session_id="...")`: Fetch message transcript.
