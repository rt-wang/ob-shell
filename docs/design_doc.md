# Fast Obsidian Mobile Client — Design Doc

## 1. Summary

Build a lightweight mobile companion for an existing Obsidian vault. The app should open quickly, show recently changed Markdown files, allow simple editing, and support quick capture. It should not try to replace Obsidian’s plugin system, graph view, backlinks, Dataview, canvas, or full desktop experience.

The core idea:

> Obsidian remains the main knowledge system. This app is a fast mobile shell for Markdown editing and recent-file access.

## 2. Problem

Obsidian mobile can feel slow because opening a vault may involve loading the full vault structure, reading `.obsidian` config, starting plugins, loading themes/CSS, building indexes, waiting for sync-provider hydration, and restoring workspace state.

For mobile use, the user often only needs to open a recent note, edit Markdown, append a quick thought, or see what changed recently.

## 3. Goals

Primary goals:

* Launch quickly.
* Access an existing Obsidian vault folder.
* Show recently modified Markdown files.
* Open, edit, and save `.md` files.
* Detect file changes made by desktop Obsidian or another mobile editor.
* Support quick append to Daily Note or Inbox.
* Avoid touching Obsidian configuration files.

Non-goals:

* No Obsidian plugin compatibility.
* No Dataview execution.
* No graph view or backlinks graph in MVP.
* No Canvas support in MVP.
* No full backlinks engine in MVP.
* No custom Obsidian theme support.
* No replacement for Obsidian Sync.
* No editing of `.obsidian/` internals.

## 4. MVP Scope

### Vault Access

The user selects an existing Obsidian vault folder.

On iOS:

* Use folder picker.
* Store security-scoped bookmark.
* Resolve folder permission on launch.

On Android:

* Use Storage Access Framework.
* Persist URI permissions.

### File Index

Maintain a local SQLite index of Markdown files.

Fields:

```sql
CREATE TABLE notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  filename TEXT NOT NULL,
  folder TEXT,
  title TEXT,
  first_heading TEXT,
  preview TEXT,
  modified_at INTEGER NOT NULL,
  size_bytes INTEGER NOT NULL,
  last_opened_at INTEGER,
  is_deleted INTEGER DEFAULT 0
);
```

Indexing strategy:

* Scan `.md` files.
* Ignore `.obsidian/`, `.trash/`, `.git/`, `node_modules/`, and attachment folders.
* Load cached index immediately on launch.
* Refresh changed files in background using modified time and size.
* Parse only minimal metadata: path, title, first heading, preview, modified time, and file size.

### Recent Changes View

Default home screen:

* Recently modified notes
* Edited today
* Edited this week
* Daily notes
* Inbox / quick capture note

### Markdown Editor

Basic requirements:

* Open `.md` files lazily.
* Plain text editing.
* Save button and optional autosave.
* Preserve raw Markdown.
* Show modified time.
* Detect if the file changed externally while open.

### Quick Capture

Support:

* Append to `Inbox.md`
* Append to today’s Daily Note
* Optional timestamp prefix
* Optional source URL
* Optional selected/shared text

Example:

```md
## 2026-06-22 15:42

Thought text here.

Source: https://example.com
```

## 5. Architecture

```text
App
├── VaultAccessManager
│   ├── Request vault folder access
│   ├── Store persistent permission
│   └── Resolve vault URL on launch
│
├── VaultIndexer
│   ├── Scan Markdown files
│   ├── Compare modified time and size
│   ├── Extract title / preview
│   └── Update SQLite index
│
├── NoteRepository
│   ├── Read note content
│   ├── Save note content
│   ├── Atomic write
│   └── Conflict detection
│
├── RecentChangesService
│   ├── Recently modified
│   ├── Recently opened
│   └── Daily notes / inbox filters
│
├── MarkdownEditor
│   ├── Plain text editor
│   ├── Save / autosave
│   └── External change warning
│
└── QuickCaptureService
    ├── Append to Inbox.md
    ├── Append to Daily Note
    └── Share extension / shortcut support
```

