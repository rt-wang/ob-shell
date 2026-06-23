import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var theme: ThemeSettings
    @State private var navigationPath: [Note.ID] = []
    @State private var isShowingVaultPicker = false
    @State private var isShowingDirectory = false
    @State private var isShowingNewNote = false
    @State private var isShowingSettings = false
    @State private var pendingCreatedNoteID: Note.ID?
    @State private var expandedFolders: Set<String> = []
    @State private var searchQuery = ""
    @State private var searchHits: [SearchHit] = []
    @FocusState private var isEditingGreeting: Bool

    /// Character cap that keeps the greeting within two lines of the display font at the home
    /// screen's width. Editing enforces this alongside a one-line-break limit.
    private static let greetingCharLimit = 44

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        !trimmedQuery.isEmpty
    }

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack(path: $navigationPath) {
                homeContent
            }

            if isShowingDirectory {
                directoryOverlay
            }
        }
        // Re-identify the content when the selected font changes so every surface
        // rebuilds with the new typeface. The Settings sheet is attached after this
        // and keyed on HomeView state, so it stays open across the rebuild.
        .id(theme.fontFamily)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isShowingDirectory)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(vault)
                .environmentObject(theme)
        }
    }

    private var homeContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                header

                if vault.hasVault {
                    if vault.notes.isEmpty {
                        EmptyVaultView(refreshAction: vault.refreshIndex)
                    } else {
                        SearchBar(query: $searchQuery)

                        if isSearchActive {
                            SearchResultsSection(query: trimmedQuery, hits: searchHits)
                        } else {
                            NoteSection(title: "Recent Notes", notes: vault.recentNotes)
                            NoteSection(title: "Edited Today", notes: vault.editedToday)
                            NoteSection(title: "Edited This Week", notes: vault.editedThisWeek)
                            NoteSection(title: "Daily Notes", notes: vault.dailyNotes)
                        }
                    }
                } else {
                    ChooseVaultView {
                        isShowingVaultPicker = true
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 40)
            // A tap on empty content (outside the greeting field and any row) ends greeting
            // editing. This lives on a background layer so it never overlaps the note rows or
            // the greeting field — keeping it off the rows means it can't fight their
            // NavigationLink taps or stall the ScrollView's vertical pan on touch-down.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditingGreeting = false
                    }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .task(id: searchQuery) {
            // Debounced search-as-you-type: rapid keystrokes cancel the prior task before the
            // sleep elapses, so only the settled query hits the index.
            guard isSearchActive else {
                searchHits = []
                return
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            searchHits = await vault.search(trimmedQuery)
        }
        .navigationDestination(for: Note.ID.self) { noteID in
            MarkdownEditorView(noteID: noteID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isShowingDirectory = true
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 17, weight: .medium))
                }
                .accessibilityLabel("Open Files")
            }

            if vault.hasVault {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vault.refreshIndex()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .accessibilityLabel("Refresh Index")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .medium))
                }
                .accessibilityLabel("New Note")
            }
        }
        .fullScreenCover(isPresented: $isShowingNewNote, onDismiss: openPendingCreatedNote) {
            NewNoteComposerView { noteID in
                pendingCreatedNoteID = noteID
            }
            .environmentObject(vault)
        }
        .fileImporter(
            isPresented: $isShowingVaultPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    vault.connect(to: url)
                    expandedFolders = []
                    isShowingDirectory = false
                }
            case .failure(let error):
                vault.errorMessage = "Could not choose vault: \(error.localizedDescription)"
            }
        }
        .alert("Vault Error", isPresented: errorBinding) {
            Button("OK") {
                vault.errorMessage = nil
            }
        } message: {
            Text(vault.errorMessage ?? "")
        }
        .editorialScreen()
    }

    private var directoryOverlay: some View {
        GeometryReader { proxy in
            let drawerWidth = min(proxy.size.width * 0.84, 370)

            ZStack(alignment: .leading) {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isShowingDirectory = false
                    }

                VaultDirectoryDrawer(
                    tree: vault.directoryTree,
                    vaultName: vault.vaultName,
                    hasVault: vault.hasVault,
                    selectedNoteID: navigationPath.last,
                    expandedFolders: $expandedFolders,
                    selectNote: { noteID in
                        navigationPath = [noteID]
                        isShowingDirectory = false
                    },
                    newNoteAction: showNewNote,
                    settingsAction: {
                        isShowingDirectory = false
                        isShowingSettings = true
                    },
                    closeAction: {
                        isShowingDirectory = false
                    }
                )
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Tap to edit; the field grows to at most two lines and collapses back to one when the
            // text is short. Characters and line breaks are capped so it never exceeds two lines.
            TextField("", text: $theme.greeting, axis: .vertical)
                .font(EditorialFont.display(29))
                .foregroundStyle(EditorialColor.primaryText)
                .lineSpacing(1)
                .lineLimit(1...2)
                .textInputAutocapitalization(.sentences)
                .focused($isEditingGreeting)
                .submitLabel(.done)
                .onChange(of: theme.greeting) { _, newValue in
                    let sanitized = sanitizedGreeting(newValue)
                    if sanitized != newValue {
                        theme.greeting = sanitized
                    }
                }
                .onChange(of: isEditingGreeting) { _, editing in
                    if !editing, theme.greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        theme.greeting = ThemeSettings.defaultGreeting
                    }
                }

            Text(headerSubtitle)
                .font(EditorialFont.ui(.body))
                .foregroundStyle(EditorialColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Constrains the greeting to two lines: collapses everything after the first line break into a
    /// single second line, then caps the total length.
    private func sanitizedGreeting(_ raw: String) -> String {
        let lines = raw.components(separatedBy: "\n")
        let collapsed: String
        if lines.count <= 1 {
            collapsed = raw
        } else {
            let rest = lines.dropFirst().joined(separator: " ")
            collapsed = lines[0] + "\n" + rest
        }
        return String(collapsed.prefix(Self.greetingCharLimit))
    }

    /// Vault, note count, and sync status condensed into the header subtitle, replacing the former
    /// boxed status strip.
    private var headerSubtitle: String {
        guard vault.hasVault else { return "Choose a vault to begin" }

        let notesText = vault.notes.count == 1 ? "1 note" : "\(vault.notes.count) notes"
        return "\(vault.vaultName) · \(notesText) · \(syncText)"
    }

    private var syncText: String {
        guard let refreshedAt = vault.lastRefreshAt else { return "not synced" }
        if abs(refreshedAt.timeIntervalSinceNow) < 60 { return "synced now" }
        return "synced \(VaultStore.modifiedString(for: refreshedAt))"
    }

    private func showNewNote() {
        guard vault.hasVault else {
            isShowingVaultPicker = true
            return
        }

        isShowingDirectory = false
        isShowingNewNote = true
    }

    private func openPendingCreatedNote() {
        guard let noteID = pendingCreatedNoteID else { return }
        pendingCreatedNoteID = nil
        navigationPath = [noteID]
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { vault.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    vault.errorMessage = nil
                }
            }
        )
    }
}

