# Iteration 02: Real Vault Notes + Rendered Markdown

## Summary

This iteration turns the first visual prototype into a usable local-vault prototype. The app should let the user pick an Obsidian vault folder, scan the actual file structure for Markdown notes, render Markdown in a reading-first editor, and move the UI closer to the Concept D Editorial Minimal reference.

## Product Requirements

* Use the iOS folder picker to select a vault folder.
* Store and resolve a security-scoped bookmark for the selected folder.
* Recursively scan the selected folder for `.md` files.
* Ignore `.obsidian/`, `.trash/`, `.git/`, `node_modules/`, `.DS_Store`, and common attachment folders.
* Show actual vault notes in the Home / Recent Notes screen.
* Default note opening to rendered Markdown.
* Provide a read/edit toggle for raw Markdown editing.
* Save raw Markdown back to the selected file.
* Keep Quick Capture scoped to appending to `Inbox.md` or today's Daily Note.

## Markdown Rendering

Render a lightweight subset locally:

* `#`, `##`, and `###` as progressively smaller headings.
* Paragraph text as restrained body copy.
* `-`, `*`, and numbered list items as indented rows.
* `**bold**`, `*italic*`, `__underline__`, `<u>underline</u>`, and inline code where practical.
* Unrecognized Markdown remains readable as body text.

This is not intended to be a complete Obsidian renderer.

## UI Direction

Use the provided Concept D reference as directional guidance:

* Warm cream page background.
* Thin separators instead of heavy cards.
* Serif display text for greetings and note titles.
* Compact sans-serif metadata and controls.
* No large white boxed writing area on the reading screen.
* Raw edit mode should feel like writing on the page, not typing inside a heavy card.
* Quick Capture should use a quiet bottom sheet with minimal borders and a dark primary action.

## Out Of Scope

* Graph view or backlinks graph.
* Canvas.
* Obsidian plugin compatibility.
* Dataview execution.
* Custom theme compatibility.
* SQLite-backed indexing.
* Full Markdown or Obsidian syntax compatibility.

## Acceptance Criteria

* A user can choose a vault folder and see nested `.md` notes from that folder.
* Ignored folders and non-Markdown files do not appear.
* Opening a note shows rendered Markdown hierarchy.
* Edit mode shows raw Markdown and Save writes to the same file.
* Quick Capture creates or appends to `Inbox.md` or today's Daily Note in the selected vault.
* The app builds with `xcodebuild` for iOS Simulator.
* The UI remains inside the documented Editorial Minimal palette and typography hierarchy.
