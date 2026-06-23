# Contributing

Thanks for helping improve Fast Obsidian Mobile.

## Product Boundaries

Before proposing product, UI, or architecture changes, read:

- [docs/design_doc.md](docs/design_doc.md)
- [docs/style_guide.md](docs/style_guide.md)

Keep the MVP focused on fast launch, recent notes, plain Markdown editing, quick capture, file safety, and conflict detection. Do not add Obsidian plugins, Dataview, graph view, Canvas, a full backlinks engine, custom theme compatibility, or a sync service.

## Development Setup

Build with:

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

Create a simulator test vault with:

```sh
sh scripts/create_sim_vault.sh
```

## Pull Requests

- Keep changes small and scoped.
- Match the Editorial Minimal style guide.
- Avoid screenshots or fixtures from real private vaults.
- Run the simulator build before opening a pull request.
- Mention any checks that could not be run.
