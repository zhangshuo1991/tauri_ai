import Accelerate
import Foundation
import NaturalLanguage
import SQLite3

final class ConversationStore: @unchecked Sendable {
    static let shared = ConversationStore()

    private let queue = DispatchQueue(label: "ConversationStore")
    private var db: OpaquePointer?
    private let dbPath: String
    private let maxResults = 50

    private init() {
        Storage.shared.ensureBaseDirectory()
        let dbURL = Storage.shared.conversationsDBURL()
        dbPath = dbURL.path
        queue.sync {
            openDatabase(path: dbPath)
            createTables()
        }
    }

    deinit {
        queue.sync {
            if let db {
                sqlite3_close(db)
            }
            db = nil
        }
    }

    func saveConversation(tabId: String, content: String, markdown: String, siteName: String, url: String, createdAt: UInt64, embedding: [Float]?) async throws -> SavedConversation {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }

                    let insertSQL = """
                    INSERT INTO conversations (tab_id, site_name, url, content, markdown, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(tab_id) DO UPDATE SET
                        site_name=excluded.site_name,
                        url=excluded.url,
                        content=excluded.content,
                        markdown=excluded.markdown,
                        created_at=excluded.created_at;
                    """
                    var statement: OpaquePointer?
                    guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
                        throw ConversationStoreError(message: "Failed to prepare insert")
                    }
                    defer { sqlite3_finalize(statement) }

                    sqlite3_bind_text(statement, 1, tabId, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, siteName, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 3, url, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 4, content, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 5, markdown, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(statement, 6, Int64(createdAt))

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw ConversationStoreError(message: "Failed to insert conversation")
                    }

                    let rowId = try self.fetchConversationId(db: db, tabId: tabId)
                    try self.refreshFTSRow(db: db, rowId: rowId, content: content)

                    if let embedding {
                        try self.insertEmbedding(db: db, conversationId: rowId, embedding: embedding)
                    } else {
                        self.removeEmbedding(db: db, conversationId: rowId)
                    }

                    let saved = SavedConversation(
                        id: rowId,
                        siteName: siteName,
                        url: url,
                        content: content,
                        markdown: markdown,
                        createdAt: createdAt
                    )
                    continuation.resume(returning: saved)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func searchKeyword(query: String) async throws -> [SavedConversationPreview] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }

                    let matchQuery = self.ftsQuery(from: query)
                    let sql = """
                    SELECT conversations.id, conversations.site_name, conversations.url,
                           substr(conversations.content, 1, 200) AS snippet,
                           conversations.created_at
                    FROM conversations_fts
                    JOIN conversations ON conversations_fts.rowid = conversations.id
                    WHERE conversations_fts MATCH ?
                    ORDER BY bm25(conversations_fts)
                    LIMIT ?;
                    """

                    var statement: OpaquePointer?
                    if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                        try self.rebuildFTSIndex(db: db)
                        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                            throw ConversationStoreError(message: "Failed to prepare search")
                        }
                    }
                    defer { sqlite3_finalize(statement) }

                    sqlite3_bind_text(statement, 1, matchQuery, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(statement, 2, Int32(self.maxResults))

                    var results: [SavedConversationPreview] = []
                    while sqlite3_step(statement) == SQLITE_ROW {
                        if let preview = self.readPreviewRow(statement: statement) {
                            results.append(preview)
                        }
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func searchSemantic(queryEmbedding: [Float]) async throws -> [SavedConversationPreview] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }

                    let dimension = queryEmbedding.count
                    let sql = "SELECT conversation_id, dimension, vector FROM conversation_embeddings WHERE dimension = ?;"
                    var statement: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                        throw ConversationStoreError(message: "Failed to prepare embeddings")
                    }
                    defer { sqlite3_finalize(statement) }
                    sqlite3_bind_int(statement, 1, Int32(dimension))

                    var scored: [(Int64, Float)] = []
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let convoId = sqlite3_column_int64(statement, 0)
                        let blob = sqlite3_column_blob(statement, 2)
                        let size = sqlite3_column_bytes(statement, 2)
                        guard let blob, size > 0 else { continue }
                        let data = Data(bytes: blob, count: Int(size))
                        let vector = data.withUnsafeBytes { pointer -> [Float] in
                            let buffer = pointer.bindMemory(to: Float.self)
                            return Array(buffer)
                        }
                        guard vector.count == dimension else { continue }
                        let score = self.cosineSimilarity(queryEmbedding, vector)
                        scored.append((convoId, score))
                    }

                    let sorted = scored.sorted { $0.1 > $1.1 }.prefix(self.maxResults)
                    var results: [SavedConversationPreview] = []
                    for (convoId, _) in sorted {
                        if let preview = self.fetchConversationPreview(db: db, id: convoId) {
                            results.append(preview)
                        }
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func listRecent(limit: Int) async throws -> [SavedConversationPreview] {
        let capped = min(max(1, limit), maxResults)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }

                    let sql = """
                    SELECT id, site_name, url, substr(content, 1, 200) AS snippet, created_at
                    FROM conversations
                    ORDER BY created_at DESC
                    LIMIT ?;
                    """
                    var statement: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                        throw ConversationStoreError(message: "Failed to prepare recent list")
                    }
                    defer { sqlite3_finalize(statement) }
                    sqlite3_bind_int(statement, 1, Int32(capped))

                    var results: [SavedConversationPreview] = []
                    while sqlite3_step(statement) == SQLITE_ROW {
                        if let preview = self.readPreviewRow(statement: statement) {
                            results.append(preview)
                        }
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func listHistory(
        keyword: String,
        siteName: String?,
        startTime: UInt64?,
        endTime: UInt64?,
        codeOnly: Bool,
        limit: Int,
        offset: Int
    ) async throws -> [SavedConversationPreview] {
        let capped = min(max(1, limit), maxResults)
        let clampedOffset = max(0, offset)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }
                    let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parts = self.historyQueryParts(
                        keyword: query,
                        siteName: siteName,
                        startTime: startTime,
                        endTime: endTime,
                        codeOnly: codeOnly
                    )
                    let sql: String
                    if parts.useFTS {
                        sql = """
                        SELECT conversations.id, conversations.site_name, conversations.url,
                               substr(conversations.content, 1, 200) AS snippet,
                               conversations.created_at
                        FROM conversations_fts
                        JOIN conversations ON conversations_fts.rowid = conversations.id
                        \(parts.whereClause)
                        ORDER BY conversations.created_at DESC
                        LIMIT ? OFFSET ?;
                        """
                    } else {
                        sql = """
                        SELECT id, site_name, url, substr(content, 1, 200) AS snippet, created_at
                        FROM conversations
                        \(parts.whereClause)
                        ORDER BY created_at DESC
                        LIMIT ? OFFSET ?;
                        """
                    }

                    var statement: OpaquePointer?
                    if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                        if parts.useFTS {
                            try self.rebuildFTSIndex(db: db)
                            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                                throw ConversationStoreError(message: "Failed to prepare history list")
                            }
                        } else {
                            throw ConversationStoreError(message: "Failed to prepare history list")
                        }
                    }
                    defer { sqlite3_finalize(statement) }

                    var bindings = parts.bindings
                    bindings.append(.int(capped))
                    bindings.append(.int(clampedOffset))
                    self.bind(statement: statement, values: bindings)

                    var results: [SavedConversationPreview] = []
                    while sqlite3_step(statement) == SQLITE_ROW {
                        if let preview = self.readPreviewRow(statement: statement) {
                            results.append(preview)
                        }
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func countHistory(
        keyword: String,
        siteName: String?,
        startTime: UInt64?,
        endTime: UInt64?,
        codeOnly: Bool
    ) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }
                    let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parts = self.historyQueryParts(
                        keyword: query,
                        siteName: siteName,
                        startTime: startTime,
                        endTime: endTime,
                        codeOnly: codeOnly
                    )
                    let sql: String
                    if parts.useFTS {
                        sql = """
                        SELECT COUNT(*)
                        FROM conversations_fts
                        JOIN conversations ON conversations_fts.rowid = conversations.id
                        \(parts.whereClause);
                        """
                    } else {
                        sql = """
                        SELECT COUNT(*)
                        FROM conversations
                        \(parts.whereClause);
                        """
                    }

                    var statement: OpaquePointer?
                    if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                        if parts.useFTS {
                            try self.rebuildFTSIndex(db: db)
                            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                                throw ConversationStoreError(message: "Failed to prepare history count")
                            }
                        } else {
                            throw ConversationStoreError(message: "Failed to prepare history count")
                        }
                    }
                    defer { sqlite3_finalize(statement) }
                    self.bind(statement: statement, values: parts.bindings)

                    guard sqlite3_step(statement) == SQLITE_ROW else {
                        continuation.resume(returning: 0)
                        return
                    }
                    continuation.resume(returning: Int(sqlite3_column_int64(statement, 0)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchConversations(ids: [Int64]) async throws -> [SavedConversation] {
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty else { return [] }
        let placeholders = uniqueIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT id, site_name, url, content, markdown, created_at
        FROM conversations
        WHERE id IN (\(placeholders))
        ORDER BY created_at DESC;
        """
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }
                    var statement: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                        throw ConversationStoreError(message: "Failed to prepare history fetch")
                    }
                    defer { sqlite3_finalize(statement) }
                    for (idx, id) in uniqueIds.enumerated() {
                        sqlite3_bind_int64(statement, Int32(idx + 1), id)
                    }
                    var results: [SavedConversation] = []
                    while sqlite3_step(statement) == SQLITE_ROW {
                        if let convo = self.readConversationRow(statement: statement) {
                            results.append(convo)
                        }
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteConversations(ids: [Int64]) async throws {
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty else { return }
        let placeholders = uniqueIds.map { _ in "?" }.joined(separator: ",")
        let deleteConversationsSQL = "DELETE FROM conversations WHERE id IN (\(placeholders));"
        let deleteEmbeddingsSQL = "DELETE FROM conversation_embeddings WHERE conversation_id IN (\(placeholders));"
        let deleteFTSSQL = "DELETE FROM conversations_fts WHERE rowid IN (\(placeholders));"
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let db = self.db else {
                    continuation.resume(throwing: ConversationStoreError(message: "Database not available"))
                    return
                }
                do {
                    if sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        if self.isDatabaseCorrupt(db: db) {
                            self.resetDatabase()
                            continuation.resume()
                            return
                        }
                        throw ConversationStoreError(message: "Failed to begin transaction: \(message)")
                    }

                    try self.executeDelete(db: db, sql: deleteEmbeddingsSQL, ids: uniqueIds, errorMessage: "Failed to delete embeddings")
                    if !self.executeDeleteAllowingRebuild(db: db, sql: deleteFTSSQL, ids: uniqueIds) {
                        try self.rebuildFTSIndex(db: db)
                        _ = self.executeDeleteAllowingRebuild(db: db, sql: deleteFTSSQL, ids: uniqueIds)
                    }
                    try self.executeDelete(db: db, sql: deleteConversationsSQL, ids: uniqueIds, errorMessage: "Failed to delete conversations")

                    if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw ConversationStoreError(message: "Failed to commit delete: \(message)")
                    }
                    continuation.resume()
                } catch {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchConversation(id: Int64) async throws -> SavedConversation? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SavedConversation?, Error>) in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }
                    continuation.resume(returning: self.fetchConversation(db: db, id: id))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func clearHistory() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }
                    if sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        if self.isDatabaseCorrupt(db: db) {
                            self.resetDatabase()
                            continuation.resume()
                            return
                        }
                        throw ConversationStoreError(message: "Failed to begin transaction: \(message)")
                    }
                    if sqlite3_exec(db, "DELETE FROM conversation_embeddings;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        if self.isDatabaseCorrupt(db: db) {
                            self.resetDatabase()
                            continuation.resume()
                            return
                        }
                        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw ConversationStoreError(message: "Failed to clear embeddings: \(message)")
                    }
                    if sqlite3_exec(db, "DELETE FROM conversations_fts;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        if self.isDatabaseCorrupt(db: db) {
                            self.resetDatabase()
                            continuation.resume()
                            return
                        }
                        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw ConversationStoreError(message: "Failed to clear search index: \(message)")
                    }
                    if sqlite3_exec(db, "DELETE FROM conversations;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        if self.isDatabaseCorrupt(db: db) {
                            self.resetDatabase()
                            continuation.resume()
                            return
                        }
                        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw ConversationStoreError(message: "Failed to clear conversations: \(message)")
                    }
                    if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        if self.isDatabaseCorrupt(db: db) {
                            self.resetDatabase()
                            continuation.resume()
                            return
                        }
                        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw ConversationStoreError(message: "Failed to commit: \(message)")
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func openDatabase(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            db = nil
            return
        }
        _ = sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    private func resetDatabase() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
        try? FileManager.default.removeItem(atPath: dbPath)
        openDatabase(path: dbPath)
        createTables()
    }

    private func isDatabaseCorrupt(db: OpaquePointer?) -> Bool {
        guard let db else { return false }
        let code = sqlite3_errcode(db)
        if code == SQLITE_CORRUPT || code == SQLITE_NOTADB {
            return true
        }
        let message = String(cString: sqlite3_errmsg(db))
        return message.localizedCaseInsensitiveContains("malformed")
    }

    private func createTables() {
        let createConversations = """
        CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tab_id TEXT,
            site_name TEXT NOT NULL,
            url TEXT NOT NULL,
            content TEXT NOT NULL,
            markdown TEXT,
            created_at INTEGER NOT NULL
        );
        """
        guard let db else { return }
        let createEmbeddings = """
        CREATE TABLE IF NOT EXISTS conversation_embeddings (
            conversation_id INTEGER PRIMARY KEY,
            dimension INTEGER NOT NULL,
            vector BLOB NOT NULL
        );
        """
        _ = sqlite3_exec(db, createConversations, nil, nil, nil)
        createFTSTable(db: db)
        _ = sqlite3_exec(db, createEmbeddings, nil, nil, nil)
        migrateSchemaIfNeeded()
    }

    private func migrateSchemaIfNeeded() {
        ensureColumn(table: "conversations", column: "tab_id", definition: "TEXT")
        ensureColumn(table: "conversations", column: "markdown", definition: "TEXT")
        _ = sqlite3_exec(db, "CREATE UNIQUE INDEX IF NOT EXISTS conversations_tab_id_idx ON conversations (tab_id);", nil, nil, nil)
    }

    private func ensureColumn(table: String, column: String, definition: String) {
        guard let db, !columnExists(table: table, column: column) else { return }
        let sql = "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);"
        _ = sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func columnExists(table: String, column: String) -> Bool {
        guard let db else { return false }
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column {
                return true
            }
        }
        return false
    }

    private func insertFTSRow(db: OpaquePointer, rowId: Int64, content: String) throws {
        let searchable = searchableContent(from: content)
        let sql = "INSERT INTO conversations_fts(rowid, content) VALUES (?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationStoreError(message: "Failed to prepare FTS insert")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowId)
        sqlite3_bind_text(statement, 2, searchable, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ConversationStoreError(message: "Failed to insert FTS row")
        }
    }

    private func refreshFTSRow(db: OpaquePointer, rowId: Int64, content: String) throws {
        if !deleteFTSRow(db: db, rowId: rowId) {
            try rebuildFTSIndex(db: db)
            _ = deleteFTSRow(db: db, rowId: rowId)
        }

        do {
            try insertFTSRow(db: db, rowId: rowId, content: content)
        } catch {
            try rebuildFTSIndex(db: db)
            try insertFTSRow(db: db, rowId: rowId, content: content)
        }
    }

    private func deleteFTSRow(db: OpaquePointer, rowId: Int64) -> Bool {
        let sql = "DELETE FROM conversations_fts WHERE rowid = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowId)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func rebuildFTSIndex(db: OpaquePointer) throws {
        let rebuildSQL = "INSERT INTO conversations_fts(conversations_fts) VALUES('rebuild');"
        if sqlite3_exec(db, rebuildSQL, nil, nil, nil) == SQLITE_OK {
            return
        }
        _ = sqlite3_exec(db, "DROP TABLE IF EXISTS conversations_fts;", nil, nil, nil)
        createFTSTable(db: db)
        if sqlite3_exec(db, rebuildSQL, nil, nil, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            throw ConversationStoreError(message: "Failed to rebuild search index: \(message)")
        }
    }

    private func createFTSTable(db: OpaquePointer) {
        let createFts = """
        CREATE VIRTUAL TABLE IF NOT EXISTS conversations_fts USING fts5(
            content,
            content='conversations',
            content_rowid='id'
        );
        """
        _ = sqlite3_exec(db, createFts, nil, nil, nil)
    }

    private func insertEmbedding(db: OpaquePointer, conversationId: Int64, embedding: [Float]) throws {
        let sql = "INSERT OR REPLACE INTO conversation_embeddings (conversation_id, dimension, vector) VALUES (?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationStoreError(message: "Failed to prepare embedding insert")
        }
        defer { sqlite3_finalize(statement) }

        let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
        sqlite3_bind_int64(statement, 1, conversationId)
        sqlite3_bind_int(statement, 2, Int32(embedding.count))
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ConversationStoreError(message: "Failed to insert embedding")
        }
    }

    private func removeEmbedding(db: OpaquePointer, conversationId: Int64) {
        let sql = "DELETE FROM conversation_embeddings WHERE conversation_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, conversationId)
        _ = sqlite3_step(statement)
    }

    private func fetchConversationId(db: OpaquePointer, tabId: String) throws -> Int64 {
        let sql = "SELECT id FROM conversations WHERE tab_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationStoreError(message: "Failed to read conversation id")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, tabId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ConversationStoreError(message: "Conversation id not found")
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func fetchConversation(db: OpaquePointer, id: Int64) -> SavedConversation? {
        let sql = "SELECT id, site_name, url, content, markdown, created_at FROM conversations WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return readConversationRow(statement: statement)
    }

    private func fetchConversationPreview(db: OpaquePointer, id: Int64) -> SavedConversationPreview? {
        let sql = """
        SELECT id, site_name, url, substr(content, 1, 200) AS snippet, created_at
        FROM conversations WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return readPreviewRow(statement: statement)
    }

    private func readConversationRow(statement: OpaquePointer?) -> SavedConversation? {
        guard let statement else { return nil }
        let id = sqlite3_column_int64(statement, 0)
        let siteName = readText(statement: statement, index: 1)
        let url = readText(statement: statement, index: 2)
        let content = readText(statement: statement, index: 3)
        let markdown = readText(statement: statement, index: 4)
        let createdAt = sqlite3_column_int64(statement, 5)
        return SavedConversation(
            id: id,
            siteName: siteName,
            url: url,
            content: content,
            markdown: markdown,
            createdAt: UInt64(createdAt)
        )
    }

    private func readPreviewRow(statement: OpaquePointer?) -> SavedConversationPreview? {
        guard let statement else { return nil }
        let id = sqlite3_column_int64(statement, 0)
        let siteName = readText(statement: statement, index: 1)
        let url = readText(statement: statement, index: 2)
        let snippet = readText(statement: statement, index: 3)
        let createdAt = sqlite3_column_int64(statement, 4)
        let trimmedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return SavedConversationPreview(
            id: id,
            siteName: siteName,
            url: url,
            snippet: trimmedSnippet,
            createdAt: UInt64(createdAt)
        )
    }

    private func readText(statement: OpaquePointer?, index: Int32) -> String {
        guard let statement else { return "" }
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        let cChar = UnsafeRawPointer(cString).assumingMemoryBound(to: CChar.self)
        if let valid = String(validatingCString: cChar) {
            return valid
        }
        let length = sqlite3_column_bytes(statement, index)
        guard length > 0 else { return "" }
        let data = Data(bytes: cString, count: Int(length))
        return String(decoding: data, as: UTF8.self)
    }

    private func searchableContent(from text: String) -> String {
        let tokens = tokenize(text)
        if tokens.isEmpty {
            return text
        }
        return tokens.joined(separator: " ")
    }

    private func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }

    private func ftsQuery(from query: String) -> String {
        let tokens = tokenize(query)
        if tokens.isEmpty {
            return query
        }
        let escaped = tokens.map { token in
            let sanitized = token.replacingOccurrences(of: "\"", with: "")
            return "\"\(sanitized)\"*"
        }
        return escaped.joined(separator: " AND ")
    }

    private struct HistoryQueryParts {
        let useFTS: Bool
        let whereClause: String
        let bindings: [BindValue]
    }

    private enum BindValue {
        case text(String)
        case int(Int)
        case int64(Int64)
    }

    private func historyQueryParts(
        keyword: String,
        siteName: String?,
        startTime: UInt64?,
        endTime: UInt64?,
        codeOnly: Bool
    ) -> HistoryQueryParts {
        var clauses: [String] = []
        var bindings: [BindValue] = []
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let useFTS = !trimmed.isEmpty
        if useFTS {
            clauses.append("conversations_fts MATCH ?")
            bindings.append(.text(ftsQuery(from: trimmed)))
        }
        if let siteName, !siteName.isEmpty {
            clauses.append("conversations.site_name = ?")
            bindings.append(.text(siteName))
        }
        if let startTime {
            clauses.append("conversations.created_at >= ?")
            bindings.append(.int64(Int64(startTime)))
        }
        if let endTime {
            clauses.append("conversations.created_at <= ?")
            bindings.append(.int64(Int64(endTime)))
        }
        if codeOnly {
            clauses.append("conversations.markdown LIKE ?")
            bindings.append(.text("%```%"))
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        return HistoryQueryParts(useFTS: useFTS, whereClause: whereClause, bindings: bindings)
    }

    private func bind(statement: OpaquePointer?, values: [BindValue]) {
        guard let statement else { return }
        for (index, value) in values.enumerated() {
            let idx = Int32(index + 1)
            switch value {
            case .text(let text):
                sqlite3_bind_text(statement, idx, text, -1, SQLITE_TRANSIENT)
            case .int(let number):
                sqlite3_bind_int(statement, idx, Int32(number))
            case .int64(let number):
                sqlite3_bind_int64(statement, idx, number)
            }
        }
    }

    private func executeDelete(db: OpaquePointer, sql: String, ids: [Int64], errorMessage: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationStoreError(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        for (idx, id) in ids.enumerated() {
            sqlite3_bind_int64(statement, Int32(idx + 1), id)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ConversationStoreError(message: errorMessage)
        }
    }

    private func executeDeleteAllowingRebuild(db: OpaquePointer, sql: String, ids: [Int64]) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        for (idx, id) in ids.enumerated() {
            sqlite3_bind_int64(statement, Int32(idx + 1), id)
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &dot, vDSP_Length(count))
        var lhsNorm: Float = 0
        vDSP_dotpr(lhs, 1, lhs, 1, &lhsNorm, vDSP_Length(count))
        var rhsNorm: Float = 0
        vDSP_dotpr(rhs, 1, rhs, 1, &rhsNorm, vDSP_Length(count))
        let denom = sqrt(lhsNorm) * sqrt(rhsNorm)
        if denom == 0 {
            return 0
        }
        return dot / denom
    }
}

private struct ConversationStoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
