# Fast Obsidian Mobile Dev Ops

This is the local runbook for building and running the SwiftUI iOS prototype.

## Project

```text
Project: FastObsidianMobile.xcodeproj
Scheme: FastObsidianMobile
Bundle ID: com.example.FastObsidianMobile
Minimum iOS: 17.0
Default DerivedData: /tmp/FastObsidianMobileDerivedData
```

The current prototype connects to a user-picked local vault folder, scans Markdown and text notes, renders notes in read mode, and writes edited Markdown back to disk. It does not implement a sync provider, graph engine, plugin system, Dataview, Canvas, or share extension.

## Prerequisites

Install Xcode with iOS Simulator support, then confirm the toolchain is available:

```sh
xcodebuild -version
xcrun simctl list devices available
```

If Xcode was recently installed or updated, open Xcode once and accept any license or component-install prompts before using CLI commands.

## Build From CLI

The simulator build does not require an Apple development team:

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

For install-and-run workflows, choose a simulator ID from `xcrun simctl list devices available` and set:

```sh
DEVICE_ID=<simulator-uuid>
BUNDLE_ID=com.example.FastObsidianMobile
DERIVED_DATA=/tmp/FastObsidianMobileDerivedData
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/FastObsidianMobile.app"
```

Then boot, install, and launch:

```sh
xcrun simctl boot "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
```

## Run From Xcode

```sh
open FastObsidianMobile.xcodeproj
```

In Xcode:

1. Select the `FastObsidianMobile` scheme.
2. Select an iPhone simulator.
3. Press `Cmd+R`.

For a physical device or App Store distribution, change the bundle identifier and select your own Apple development team in Xcode.

## Create A Simulator Test Vault

Create or refresh a local Markdown vault inside the simulator's Files storage:

```sh
sh scripts/create_sim_vault.sh
```

The script first uses a booted iPhone simulator, then falls back to the first available iPhone simulator. Override the target simulator or vault name when needed:

```sh
DEVICE_ID=<simulator-uuid> sh scripts/create_sim_vault.sh
VAULT_NAME=AnotherVault sh scripts/create_sim_vault.sh
```

Reset the generated vault before recreating it:

```sh
RESET=1 sh scripts/create_sim_vault.sh
```

The script writes sample `.md` files plus ignored test files under `.obsidian/` and `attachments/`. After running it, open the app, tap the folder icon, choose `Browse`, then select `TestVault` from the simulator's local Files location.

## Verification Checks

Before handing off changes, run the simulator build command above.

Confirm the MVP scope did not grow:

```sh
rg -n "graph|backlink|canvas|plugin|dataview|theme compatibility|share extension|sync service|custom theme" FastObsidianMobile
```

Confirm the Editorial Minimal style remains centralized:

```sh
rg -n "0xF7F3EC|0xEFE8DC|0x151412|0x5F5A52|0x958E82|0xE4DCCF|0x8A6F4D|display\\(|ui\\(|markdown\\(" FastObsidianMobile
```

Expected behavior in the simulator:

```text
Home screen asks for a vault if none has been selected.
Top-left folder icon opens the in-app Files drawer.
The Files drawer shows the scanned vault directory tree.
The Files drawer gear icon opens settings, where the vault can be changed.
Home screen shows Recent Notes, Edited Today, Edited This Week, and Daily Notes from actual note files.
Tapping a note opens the Markdown editor.
Rendered Markdown is shown first.
Edit mode shows raw Markdown and autosaves after changes.
Top-right compose opens a full-screen new note composer.
New notes save to the selected vault root by default.
Quick Capture appends to Inbox.md or today's Daily Note in the selected vault.
```

## Troubleshooting

If `xcodebuild` cannot find the device:

```sh
xcrun simctl list devices available
```

Update `DEVICE_ID` to a currently available simulator ID, or use Xcode's destination picker.

If install fails because the app is running:

```sh
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
```

If the app launches to an old build:

```sh
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" || true
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" || true
rm -rf "$DERIVED_DATA"
```

Then rebuild, install, and launch again.

## Operating Boundaries

Keep this prototype inside the MVP surface:

```text
Allowed:
- Home / recent notes
- Plain Markdown editor
- Quick capture to Inbox or Daily Note
- Cached-index status and manual refresh
- Basic external-change status UI

Not allowed in this prototype:
- Graph view
- Backlinks graph
- Canvas
- Obsidian plugin support
- Dataview execution
- Custom theme compatibility
- Sync service
```
