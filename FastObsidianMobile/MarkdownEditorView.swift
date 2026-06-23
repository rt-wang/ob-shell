import SwiftUI

struct MarkdownEditorView: View {
    @EnvironmentObject private var vault: VaultStore

    let noteID: Note.ID

    @State private var draft = ""
    @State private var originalDraft = ""
    @State private var loadedNoteID: Note.ID?
    @State private var loadingNoteID: Note.ID?
    @State private var isEditing = false
    @State private var editorError: String?
    @State private var autosaveTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

    private var note: Note? {
        vault.note(with: noteID)
    }

    private var hasChanges: Bool {
        draft != originalDraft
    }

    var body: some View {
        Group {
            if let note {
                VStack(alignment: .leading, spacing: 0) {
                    editorHeader(for: note)

                    if loadedNoteID != note.id {
                        NoteLoadingView(isLoading: loadingNoteID == note.id)
                    } else if isEditing {
                        rawEditor
                    } else {
                        renderedReader
                    }
                }
                .task(id: note.id) {
                    await load(note)
                }
                .onChange(of: draft) { _, _ in
                    scheduleAutosave()
                }
                .onDisappear {
                    flushSave()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if isEditing {
                            Text(hasChanges ? "Saving…" : "Saved")
                                .font(EditorialFont.ui(.caption, weight: .medium))
                                .foregroundStyle(EditorialColor.mutedText)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if isEditing {
                            Button("Done") {
                                endEditing()
                            }
                            .font(EditorialFont.ui(.subheadline, weight: .semibold))
                        } else if loadedNoteID == note.id {
                            ShareLink(
                                item: draft,
                                subject: Text(note.title),
                                message: Text(note.title)
                            ) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .alert("Note Error", isPresented: errorBinding) {
                    Button("OK") {
                        editorError = nil
                    }
                } message: {
                    Text(editorError ?? "")
                }
                .editorialScreen()
            } else {
                ContentUnavailableView("Note unavailable", systemImage: "doc.text")
                    .editorialScreen()
            }
        }
    }

    private var renderedReader: some View {
        ScrollView {
            RenderedMarkdownView(markdown: draft)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    beginEditing()
                }
        }
        .scrollIndicators(.hidden)
    }

    private var rawEditor: some View {
        TextEditor(text: $draft)
            .font(EditorialFont.ui(.body))
            .foregroundStyle(EditorialColor.primaryText)
            .lineSpacing(6)
            .tint(EditorialColor.primaryText)
            .focused($editorFocused)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .scrollContentBackground(.hidden)
            .background(EditorialColor.background)
    }

    private func editorHeader(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(note.title)
                    .font(EditorialFont.ui(.body, weight: .medium))
                    .foregroundStyle(EditorialColor.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 10)

                Text(note.folder.isEmpty ? "Root" : note.folder)
                    .font(EditorialFont.ui(.caption))
                    .foregroundStyle(EditorialColor.mutedText)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Label(VaultStore.modifiedString(for: note.modifiedAt), systemImage: "clock")
                Text("\(note.sizeBytes) bytes")
                Label("No external changes", systemImage: "checkmark.circle")
            }
            .font(EditorialFont.ui(.caption))
            .foregroundStyle(EditorialColor.secondaryText)

            Hairline()
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    @MainActor
    private func load(_ note: Note) async {
        let targetID = note.id
        guard loadedNoteID != targetID, loadingNoteID != targetID else { return }

        loadingNoteID = targetID
        editorError = nil
        isEditing = false
        defer {
            if loadingNoteID == targetID {
                loadingNoteID = nil
            }
        }

        do {
            let content = try await vault.loadContent(for: targetID)
            guard !Task.isCancelled, loadingNoteID == targetID else { return }
            draft = content
            originalDraft = content
            loadedNoteID = targetID
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, loadingNoteID == targetID else { return }
            editorError = error.localizedDescription
        }
    }

    private func beginEditing() {
        isEditing = true
        editorFocused = true
    }

    private func endEditing() {
        editorFocused = false
        isEditing = false
        flushSave()
    }

    /// Debounced autosave: persists shortly after the user stops typing.
    private func scheduleAutosave() {
        guard isEditing else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveIfNeeded()
        }
    }

    /// Saves immediately (e.g. on Done or when leaving the note).
    private func flushSave() {
        autosaveTask?.cancel()
        autosaveTask = nil
        saveIfNeeded()
    }

    private func saveIfNeeded() {
        guard draft != originalDraft else { return }
        do {
            try vault.save(noteID: noteID, content: draft)
            originalDraft = draft
        } catch {
            editorError = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { editorError != nil },
            set: { isPresented in
                if !isPresented {
                    editorError = nil
                }
            }
        )
    }
}

private struct NoteLoadingView: View {
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(EditorialColor.secondaryText)
            }

            Text(isLoading ? "Loading note..." : "Could not load note.")
                .font(EditorialFont.ui(.subheadline))
                .foregroundStyle(EditorialColor.mutedText)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EditorialColor.background)
    }
}

private struct RenderedMarkdownView: View {
    let markdown: String