private struct NoteSection: View {
    let title: String
    let notes: [Note]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(EditorialFont.ui(.caption, weight: .semibold))
                .foregroundStyle(EditorialColor.secondaryText)
                .textCase(.uppercase)
                .tracking(1.9)

            if notes.isEmpty {
                Text("No notes here yet.")
                    .font(EditorialFont.ui(.subheadline))
                    .foregroundStyle(EditorialColor.mutedText)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(notes) { note in
                        NavigationLink(value: note.id) {
                            NoteRow(note: note)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(note.title)
                    .font(EditorialFont.display(22, weight: .semibold))
                    .foregroundStyle(EditorialColor.primaryText)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(VaultStore.modifiedString(for: note.modifiedAt))
                    .font(EditorialFont.ui(.caption))
                    .foregroundStyle(EditorialColor.mutedText)
                    .lineLimit(1)
            }

            Text(note.preview)
                .font(EditorialFont.ui(.callout))
                .foregroundStyle(EditorialColor.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(note.relativePath)
                .font(EditorialFont.ui(.caption))
                .foregroundStyle(EditorialColor.mutedText)
                .lineLimit(1)
        }
        .padding(.vertical, 21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Hairline()
                .opacity(0.65)
        }
    }
}

private struct SearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(EditorialColor.mutedText)

