---
name: agentsview-extract
description: Analyze conversation history across AI agents using agentsview (CLI-first or via MCP) to extract reusable gotchas/preferences into AGENTS.md or construct new skills. Use when the user asks to analyze past sessions, extract gotchas, or build new skills from past history.
---

# agentsview-extract

Analyze conversation history across agentic coding tools (Claude Code, Antigravity, Cursor, etc.) via `agentsview` (CLI or MCP), extract non-derivable gotchas and preferences into `AGENTS.md`, or package complex workflows into new agent skills.

## Core Principles

1. **CLI-First with MCP Fallback**: Use `agentsview` CLI commands (e.g., `agentsview session list`, `agentsview search`, `agentsview get`) directly via shell for fast execution without daemon requirements. Fall back to MCP tools (`search_content`, `get_messages`) if `agentsview` MCP server is already connected.
2. **Self-Contained Security**: Scrub all sensitive data (API keys, tokens, credentials, private IPs) using [references/security.md](references/security.md) before presenting or writing extracted content.
3. **Human-in-the-Loop Asset Routing**: Never write extracted gotchas or create new skills without explicit user review and confirmation.

## 3-Stage Pipeline Workflow

### Stage 1: Search & Retrieval
1. **Verify & Locate History**:
   - Check CLI availability (`command -v agentsview`). If missing, refer to [AgentsView Quickstart](https://www.agentsview.io/quickstart/) or [references/agentsview-cli.md](references/agentsview-cli.md).
   - Using CLI: Consult [references/agentsview-cli.md](references/agentsview-cli.md) for command examples.
     - Search sessions by keyword/topic: `agentsview search "<topic_or_error>"`
     - List recent sessions: `agentsview session list --limit 20`
     - Inspect specific session messages: `agentsview session get <session-id>` or `agentsview session export <session-id>`
   - Using MCP (if active):
     - `search_content(query="...")` or `list_sessions(...)` followed by `get_messages(session_id="...")`.
2. **Filter Relevant Transcripts**: Identify target sessions that contain problem-solving steps, error tracebacks, bug fixes, or specialized workflows.

### Stage 2: Pattern Recognition & Synthesis
1. **Analyze Session Transcripts**:
   - Distill the root cause of issues, non-obvious configurations, or environment quirks.
   - Recognize complex multi-step patterns that were successfully executed (e.g., deploying a complex stack, running niche migration scripts).
2. **Scrub Sensitive Data**:
   - Filter out secrets, passwords, Bearer tokens, and private hostnames using patterns in [references/security.md](references/security.md).

### Stage 3: Asset Routing & Confirmation

Evaluate the synthesized findings and route them into one of two asset types:

#### Option A: Gotchas & Preferences -> `AGENTS.md`
- **Criteria**: Concise, project-specific gotcha, non-obvious fix, or user preference (1–3 bullet points).
- **Confirmation Protocol**:
  1. Present the scrubbed candidate Gotcha snippet to the user.
  2. Explain why it is non-derivable and valuable for future agent sessions.
  3. Upon user confirmation, append to `AGENTS.md` (or `~/.agents/AGENTS.md` if global) under `## Lessons Learned` or relevant section, adhering to the 100-line bloat limit (prune if > 5 entries).

#### Option B: Complex Workflow / Expertise -> New `SKILL.md`
- **Criteria**: Multi-step workflow, specialized toolchain setup, or recurring complex procedure suitable for automation.
- **Confirmation Protocol**:
  1. Propose the new Skill name (e.g., `skills/<skill-name>/SKILL.md`), description, and directory structure.
  2. Outline the proposed `SKILL.md` content (YAML frontmatter + step-by-step guidance + reference pointers).
  3. Upon user confirmation, create `skills/<skill-name>/SKILL.md` and auxiliary files, and update `README.md`.

## Reference Documentation
- Security & Secrets Redaction Rules: [references/security.md](references/security.md)
- `agentsview` CLI Usage Guide: [references/agentsview-cli.md](references/agentsview-cli.md)
