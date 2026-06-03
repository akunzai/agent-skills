# Memory Security Specifications

This reference outlines strict security restrictions, quality constraints, and branch protection rules for memory management.

## 1. Strictly Prohibited Data

Never record, log, or persist the following sensitive information under any circumstances:
- **Authentication**: Passwords, API keys, access tokens, SSH keys, private certificates.
- **Environment**: Cloud provider credentials, private registry logins, local system tokens.
- **Privacy**: Customer personal identifiable information (PII), proprietary private datasets, or confidential database records.

## 2. Quality & Authenticity Safeguards

- **No Speculations**: Never promote AI-generated guesses, unverified assumptions, or speculative coding ideas directly into durable memory.
- **Diligence Rule**: Only persist knowledge that has been validated as working in the active environment.
- **Redact Handoffs**: Short-term handoff notes and daily logs must redact secrets, PII, private records, and credential-adjacent values. Refer to safe artifact paths or URLs when possible instead of copying sensitive content.