            TextField("Search notes", text: $query)
                .font(EditorialFont.ui(.body))
                .foregroundStyle(EditorialColor.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(EditorialColor.mutedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(EditorialColor.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(EditorialColor.divider, lineWidth: 0.75)
        }
    }
}

private struct SearchResultsSection: View {
    let query: String
    let hits: [SearchHit]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(headerText)
                .font(EditorialFont.ui(.caption, weight: .semibold))
                .foregroundStyle(EditorialColor.secondaryText)
                .textCase(.uppercase)
                .tracking(1.9)

            if hits.isEmpty {
                Text("No matches for \u{201C}\(query)\u{201D}.")
                    .font(EditorialFont.ui(.subheadline))
                    .foregroundStyle(EditorialColor.mutedText)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(hits) { hit in
                        NavigationLink(value: hit.path) {
                            SearchResultRow(hit: hit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var headerText: String {
        guard !hits.isEmpty else { return "Search" }
        return hits.count == 1 ? "1 Result" : "\(hits.count) Results"
    }
}

private struct SearchResultRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(highlighted(hit.titleSnippet.isEmpty ? hit.title : hit.titleSnippet))
                .font(EditorialFont.display(22, weight: .semibold))
                .foregroundStyle(EditorialColor.primaryText)
                .lineLimit(2)

            if !strippedBody.isEmpty {
                Text(highlighted(hit.bodySnippet))
                    .font(EditorialFont.ui(.callout))
                    .foregroundStyle(EditorialColor.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(relativePath)
                .font(EditorialFont.ui(.caption))
                .foregroundStyle(EditorialColor.mutedText)
                .lineLimit(1)
        }
        .padding(.vertical, 21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Hairline()
                .opacity(0.65)
        }
    }

    /// The note's vault-relative path (`folder/filename`), falling back to the filename if the
    /// hit wasn't matched to an in-memory note.
    private var relativePath: String {
        hit.relativePath.isEmpty ? (hit.path as NSString).lastPathComponent : hit.relativePath
    }

    private var strippedBody: String {
        hit.bodySnippet
            .replacingOccurrences(of: SearchIndex.highlightOpen, with: "")
            .replacingOccurrences(of: SearchIndex.highlightClose, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Turns an FTS5 snippet (matched terms wrapped in highlight sentinels) into an attributed
    /// string where matches are emphasized with the accent color.
    private func highlighted(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var buffer = ""
        var isMatch = false

        func flush() {
            guard !buffer.isEmpty else { return }
            var run = AttributedString(buffer)
            if isMatch {
                run.foregroundColor = EditorialColor.mutedAccent
                run.inlinePresentationIntent = .stronglyEmphasized
            }
            result.append(run)
            buffer = ""
        }

        for character in snippet {
            switch character {
            case Character(SearchIndex.highlightOpen):
                flush()
                isMatch = true
            case Character(SearchIndex.highlightClose):
                flush()
                isMatch = false
            default:
                buffer.append(character)
            }
        }
        flush()
        return result
    }
}

private struct VaultDirectoryDrawer: View {
    let tree: VaultDirectoryNode
    let vaultName: String
    let hasVault: Bool
    let selectedNoteID: Note.ID?
    @Binding var expandedFolders: Set<String>
    let selectNote: (Note.ID) -> Void
    let newNoteAction: () -> Void
    let settingsAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(EditorialColor.primaryText)

                Text("Files")
                    .font(EditorialFont.display(23, weight: .semibold))
                    .foregroundStyle(EditorialColor.primaryText)

                Spacer()

                Button(action: closeAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(EditorialColor.secondaryText)
                .accessibilityLabel("Close Files")
            }
            .padding(.horizontal, 28)

            ScrollView {
                if hasVault {
                    DirectoryNodeList(
                        node: tree,
                        depth: 0,
                        selectedNoteID: selectedNoteID,
                        expandedFolders: $expandedFolders,
                        selectNote: selectNote
                    )
                    .padding(.horizontal, 22)
                } else {
                    Text("Choose a vault folder to show files.")
                        .font(EditorialFont.ui(.body))
                        .foregroundStyle(EditorialColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                }
            }
            .scrollIndicators(.hidden)

            drawerActions
                .padding(.horizontal, 28)

            drawerFooter
                .padding(.horizontal, 28)
        }
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Content sits inside the safe area (set by the overlay); only the panel
        // background bleeds behind the status bar and home indicator.
        .background(EditorialColor.background.ignoresSafeArea())
        .shadow(color: .black.opacity(0.18), radius: 26, x: 8, y: 0)
    }

    private var drawerActions: some View {
        HStack(spacing: 22) {
            iconButton(systemName: "square.and.pencil", label: "New Note", action: newNoteAction)
            Spacer(minLength: 0)
        }
        .font(.system(size: 22, weight: .regular))
        .foregroundStyle(EditorialColor.secondaryText)
    }

    private var drawerFooter: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(hasVault ? vaultName : "No vault")
                    .font(EditorialFont.display(22, weight: .semibold))
                    .foregroundStyle(EditorialColor.primaryText)
                    .lineLimit(1)

                Text(summaryText)
                    .font(EditorialFont.ui(.caption))
                    .foregroundStyle(EditorialColor.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: settingsAction) {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(EditorialColor.surface))
            }
            .buttonStyle(.plain)
            .foregroundStyle(EditorialColor.primaryText)
            .accessibilityLabel("Settings")
        }
    }

    private var summaryText: String {
        guard hasVault else {
            return "Choose a folder"
        }

        let noteText = tree.noteCount == 1 ? "1 file" : "\(tree.noteCount) files"
        let folderText = tree.folderCount == 1 ? "1 folder" : "\(tree.folderCount) folders"
        return "\(noteText), \(folderText)"
    }

    private func iconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var theme: ThemeSettings
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingVaultPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: $theme.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose a light or dark palette, or follow the system setting.")
                }

