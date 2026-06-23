import Foundation
import SQLite3

/// SQLite's `SQLITE_TRANSIENT` tells SQLite to copy bound text before returning, so we can pass
/// transient Swift strings safely. It isn't imported from the C header, so reconstruct it here.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A single full-text match. `path` equals the originating `Note.ID` so it can drive navigation.
/// `titleSnippet`/`bodySnippet` keep the highlight sentinels (`\u{2}` … `\u{3}`) around matched
/// terms; the view turns them into styled runs.
struct SearchHit: Identifiable, Sendable, Hashable {
    let path: String
    let title: String
    let titleSnippet: String
    let bodySnippet: String
    /// Vault-relative path (`folder/filename`) for display. Filled in by `VaultStore` from its
    /// in-memory note index; empty until then, in which case the view falls back to the filename.
    var relativePath: String = ""

    var id: String { path }
}

/// One note handed to `reconcile`. Carries enough to decide whether a re-read is needed without
/// touching disk, plus the URL to read the body from when it is.
struct IndexEntry: Sendable {
    let path: String
    let title: String
    let url: URL
    let mtime: Double
}

/// Persistent full-text index over note bodies, backed by the system SQLite's FTS5 module.
///
/// Modeled as an `actor` so the non-`Sendable` SQLite connection is only ever touched from one
/// place — every method is serialized, satisfying SQLite's single-connection threading rule under
/// Swift 6 strict concurrency. The database lives in Application Support and survives launches, so a
/// cold start only re-reads files whose modification date changed (see `reconcile`).
actor SearchIndex {
    /// Markers wrapped around matched terms by FTS5 `snippet()`; control chars that never occur in
    /// note text. The view splits on these to style matches.
    static let highlightOpen = "\u{2}"
    static let highlightClose = "\u{3}"

    private var db: OpaquePointer?

    init() {
        db = Self.openDatabase()
    }

    // The connection lives for the whole app session; the OS reclaims it on exit and SQLite
    // recovers the WAL on the next launch, so no isolated `deinit` close is needed.

    // MARK: - Setup

    private static func openDatabase() -> OpaquePointer? {
        let fileManager = FileManager.default
        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }

        let directory = support.appendingPathComponent("FastObsidianMobile", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("search-index.sqlite")

        var handle: OpaquePointer?
        guard sqlite3_open(dbURL.path, &handle) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }

        // WAL + relaxed sync favors fast incremental writes; the index is a rebuildable cache.
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA synchronous=NORMAL;", nil, nil, nil)

        let schema = """
        CREATE TABLE IF NOT EXISTS note_meta(
            path  TEXT PRIMARY KEY,
            rowid INTEGER NOT NULL,
            mtime REAL NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(
            path UNINDEXED, title, body,
            tokenize='unicode61 remove_diacritics 2'
        );
        """
        guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }

        return handle
    }

    // MARK: - Maintenance

    /// Brings the index in line with `entries`: re-reads bodies for new or changed files, and drops
    /// rows for paths that are no longer present. The caller holds security-scoped access to the
    /// vault for the duration; `readBody` performs the actual file read.
    func reconcile(_ entries: [IndexEntry], readBody: @Sendable (URL) -> String?) {
        guard let db else { return }

        var stored = loadStoredMtimes()
        let currentPaths = Set(entries.map(\.path))

        sqlite3_exec(db, "BEGIN", nil, nil, nil)

        for entry in entries {
            if let existing = stored[entry.path], abs(existing - entry.mtime) < 0.001 {
                continue
            }
            let body = readBody(entry.url) ?? ""
            upsertLocked(path: entry.path, title: entry.title, body: body, mtime: entry.mtime)
            stored[entry.path] = entry.mtime
        }

        for path in stored.keys where !currentPaths.contains(path) {
            deleteLocked(path: path)
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    /// Updates a single note in place. Used by the mutation paths that already hold fresh content,
    /// so the index stays current without a rescan or file read.
    func upsert(path: String, title: String, body: String, mtime: Double) {
        guard db != nil else { return }
        upsertLocked(path: path, title: title, body: body, mtime: mtime)
    }

    func delete(path: String) {
        guard db != nil else { return }
        deleteLocked(path: path)
    }

    // MARK: - Query

    /// Returns ranked matches (best first) for a user query, or `[]` for blank/invalid input.
    func search(_ query: String, limit: Int = 50) -> [SearchHit] {
        guard let db, let match = Self.matchExpression(from: query) else { return [] }

        let sql = """
        SELECT path, title,
               snippet(note_fts, 1, ?, ?, '', 12)  AS titleSnippet,
               snippet(note_fts, 2, ?, ?, '…', 12) AS bodySnippet
        FROM note_fts
        WHERE note_fts MATCH ?
        ORDER BY bm25(note_fts)
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, Self.highlightOpen)
        bindText(stmt, 2, Self.highlightClose)
        bindText(stmt, 3, Self.highlightOpen)
        bindText(stmt, 4, Self.highlightClose)
        bindText(stmt, 5, match)
        sqlite3_bind_int(stmt, 6, Int32(limit))

        var hits: [SearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            hits.append(
                SearchHit(
                    path: columnText(stmt, 0),
                    title: columnText(stmt, 1),
                    titleSnippet: columnText(stmt, 2),
                    bodySnippet: columnText(stmt, 3)
                )
            )
        }
        return hits
    }

    // MARK: - Locked primitives (callers guarantee `db != nil`)

    private func upsertLocked(path: String, title: String, body: String, mtime: Double) {
        guard let db else { return }

        if let rowid = rowid(for: path) {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE note_fts SET title=?, body=? WHERE rowid=?;", -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, title)
                bindText(stmt, 2, body)
                sqlite3_bind_int64(stmt, 3, rowid)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)

            var metaStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE note_meta SET mtime=? WHERE path=?;", -1, &metaStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(metaStmt, 1, mtime)
                bindText(metaStmt, 2, path)
                sqlite3_step(metaStmt)
            }
            sqlite3_finalize(metaStmt)
            return
        }

        var insert: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT INTO note_fts(path, title, body) VALUES(?,?,?);", -1, &insert, nil) == SQLITE_OK {
            bindText(insert, 1, path)
            bindText(insert, 2, title)
            bindText(insert, 3, body)
            sqlite3_step(insert)
        }
        sqlite3_finalize(insert)

        let rowid = sqlite3_last_insert_rowid(db)
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT INTO note_meta(path, rowid, mtime) VALUES(?,?,?);", -1, &metaStmt, nil) == SQLITE_OK {
            bindText(metaStmt, 1, path)
            sqlite3_bind_int64(metaStmt, 2, rowid)
            sqlite3_bind_double(metaStmt, 3, mtime)
            sqlite3_step(metaStmt)
        }
        sqlite3_finalize(metaStmt)
    }

    private func deleteLocked(path: String) {
        guard let db, let rowid = rowid(for: path) else { return }

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM note_fts WHERE rowid=?;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, rowid)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM note_meta WHERE path=?;", -1, &metaStmt, nil) == SQLITE_OK {
            bindText(metaStmt, 1, path)
            sqlite3_step(metaStmt)
        }
        sqlite3_finalize(metaStmt)
    }

    private func rowid(for path: String) -> Int64? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT rowid FROM note_meta WHERE path=?;", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, path)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
    }

    private func loadStoredMtimes() -> [String: Double] {
        guard let db else { return [:] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT path, mtime FROM note_meta;", -1, &stmt, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }

        var result: [String: Double] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            result[columnText(stmt, 0)] = sqlite3_column_double(stmt, 1)
        }
        return result
    }

    // MARK: - Helpers

    /// Builds a safe FTS5 MATCH expression for type-ahead: each whitespace-separated token becomes a
    /// quoted phrase (so punctuation can't break the query syntax), and the final token gets a `*`
    /// for prefix matching. Returns `nil` when there's nothing to search.
    static func matchExpression(from query: String) -> String? {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return nil }

        return tokens.enumerated().map { index, token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            let isLast = index == tokens.count - 1
            return isLast ? "\"\(escaped)\"*" : "\"\(escaped)\""
        }.joined(separator: " ")
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }
}
