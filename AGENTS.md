# Agent Instructions

## Product context

This project is a fast, lightweight mobile companion for an Obsidian vault. It should feel instant, local-first, minimal, and safe for plain Markdown editing.

Before doing frontend, product, or architecture work, read:

- `docs/design_doc.md`
- `docs/style_guide.md`

Treat these as source-of-truth constraints unless the user explicitly overrides them.

## Design rules

Follow the Editorial Minimal direction from `docs/style_guide.md`.

Use:
- Warm cream backgrounds
- Soft black primary text
- Graphite gray secondary text
- Warm gray dividers
- Muted stone/beige accents only
- Editorial serif for major display moments
- Neutral sans-serif for functional UI
- Monospace only for code or raw Markdown editing

Avoid:
- Bright saturated colors
- Purple/blue accent colors unless explicitly requested
- Oversized mobile typography
- Crowded status bars
- Heavy card shadows
- Plugin-like Obsidian complexity in the MVP

## Product rules

Prioritize:
- Fast launch
- Recent notes
- Markdown editing
- Quick capture
- File safety
- Conflict detection

Do not implement:
- Obsidian plugins
- Dataview
- Graph view
- Canvas
- Full backlinks engine
- Custom theme compatibility

## Working rules

When implementing a feature:
1. Read the relevant docs first.
2. Make a short plan.
3. Implement the smallest useful version.
4. Keep the UI consistent with `docs/style_guide.md`.
5. Run available build, lint, and test commands.
6. Summarize changed files and verification steps.
