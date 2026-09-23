# Rewriting a PR, MR, or issue body

Editing part of an existing body (a PR, MR, or the tracking issue whose table
lists them) means fetch, change, write back. If the fetch or the edit fails and
the write still runs, the forge stores an empty or truncated body, and GitLab CE
keeps no version to restore it from. Run all three under `set -euo pipefail` in
one block rather than an `&&` chain: a newline after a heredoc ends the chain,
so the write on the next line runs even though the fetch failed. Refuse to
write a file that is empty or shorter than the fetched body:

```bash
set -euo pipefail
gh pr view <pr_number> --json body -q .body > body.md
test -s body.md
cp body.md body.orig.md
# ...edit body.md...
test "$(wc -c < body.md)" -ge "$(wc -c < body.orig.md)" || { echo "body shrank; not writing" >&2; exit 1; }
gh pr edit <pr_number> --body-file body.md
```

Keep `body.orig.md` until the write is confirmed; it is the only copy. On
Windows, parse forge JSON from bytes (`sys.stdin.buffer`), not a text stream
the console codepage decodes. Drop the size check only when the edit is
meant to delete content, and then diff the two files before writing.