                Section {
                    ForEach(SurfaceFont.allCases) { font in
                        Button {
                            theme.fontFamily = font
                        } label: {
                            HStack {
                                Text(font.displayName)
                                    .font(font.font(textStyle: .body, weight: .regular))
                                    .foregroundStyle(EditorialColor.primaryText)

                                Spacer()

                                if theme.fontFamily == font {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(EditorialColor.mutedAccent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Font")
                } footer: {
                    Text("Applies to all surface text across the app.")
                }

                Section {
                    Button {
                        isShowingVaultPicker = true
                    } label: {
                        HStack {
                            Text("Change Vault")
                                .foregroundStyle(EditorialColor.primaryText)
                            Spacer()
                            Text(vault.vaultName)
                                .foregroundStyle(EditorialColor.mutedText)
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text("Vault")
                }
            }
            .scrollContentBackground(.hidden)
            .background(EditorialColor.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(EditorialColor.primaryText)
        .fileImporter(
            isPresented: $isShowingVaultPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    vault.connect(to: url)
                }
            case .failure(let error):
                vault.errorMessage = "Could not choose vault: \(error.localizedDescription)"
            }
            dismiss()
        }
    }
}

private struct DirectoryNodeList: View {
    let node: VaultDirectoryNode
    let depth: Int
    let selectedNoteID: Note.ID?
    @Binding var expandedFolders: Set<String>
    let selectNote: (Note.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(node.children) { child in
                DirectoryFolderRow(
                    node: child,
                    depth: depth,
                    selectedNoteID: selectedNoteID,
                    expandedFolders: $expandedFolders,
                    selectNote: selectNote
                )
            }

            ForEach(node.notes) { note in
                DirectoryNoteRow(
                    note: note,
                    depth: depth,
                    isSelected: selectedNoteID == note.id,
                    selectNote: selectNote
                )
            }
        }
    }
}

private struct DirectoryFolderRow: View {
    let node: VaultDirectoryNode
    let depth: Int
    let selectedNoteID: Note.ID?
    @Binding var expandedFolders: Set<String>
    let selectNote: (Note.ID) -> Void

    private var isExpanded: Bool {
        expandedFolders.contains(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EditorialColor.mutedText)
                        .frame(width: 14)

                    Text(node.name)
                        .font(EditorialFont.ui(.body, weight: .semibold))
                        .foregroundStyle(EditorialColor.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(node.noteCount)")
                        .font(EditorialFont.ui(.caption))
                        .foregroundStyle(EditorialColor.mutedText)
                }
                .padding(.leading, CGFloat(depth) * 18)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                DirectoryNodeList(
                    node: node,
                    depth: depth + 1,
                    selectedNoteID: selectedNoteID,
                    expandedFolders: $expandedFolders,
                    selectNote: selectNote
                )
            }
        }
    }

    private func toggle() {
        if isExpanded {
            expandedFolders.remove(node.id)
        } else {
            expandedFolders.insert(node.id)
        }
    }
}

private struct DirectoryNoteRow: View {
    let note: Note
    let depth: Int
    let isSelected: Bool
    let selectNote: (Note.ID) -> Void

