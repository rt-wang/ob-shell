import Foundation

struct Note: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let url: URL
    var filename: String
    var folder: String
    var title: String
    var preview: String
    var modifiedAt: Date
    var sizeBytes: Int
    var isDailyNote: Bool
    var isInbox: Bool

    var relativePath: String {
        folder.isEmpty ? filename : "\(folder)/\(filename)"
    }
}

enum CaptureDestination: String, CaseIterable, Identifiable, Sendable {
    case inbox = "Inbox"
    case daily = "Daily Note"

    var id: String { rawValue }
}

struct VaultDirectoryNode: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var relativePath: String
    var notes: [Note]
    var children: [VaultDirectoryNode]

    var noteCount: Int {
        notes.count + children.reduce(0) { $0 + $1.noteCount }
    }

    var folderCount: Int {
        children.count + children.reduce(0) { $0 + $1.folderCount }
    }

    static func root(named name: String) -> VaultDirectoryNode {
        VaultDirectoryNode(id: "__root__", name: name, relativePath: "", notes: [], children: [])
    }
}

private struct NoteMetadataCache: Codable {
    let vaultPath: String
    let vaultName: String
    let refreshedAt: Date
    let notes: [Note]
}

@MainActor
final class VaultStore: ObservableObject {
    /// `notes` is kept sorted by recency. The collections below are derived once whenever
    /// `notes` changes (see `setNotes`) instead of being recomputed on every SwiftUI pass.
    @Published private(set) var notes: [Note] = []
    @Published private(set) var recentNotes: [Note] = []
    @Published private(set) var editedToday: [Note] = []
    @Published private(set) var editedThisWeek: [Note] = []
    @Published private(set) var dailyNotes: [Note] = []
    @Published private(set) var directoryTree: VaultDirectoryNode = .root(named: "No vault selected")
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var vaultURL: URL?
    @Published private(set) var vaultName = "No vault selected"
    @Published var errorMessage: String?

    private let bookmarkKey = "FastObsidianMobile.vaultBookmark"
    private let noteMetadataCacheKey = "FastObsidianMobile.noteMetadataCache.v1"
    private var indexTask: Task<Void, Never>?

    /// Persistent full-text index over note bodies, kept in sync with `notes`.
    private let searchIndex = SearchIndex()

    /// Maximum bytes read from a file to build its one-line preview during indexing.
    nonisolated private static let previewByteLimit = 4096
    nonisolated private static let homeSectionNoteLimit = 40
    nonisolated private static let ignoredDirectoryNames: Set<String> = [
        ".obsidian",
        ".trash",
        ".git",
        "node_modules",
        "attachments",
        "attachment",
        "assets",
        "images",
        "img",
        "media",
        "files"
    ]

    /// File extensions treated as notes when scanning a vault.
    nonisolated static let recognizedNoteExtensions: Set<String> = ["md", "txt"]

    var hasVault: Bool {
        vaultURL != nil
    }

    init() {
        restoreVaultBookmark()
    }

