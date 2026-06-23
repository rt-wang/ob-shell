# Security Policy

Fast Obsidian Mobile is local-first software that reads and writes files from a user-selected folder. Please treat any vault path, note title, note body, screenshot, or file-provider detail as potentially sensitive.

## Reporting A Vulnerability

For sensitive reports, use GitHub Security Advisories after this repository is public. For non-sensitive bugs, open a regular GitHub issue.

Please do not include private vault contents, screenshots of personal notes, API keys, tokens, signing identities, or other secrets in public reports.

## Scope

Security-sensitive areas include:

- Security-scoped folder access.
- Bookmark persistence.
- File writes and autosave behavior.
- Conflict detection.
- Local index storage.
- Handling of vault paths and note metadata.

This app does not provide a sync service and should not be treated as a backup system.