    var body: some View {
        Button {
            selectNote(note.id)
        } label: {
            HStack(spacing: 9) {
                Text(noteName)
                    .font(EditorialFont.ui(.callout, weight: .medium))
                    .foregroundStyle(EditorialColor.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.leading, CGFloat(depth) * 18 + 31)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule()
                        .fill(EditorialColor.surface)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var noteName: String {
        let ext = (note.filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, VaultStore.recognizedNoteExtensions.contains(ext) else {
            return note.filename
        }
        return String(note.filename.dropLast(ext.count + 1))
    }
}

private struct NewNoteComposerView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Note.ID) -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var createError: String?

    private var canSave: Bool {
        vault.hasVault && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Filename", text: $title, axis: .vertical)
                    .font(EditorialFont.display(32, weight: .semibold))
                    .foregroundStyle(EditorialColor.primaryText)
                    .textInputAutocapitalization(.sentences)
                    .lineLimit(1...3)

                Text("\(filenamePreview).md")
                    .font(EditorialFont.ui(.caption))
                    .foregroundStyle(EditorialColor.mutedText)
                    .lineLimit(1)

                Hairline()
                    .opacity(0.65)

                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("Start writing...")
                            .font(EditorialFont.markdown(.body))
                            .foregroundStyle(EditorialColor.mutedText)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }

                    TextEditor(text: $bodyText)
                        .font(EditorialFont.markdown(.body))
                        .foregroundStyle(EditorialColor.primaryText)
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .background(EditorialColor.background)
                        .padding(.horizontal, -5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(EditorialFont.ui(.subheadline, weight: .medium))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(EditorialFont.ui(.subheadline, weight: .semibold))
                    .disabled(!canSave)
                }
            }
            .alert("Create Note Error", isPresented: errorBinding) {
                Button("OK") {
                    createError = nil
                }
            } message: {
                Text(createError ?? "")
            }
            .editorialScreen()
        }
    }

    private func save() {
        do {
            let noteID = try vault.createNote(title: title, body: bodyText)
            dismiss()
            onCreated(noteID)
        } catch {
            createError = error.localizedDescription
        }
    }

    private var filenamePreview: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "Untitled"
        }

        if trimmedTitle.lowercased().hasSuffix(".md") {
            return String(trimmedTitle.dropLast(3))
        }

        return trimmedTitle
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { createError != nil },
            set: { isPresented in
                if !isPresented {
                    createError = nil
                }
            }
        )
    }
}

private struct ChooseVaultView: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open an existing Obsidian vault folder to render recent Markdown notes.")
                .font(EditorialFont.display(23))
                .foregroundStyle(EditorialColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Label("Choose Vault Folder", systemImage: "folder")
                    .font(EditorialFont.ui(.body, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(EditorialColor.darkOverlay)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyVaultView: View {
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No Markdown notes found.")
                .font(EditorialFont.display(23))
                .foregroundStyle(EditorialColor.primaryText)

            Text("This pass scans nested `.md` files and skips Obsidian internals plus common attachment folders.")
                .font(EditorialFont.ui(.subheadline))
                .foregroundStyle(EditorialColor.secondaryText)

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(EditorialFont.ui(.body, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(EditorialColor.primaryText)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
