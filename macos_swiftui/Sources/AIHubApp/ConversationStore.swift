import Accelerate
import Foundation
import NaturalLanguage
import SQLite3

final class ConversationStore: @unchecked Sendable {
    static let shared = ConversationStore()

    private let queue = DispatchQueue(label: "ConversationStore")
    private var db: OpaquePointer?
    private let maxResults = 50

    private init() {
        Storage.shared.ensureBaseDirectory()
        let dbURL = Storage.shared.conversationsDBURL()
        queue.sync {
            openDatabase(path: dbURL.path)
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

    func saveConversation(content: String, siteName: String, url: String, createdAt: UInt64, embedding: [Float]?) async throws -> SavedConversation {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }

                    let insertSQL = "INSERT INTO conversations (site_name, url, content, created_at) VALUES (?, ?, ?, ?);"
                    var statement: OpaquePointer?
                    guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
                        throw ConversationStoreError(message: "Failed to prepare insert")
                    }
                    defer { sqlite3_finalize(statement) }

                    sqlite3_bind_text(statement, 1, siteName, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, url, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 3, content, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(statement, 4, Int64(createdAt))

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw ConversationStoreError(message: "Failed to insert conversation")
                    }

                    let rowId = sqlite3_last_insert_rowid(db)
                    try self.insertFTSRow(db: db, rowId: rowId, content: content)

                    if let embedding {
                        try self.insertEmbedding(db: db, conversationId: rowId, embedding: embedding)
                    }

                    let saved = SavedConversation(
                        id: rowId,
                        siteName: siteName,
                        url: url,
                        content: content,
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
                    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                        throw ConversationStoreError(message: "Failed to prepare search")
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

    func fetchConversation(id: Int64) async throws -> SavedConversation? {
        try await withCheckedThrowingContinuation { continuation in
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
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw ConversationStoreError(message: "Database not available")
                    }
                    if sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        throw ConversationStoreError(message: "Failed to begin transaction: \(message)")
                    }
                    if sqlite3_exec(db, "DELETE FROM conversation_embeddings;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw ConversationStoreError(message: "Failed to clear embeddings: \(message)")
                    }
                    if sqlite3_exec(db, "DELETE FROM conversations_fts;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw ConversationStoreError(message: "Failed to clear search index: \(message)")
                    }
                    if sqlite3_exec(db, "DELETE FROM conversations;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
                        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        throw ConversationStoreError(message: "Failed to clear conversations: \(message)")
                    }
                    if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
                        let message = String(cString: sqlite3_errmsg(db))
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

    private func createTables() {
        let createConversations = """
        CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            site_name TEXT NOT NULL,
            url TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );
        """
        let createFts = """
        CREATE VIRTUAL TABLE IF NOT EXISTS conversations_fts USING fts5(
            content,
            content='conversations',
            content_rowid='id'
        );
        """
        let createEmbeddings = """
        CREATE TABLE IF NOT EXISTS conversation_embeddings (
            conversation_id INTEGER PRIMARY KEY,
            dimension INTEGER NOT NULL,
            vector BLOB NOT NULL
        );
        """
        _ = sqlite3_exec(db, createConversations, nil, nil, nil)
        _ = sqlite3_exec(db, createFts, nil, nil, nil)
        _ = sqlite3_exec(db, createEmbeddings, nil, nil, nil)
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

    private func fetchConversation(db: OpaquePointer, id: Int64) -> SavedConversation? {
        let sql = "SELECT id, site_name, url, content, created_at FROM conversations WHERE id = ?;"
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
        guard let siteName = sqlite3_column_text(statement, 1),
              let url = sqlite3_column_text(statement, 2),
              let content = sqlite3_column_text(statement, 3) else {
            return nil
        }
        let createdAt = sqlite3_column_int64(statement, 4)
        return SavedConversation(
            id: id,
            siteName: String(cString: siteName),
            url: String(cString: url),
            content: String(cString: content),
            createdAt: UInt64(createdAt)
        )
    }

    private func readPreviewRow(statement: OpaquePointer?) -> SavedConversationPreview? {
        guard let statement else { return nil }
        let id = sqlite3_column_int64(statement, 0)
        guard let siteName = sqlite3_column_text(statement, 1),
              let url = sqlite3_column_text(statement, 2),
              let snippet = sqlite3_column_text(statement, 3) else {
            return nil
        }
        let createdAt = sqlite3_column_int64(statement, 4)
        let trimmedSnippet = String(cString: snippet).trimmingCharacters(in: .whitespacesAndNewlines)
        return SavedConversationPreview(
            id: id,
            siteName: String(cString: siteName),
            url: String(cString: url),
            snippet: trimmedSnippet,
            createdAt: UInt64(createdAt)
        )
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
