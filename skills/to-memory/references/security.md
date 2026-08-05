# Memory Security Specifications

Strict security restrictions and quality constraints for what `to-memory` may
write, at either tier.

## 1. Strictly Prohibited Data

Never record, log, or persist the following sensitive information under any
circumstances:

- **Authentication**: Passwords, API keys, access tokens, SSH keys, private
  certificates.
- **Environment**: Cloud provider credentials, private registry logins, local
  system tokens.
- **Privacy**: Customer personal identifiable information (PII), proprietary
  private datasets, or confidential database records.

## 2. Quality & Authenticity Safeguards

- **No Speculations**: Never write AI-generated guesses, unverified assumptions,
  or speculative ideas directly into durable memory.
- **Diligence Rule**: Only persist knowledge that has been validated as working in
  the active environment.
- **Redact, Don't Drop**: If only part of a note is sensitive, redact the
  sensitive part rather than discarding the whole note. Refer to a safe artifact
  path or URL instead of copying sensitive content.