## 6. Launch Flow

Desired fast launch path:

```text
Open app
→ Resolve vault permission
→ Load SQLite index
→ Render recent notes immediately
→ Start background refresh
→ Update list as changed files are discovered
```

Avoid:

```text
Open app
→ Recursively read entire vault
→ Parse every Markdown file
→ Build full backlinks graph
→ Load plugins
→ Load theme
→ Render UI
```

## 7. Sync Model

The app should not implement its own sync service in MVP.

Sync should be handled by:

* iCloud Drive
* Obsidian Sync
* Dropbox
* Google Drive
* Git
* Syncthing
* Another file provider

The app only reads and writes local files exposed by the platform.

## 8. File Safety

Ignore by default:

```text
.obsidian/
.trash/
.git/
node_modules/
.DS_Store
```

Safe write strategy:

1. Check current file metadata.
2. Compare with metadata from when the file was opened.
3. If unchanged, write to temporary file.
4. Replace original file atomically where possible.
5. Update SQLite index.

Conflict detection should store:

```text
opened_modified_at
opened_size_bytes
opened_content_hash
```

Before saving, compare current metadata/hash. If changed, warn the user.

## 9. Platform Recommendation

Build iOS first.

Recommended stack:

* SwiftUI
* SQLite
* Native file picker
* Security-scoped bookmarks
* TextEditor or custom UIKit text view wrapper
* Share Extension later
* App Shortcuts later

Reasoning:

* Better native access to iOS Files behavior.
* Better performance for file-heavy workflows.
* Easier to handle security-scoped URLs correctly.
* Smaller MVP surface area.

## 10. Roadmap

### Version 0.1

* iOS app
* Pick vault folder
* SQLite file index
* Recent files view
* Open/edit/save Markdown
* Manual refresh
* Quick append to `Inbox.md`

### Version 0.2

* Daily note support
* Background refresh on app foreground
* Conflict warning
* File name search
* Last opened list

### Version 0.3

* Share extension
* Append source URL and selected text
* SQLite FTS full-text search
* Basic wikilink autocomplete

### Version 1.0

* Fast stable editor
* Reliable vault indexing
* Share extension
* Daily note / inbox workflow
* Full-text search
* Conflict-safe saving
* Polished mobile UI

### Deferred / Post-MVP

* Graph view / backlinks graph
* Canvas support
* Obsidian plugin compatibility

## 11. Risks

### iCloud / File Provider Latency

Even if files are marked “Keep Downloaded,” iOS file providers can still behave unpredictably.

Mitigation:

* Show cached index immediately.
* Indicate when a file is unavailable.
* Retry file reads.
* Avoid blocking launch on a full scan.

### Permission Loss

Security-scoped bookmarks can become stale.

Mitigation:

* Detect failed bookmark resolution.
* Ask user to reconnect vault folder.
* Preserve SQLite cache but mark vault disconnected.

### File Conflicts

Desktop and mobile edits can conflict.

Mitigation:

* Metadata/hash check before save.
* Warn before overwrite.
* Save conflict copy if needed.

## 12. Success Metrics

Technical metrics:

* Cold launch to recent-files screen under 1 second after initial index.
* Open recent note under 300ms if local.
* Save normal Markdown file under 200ms.
* No accidental modifications to `.obsidian/`.
* No silent overwrites of externally changed files.

User metrics:

* User can capture a thought faster than opening Obsidian mobile.
* User can quickly see what changed since desktop usage.
* User trusts the app not to corrupt their vault.
* User still uses Obsidian desktop as the main knowledge system.

## 13. Recommended MVP Decision

Build the simplest useful version:

> iOS-native app that opens an existing vault, shows recently modified Markdown files instantly from cache, supports editing, and appends quick captures to Inbox.md or Daily Note.

Everything else should be deferred until the core loop feels instant and safe.
::: 

