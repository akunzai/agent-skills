# Memory Promotion Specifications

This reference provides the checklist and workflows required to safely promote a candidate memory to a long-term durable convention.

## 1. The Promotion Criteria

Before any entry flagged as `[Candidate]` is eligible for promotion to durable memory, the Agent must verify it against these four rules:

- [ ] **Verified**: The fact, fix, or workflow has been proven to work successfully in the current workspace.
- [ ] **Reusable**: The convention has a high probability of being useful in future sessions or to other developers on the project.
- [ ] **Stable**: It represents a lasting architectural choice, coding guideline, or tool configuration, not a temporary hack.
- [ ] **Not Handoff-Only**: Exclude transient continuation details such as current TODOs, partial verification status, open blockers, or suggested skills unless they reveal a stable convention.

## 2. Interactive Promotion Workflow

1. **Scan**: Identify `[Candidate]` memories in `.memories/YYYY-MM-DD.md` (project) or `memories/YYYY-MM-DD.md` (user).
2. **Filter**: Exclude any candidates that do not satisfy the promotion criteria above.
   - Treat short-term handoff notes as source material, not durable memory. Promote only the reusable rule or workflow behind them.
3. **Format**: Draft a concise entry suitable for `MEMORY.md` (global durable memory) or `AGENTS.md` (project, fallback to `CLAUDE.md` if `AGENTS.md` is absent).
   - **Clean-up Rule**: **Strip out daily time stamps** (e.g., `[HH:MM]`) to keep durable files timeless and strictly concise.
4. **Confirm**: Propose the drafted change to the user:
   > *"I found a stable convention in today's notes. Would you like me to promote it to local AGENTS.md (or CLAUDE.md)?"*
5. **Write & Log**: Upon user approval:
   - **Global Scope**: Write reusable durable memory to `~/.agents/MEMORY.md`.
   - **Project Scope**: Write the entry to `<repo>/AGENTS.md` (or `CLAUDE.md` if `AGENTS.md` is absent).
   - Mark the daily log entry as `[Promoted]` to keep logs auditable.
   - If the user declines promotion, mark the daily log entry `[Rejected]` (instead of
     `[Promoted]`) so it no longer blocks short-term cleanup as an unresolved candidate.