    private var lines: [String] {
        markdown.components(separatedBy: .newlines)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MarkdownLineView(line: line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownLineView: View {
    let line: String

    private var trimmed: String {
        line.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                Spacer()
                    .frame(height: 10)
            } else if let heading = heading(level: 1) {
                inlineText(heading, font: EditorialFont.display(30))
                    .foregroundStyle(EditorialColor.primaryText)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            } else if let heading = heading(level: 2) {
                inlineText(heading, font: EditorialFont.display(22))
                    .foregroundStyle(EditorialColor.primaryText)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            } else if let heading = heading(level: 3) {
                inlineText(heading, font: EditorialFont.ui(.headline, weight: .semibold))
                    .foregroundStyle(EditorialColor.primaryText)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            } else if let listItem = unorderedListItem {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("-")
                        .font(EditorialFont.ui(.body))
                        .foregroundStyle(EditorialColor.mutedText)

                    inlineText(listItem, font: EditorialFont.ui(.body))
                        .foregroundStyle(EditorialColor.secondaryText)
                }
                .padding(.leading, 8)
                .padding(.bottom, 5)
            } else if let orderedItem = orderedListItem {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(orderedItem.prefix)
                        .font(EditorialFont.ui(.body))
                        .foregroundStyle(EditorialColor.mutedText)

                    inlineText(orderedItem.text, font: EditorialFont.ui(.body))
                        .foregroundStyle(EditorialColor.secondaryText)
                }
                .padding(.leading, 8)
                .padding(.bottom, 5)
            } else {
                inlineText(trimmed, font: EditorialFont.ui(.body))
                    .foregroundStyle(EditorialColor.secondaryText)
                    .lineSpacing(4)
                    .padding(.bottom, 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(level: Int) -> String? {
        let marker = String(repeating: "#", count: level) + " "
        guard trimmed.hasPrefix(marker) else { return nil }
        return String(trimmed.dropFirst(marker.count))
    }

    private var unorderedListItem: String? {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2))
        }
        return nil
    }

    private var orderedListItem: (prefix: String, text: String)? {
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let prefix = String(trimmed[...dotIndex])
        guard prefix.dropLast().allSatisfy(\.isNumber) else { return nil }
        let textStart = trimmed.index(after: dotIndex)
        let text = trimmed[textStart...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (prefix, text)
    }

    private func inlineText(_ value: String, font: Font) -> Text {
        var result = Text("")
        var index = value.startIndex

        while index < value.endIndex {
            if let segment = styledSegment(startingAt: index, in: value, font: font) {
                result = result + segment.text
                index = segment.endIndex
                continue
            }

            if let nextRange = nextMarkerRange(after: index, in: value) {
                if nextRange.lowerBound == index {
                    result = result + Text(String(value[nextRange])).font(font)
                    index = nextRange.upperBound
                } else {
                    result = result + Text(String(value[index..<nextRange.lowerBound])).font(font)
                    index = nextRange.lowerBound
                }
            } else {
                result = result + Text(String(value[index...])).font(font)
                break
            }
        }

        return result
    }

    private func styledSegment(startingAt index: String.Index, in value: String, font: Font) -> (text: Text, endIndex: String.Index)? {
        if value[index...].hasPrefix("**") {
            return pairedSegment(open: "**", close: "**", style: { $0.font(font).bold() }, startingAt: index, in: value)
        }

        if value[index...].hasPrefix("__") {
            return pairedSegment(open: "__", close: "__", style: { $0.font(font).underline() }, startingAt: index, in: value)
        }

        if value[index...].hasPrefix("_") {
            return pairedSegment(open: "_", close: "_", style: { $0.font(font).italic() }, startingAt: index, in: value)
        }

        if value[index...].hasPrefix("<u>") {
            return pairedSegment(open: "<u>", close: "</u>", style: { $0.font(font).underline() }, startingAt: index, in: value)
        }

        if value[index...].hasPrefix("`") {
            return pairedSegment(open: "`", close: "`", style: { $0.font(EditorialFont.markdown(.callout)) }, startingAt: index, in: value)
        }

        if value[index...].hasPrefix("*") {
            return pairedSegment(open: "*", close: "*", style: { $0.font(font).italic() }, startingAt: index, in: value)
        }

        return nil
    }

    private func pairedSegment(
        open: String,
        close: String,
        style: (Text) -> Text,
        startingAt index: String.Index,
        in value: String
    ) -> (text: Text, endIndex: String.Index)? {
        let contentStart = value.index(index, offsetBy: open.count)
        guard let closeRange = value.range(of: close, range: contentStart..<value.endIndex) else {
            return nil
        }

        let content = String(value[contentStart..<closeRange.lowerBound])
        return (style(Text(content)), closeRange.upperBound)
    }

    private func nextMarkerRange(after index: String.Index, in value: String) -> Range<String.Index>? {
        let markers = ["**", "__", "_", "<u>", "`", "*"]
        return markers
            .compactMap { marker in value.range(of: marker, range: index..<value.endIndex) }
            .min { $0.lowerBound < $1.lowerBound }
    }
}
