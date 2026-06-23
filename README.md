# ob shell

A lightweight SwiftUI iOS companion for working with local Markdown notes from an Obsidian vault.

The app is intentionally small: open quickly, choose a vault folder, browse recent notes, edit plain Markdown, and append quick captures to `Inbox.md` or a daily note. It is not a replacement for Obsidian desktop or mobile.

This project is independent and is not affiliated with Obsidian.

## Status

Prototype / MVP. The current app targets iOS 17+ and builds from `FastObsidianMobile.xcodeproj`.

## Current Features

- Pick a local vault folder with the iOS folder picker.
- Persist folder access with a security-scoped bookmark.
- Scan Markdown and text notes while ignoring `.obsidian/`, `.trash/`, `.git/`, `node_modules/`, and common attachment folders.
- Show recent notes, notes edited today, notes edited this week, and daily notes.
- Search indexed note contents with a local SQLite FTS index.
- Render a restrained subset of Markdown before switching into raw edit mode.
- Autosave plain Markdown edits back to the selected local file.
- Create a new Markdown note in the selected vault root.
- Append quick captures to `Inbox.md` or `Daily/yyyy-MM-dd.md`.

## Non-Goals

This MVP deliberately does not implement Obsidian plugins, Dataview, graph view, Canvas, a full backlinks engine, custom theme compatibility, or its own sync service.

## Requirements

- macOS with Xcode and iOS Simulator support.
- iOS 17+ simulator or device.

There are no third-party package dependencies. The search index uses the system SQLite library.

## Build

```sh
xcodebuild \
  -project FastObsidianMobile.xcodeproj \
  -scheme FastObsidianMobile \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/FastObsidianMobileDerivedData \
  build
```

For device or App Store distribution, replace the example bundle identifier and select your own Apple development team in Xcode.

## Test Vault

To create sample notes in a simulator's local Files storage:

```sh
sh scripts/create_sim_vault.sh
```

Then run the app, choose a vault folder, and select the generated `TestVault` folder from the simulator's local Files location.

## Project Docs

- [Design doc](docs/design_doc.md)
- [Style guide](docs/style_guide.md)
- [Dev ops runbook](docs/dev_ops.md)
- [Iteration 02 requirements](docs/iteration_02.md)

The visual direction is Editorial Minimal: warm cream backgrounds, soft black text, graphite metadata, warm gray dividers, and muted stone accents.

## File Safety

The app reads and writes only files exposed by the selected local folder permission. It does not edit `.obsidian/` internals and does not provide sync. Keep your own vault backup or sync provider in place before testing with important notes.

Do not include real vault contents, private note names, or personal screenshots in public issues, pull requests, or documentation.

## License

MIT. See [LICENSE](LICENSE).