    func connect(to url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            vaultURL = url
            vaultName = url.lastPathComponent
            errorMessage = nil
            loadCachedNotes(for: url)
            refreshIndex()
        } catch {
            errorMessage = "Could not store vault access: \(error.localizedDescription)"
        }
    }

    /// Scans the vault on a background executor and publishes the result on the main actor, so the
    /// UI (and app launch) is never blocked by disk I/O proportional to vault size.
    func refreshIndex() {
        guard let vaultURL else {
            setNotes([])
            lastRefreshAt = nil
            return
        }

        let url = vaultURL
        vaultName = url.lastPathComponent
        indexTask?.cancel()
        indexTask = Task { [weak self] in
            let result: Result<[Note], Error> = await Task.detached(priority: .userInitiated) {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    return .success(try VaultStore.scanMarkdownFiles(in: url))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let scanned):
                self.setNotes(scanned)
                let refreshedAt = Date()
                self.lastRefreshAt = refreshedAt
                self.errorMessage = nil
                self.persistCachedNotes(scanned, for: url, refreshedAt: refreshedAt)
                self.reconcileSearchIndex(with: scanned, vaultURL: url)
            case .failure(let error):
                self.errorMessage = "Could not scan vault: \(error.localizedDescription)"
            }
        }
    }

    /// Brings the full-text index in line with the freshly scanned notes off the main actor. Only
    /// new or modified files are re-read (see `SearchIndex.reconcile`); a single security-scoped
    /// access is held around the whole pass.
    private func reconcileSearchIndex(with scanned: [Note], vaultURL url: URL) {
        let entries = scanned.map {
            IndexEntry(path: $0.id, title: $0.title, url: $0.url, mtime: $0.modifiedAt.timeIntervalSince1970)
        }
        let index = searchIndex
        Task.detached(priority: .utility) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            await index.reconcile(entries) { fileURL in
                try? String(contentsOf: fileURL, encoding: .utf8)
            }
        }
    }

    /// Fire-and-forget single-note index update from the mutation paths that already hold fresh
    /// content, so search stays current without a rescan or extra file read.
    private func indexUpsert(path: Note.ID, title: String, body: String, modifiedAt: Date) {
        let index = searchIndex
        Task.detached(priority: .utility) {
            await index.upsert(path: path, title: title, body: body, mtime: modifiedAt.timeIntervalSince1970)
        }
    }

    /// Runs a full-text search against the persistent index. Returns `[]` for blank queries.
    func search(_ query: String) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var hits = await searchIndex.search(trimmed)
        for index in hits.indices {
            if let note = note(with: hits[index].path) {
                hits[index].relativePath = note.relativePath
            }
        }
        return hits
    }

    /// Assigns `notes` (sorted by recency) and recomputes the cached derived collections once.
    private func setNotes(_ newNotes: [Note]) {
        let sorted = newNotes.sortedByRecency()
        notes = sorted

        let calendar = Calendar.current
        let now = Date()
        recentNotes = Array(sorted.prefix(Self.homeSectionNoteLimit))
        editedToday = Array(sorted.lazy.filter { calendar.isDateInToday($0.modifiedAt) }.prefix(Self.homeSectionNoteLimit))
        editedThisWeek = Array(sorted.lazy.filter { calendar.isDate($0.modifiedAt, equalTo: now, toGranularity: .weekOfYear) }.prefix(Self.homeSectionNoteLimit))
        dailyNotes = Array(sorted.lazy.filter(\.isDailyNote).prefix(Self.homeSectionNoteLimit))
        directoryTree = Self.directoryTree(from: sorted, vaultName: vaultName)
    }

    /// Re-stats a single file and updates just that note in `notes`, avoiding a full vault rescan
    /// after an edit/capture/create.
    private func upsertNote(at url: URL) {
        guard let rootURL = vaultURL else { return }

        let didAccess = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return }

        let updated = Self.makeNote(at: url, rootURL: rootURL, resourceValues: values)
        var newNotes = notes
        if let index = newNotes.firstIndex(where: { $0.id == updated.id }) {
            newNotes[index] = updated
        } else {
            newNotes.append(updated)
        }
        setNotes(newNotes)
        let updatedAt = Date()
        lastRefreshAt = updatedAt
        persistCachedNotes(notes, for: rootURL, refreshedAt: updatedAt)
    }

    func note(with id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    func loadContent(for noteID: Note.ID) async throws -> String {
        guard let note = note(with: noteID) else {
            throw VaultStoreError.noteNotFound
        }
        let noteURL = note.url
        let scopedURL = vaultURL
        return try await Task.detached(priority: .userInitiated) {
            try Self.readContent(at: noteURL, scopedTo: scopedURL)
        }.value
    }

    func save(noteID: Note.ID, content: String) throws {
        guard let note = note(with: noteID) else {
            throw VaultStoreError.noteNotFound
        }

        try write(content, to: note.url)
        upsertNote(at: note.url)
        if let updated = self.note(with: note.id) {
            indexUpsert(path: updated.id, title: updated.title, body: content, modifiedAt: updated.modifiedAt)
        }
    }

    func appendCapture(_ text: String, sourceURL: String, includeTimestamp: Bool, destination: CaptureDestination) throws {
        guard let vaultURL else {
            throw VaultStoreError.noVaultSelected
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let targetURL = try captureURL(for: destination, in: vaultURL)
        var block = "\n\n"
        if includeTimestamp {
            block += "## \(Self.timestampString(for: Date()))\n\n"
        }
        block += trimmedText

        let trimmedSource = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSource.isEmpty {
            block += "\n\nSource: \(trimmedSource)"
        }

        let existing = (try? readContent(at: targetURL)) ?? ""
        let newContent = existing + block
        try write(newContent, to: targetURL)
        upsertNote(at: targetURL)
        if let updated = self.note(with: targetURL.standardizedFileURL.path) {
            indexUpsert(path: updated.id, title: updated.title, body: newContent, modifiedAt: updated.modifiedAt)
        }
    }

    func createNote(title: String, body: String) throws -> Note.ID {
        guard let vaultURL else {
            throw VaultStoreError.noVaultSelected
        }

        let trimmedFilename = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            throw VaultStoreError.emptyNote
        }

        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }

        let filenameStem = Self.filenameStem(from: trimmedFilename)
        let targetURL = uniqueMarkdownURL(baseName: filenameStem, in: vaultURL)
        let content = Self.newNoteContent(body: body)

        try write(content, to: targetURL)
        upsertNote(at: targetURL)
        if let updated = self.note(with: targetURL.standardizedFileURL.path) {
            indexUpsert(path: updated.id, title: updated.title, body: content, modifiedAt: updated.modifiedAt)
        }

        return targetURL.standardizedFileURL.path
    }

    func captureRelativePath(for destination: CaptureDestination, date: Date = Date()) -> String {
        switch destination {
        case .inbox:
            return "Inbox.md"
        case .daily:
            return "Daily/\(Self.dailyFilename(for: date)).md"
        }
    }

    static func modifiedString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func timestampString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func restoreVaultBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else { return }

        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            vaultURL = resolvedURL
            vaultName = resolvedURL.lastPathComponent
            if isStale {
                connect(to: resolvedURL)
            } else {
                loadCachedNotes(for: resolvedURL)
                refreshIndex()
            }
        } catch {
            errorMessage = "Could not reopen vault: \(error.localizedDescription)"
        }
    }

    private func loadCachedNotes(for url: URL) {
        guard let cache = cachedNotes(for: url) else {
            setNotes([])
            lastRefreshAt = nil
            return
        }

        vaultName = cache.vaultName
        setNotes(cache.notes)
        lastRefreshAt = cache.refreshedAt
    }

    private func persistCachedNotes(_ notes: [Note], for url: URL, refreshedAt: Date) {
        let cache = NoteMetadataCache(
            vaultPath: url.standardizedFileURL.path,
            vaultName: url.lastPathComponent,
            refreshedAt: refreshedAt,
            notes: notes
        )

        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: noteMetadataCacheKey)
    }

    private func cachedNotes(for url: URL) -> NoteMetadataCache? {
        guard
            let data = UserDefaults.standard.data(forKey: noteMetadataCacheKey),
            let cache = try? JSONDecoder().decode(NoteMetadataCache.self, from: data),
            cache.vaultPath == url.standardizedFileURL.path
        else {
            return nil
        }

        return cache
    }

    /// Walks the vault and builds the note index. Runs off the main actor (`nonisolated`) so it can
    /// be executed on a background task. The caller is responsible for holding security-scoped
    /// access to `rootURL` for the duration of the scan.
    nonisolated static func scanMarkdownFiles(in rootURL: URL) throws -> [Note] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw VaultStoreError.couldNotReadVault
        }

        var scannedNotes: [Note] = []

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
            let name = fileURL.lastPathComponent

            if resourceValues.isDirectory == true {
                if ignoredDirectoryNames.contains(name.lowercased()) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard resourceValues.isRegularFile == true else { continue }
            guard recognizedNoteExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

            scannedNotes.append(makeNote(at: fileURL, rootURL: rootURL, resourceValues: resourceValues))
        }

        return scannedNotes
    }

    /// Builds a `Note` from a single file's metadata, reading only a bounded prefix for the preview
    /// rather than loading the entire file.
    nonisolated static func makeNote(at fileURL: URL, rootURL: URL, resourceValues: URLResourceValues) -> Note {
        let relativePath = relativePath(for: fileURL, rootURL: rootURL)
        let folder = String(relativePath.split(separator: "/").dropLast().joined(separator: "/"))
        let filename = fileURL.lastPathComponent
        let snippet = readPrefix(at: fileURL)

        return Note(
            id: fileURL.standardizedFileURL.path,
            url: fileURL,
            filename: filename,
            folder: folder,
            title: displayTitle(for: filename),
            preview: preview(from: snippet),
            modifiedAt: resourceValues.contentModificationDate ?? .distantPast,
            sizeBytes: resourceValues.fileSize ?? snippet.utf8.count,
            isDailyNote: isDailyNote(filename: filename, folder: folder),
            isInbox: filename.lowercased() == "inbox.md"
        )
    }

    /// Reads up to `previewByteLimit` bytes from a file. Decoding is lenient so a multi-byte
    /// character split at the boundary degrades to a replacement character rather than failing.
    nonisolated private static func readPrefix(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: previewByteLimit)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func captureURL(for destination: CaptureDestination, in vaultURL: URL) throws -> URL {
        switch destination {
        case .inbox:
            return vaultURL.appendingPathComponent("Inbox.md")
        case .daily:
            let dailyFolderURL = vaultURL.appendingPathComponent("Daily", isDirectory: true)
            return dailyFolderURL.appendingPathComponent("\(Self.dailyFilename(for: Date())).md")
        }
    }

    private func uniqueMarkdownURL(baseName: String, in directoryURL: URL) -> URL {
        let fileManager = FileManager.default
        var counter = 1
        var candidateName = "\(baseName).md"
        var candidateURL = directoryURL.appendingPathComponent(candidateName)

        while fileManager.fileExists(atPath: candidateURL.path) {
            counter += 1
            candidateName = "\(baseName) \(counter).md"
            candidateURL = directoryURL.appendingPathComponent(candidateName)
        }

        return candidateURL
    }

    private func readContent(at url: URL) throws -> String {
        try Self.readContent(at: url, scopedTo: vaultURL)
    }

    nonisolated private static func readContent(at url: URL, scopedTo vaultURL: URL?) throws -> String {
        guard let vaultURL else {
            return try String(contentsOf: url, encoding: .utf8)
        }

        let didAccess = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                vaultURL.stopAccessingSecurityScopedResource()
            }
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func write(_ content: String, to url: URL) throws {
        let didAccess = vaultURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didAccess {
                vaultURL?.stopAccessingSecurityScopedResource()
            }
        }

        if let parent = url.deletingLastPathComponentIfNeeded {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated private static func displayTitle(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, recognizedNoteExtensions.contains(ext) else {
            return filename
        }
        return String(filename.dropLast(ext.count + 1))
    }

    nonisolated private static func preview(from content: String) -> String {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                !line.isEmpty && !line.hasPrefix("#")
            }
            .map(stripMarkdown)
        ?? "No preview"
    }

    nonisolated private static func stripMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
    }

    private static func directoryTree(from notes: [Note], vaultName: String) -> VaultDirectoryNode {
        var root = VaultDirectoryNode.root(named: vaultName)

        for note in notes {
            let folders = note.folder
                .split(separator: "/")
                .map(String.init)
            insert(note, into: &root, folders: folders, currentPath: "")
        }

        sortDirectory(&root)
        return root
    }

    private static func insert(_ note: Note, into node: inout VaultDirectoryNode, folders: [String], currentPath: String) {
        guard let folderName = folders.first else {
            node.notes.append(note)
            return
        }

        let nextPath = currentPath.isEmpty ? folderName : "\(currentPath)/\(folderName)"
        if let index = node.children.firstIndex(where: { $0.relativePath == nextPath }) {
            insert(note, into: &node.children[index], folders: Array(folders.dropFirst()), currentPath: nextPath)
        } else {
            var child = VaultDirectoryNode(
                id: nextPath,
                name: folderName,
                relativePath: nextPath,
                notes: [],
                children: []
            )
            insert(note, into: &child, folders: Array(folders.dropFirst()), currentPath: nextPath)
            node.children.append(child)
        }
    }

    private static func sortDirectory(_ node: inout VaultDirectoryNode) {
        node.notes.sort {
            $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending
        }
        node.children.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        for index in node.children.indices {
            sortDirectory(&node.children[index])
        }
    }

    private static func newNoteContent(body: String) -> String {
        body.isEmpty || body.hasSuffix("\n") ? body : "\(body)\n"
    }

    private static func filenameStem(from title: String) -> String {
        let titleStem = title.lowercased().hasSuffix(".md") ? String(title.dropLast(3)) : title
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleanedScalars = titleStem.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : String(scalar)
        }
        let collapsed = cleanedScalars
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        let safeName = collapsed.isEmpty ? "Untitled" : collapsed
        return String(safeName.prefix(80))
    }

    private static func dailyFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated private static func isDailyNote(filename: String, folder: String) -> Bool {
        let lowerFolder = folder.lowercased()
        guard lowerFolder.contains("daily") else { return false }
        return filename.range(of: #"^\d{4}-\d{2}-\d{2}\.md$"#, options: .regularExpression) != nil
    }

    nonisolated private static func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        let startIndex = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
        let relativePath = filePath[startIndex...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath.isEmpty ? fileURL.lastPathComponent : relativePath
    }
}

enum VaultStoreError: LocalizedError {
    case noVaultSelected
    case noteNotFound
    case couldNotReadVault
    case emptyNote

    var errorDescription: String? {
        switch self {
        case .noVaultSelected:
            "Choose a vault folder first."
        case .noteNotFound:
            "The note could not be found."
        case .couldNotReadVault:
            "The vault folder could not be read."
        case .emptyNote:
            "Add a filename before saving."
        }
    }
}

private extension Array where Element == Note {
    func sortedByRecency() -> [Note] {
        sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

private extension URL {
    var deletingLastPathComponentIfNeeded: URL? {
        let parent = deletingLastPathComponent()
        return parent.path == path ? nil : parent
    }
}
