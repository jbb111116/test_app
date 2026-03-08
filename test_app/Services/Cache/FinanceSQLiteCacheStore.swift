import Foundation
import SQLite3

final class FinanceSQLiteCacheStore: CacheStoring {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "cache.sqlite.queue")
    private let path: String

    init(filename: String = "cache.sqlite3") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.path = dir.appendingPathComponent(filename).path
        open()
        createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    private func open() {
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("[SQLiteCache] Failed to open DB at \(path)")
        }
    }

    private func createSchema() {
        let sql = "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value BLOB NOT NULL);"
        _ = exec(sql)
    }

    func save(accounts: [Account]) {
        saveJSON(accounts, forKey: "accounts")
    }

    func save(transactions: [Transaction]) {
        saveJSON(transactions, forKey: "transactions")
    }

    func loadAccounts() -> [Account] {
        loadJSON([Account].self, forKey: "accounts") ?? []
    }

    func loadTransactions() -> [Transaction] {
        loadJSON([Transaction].self, forKey: "transactions") ?? []
    }

    private func saveJSON<T: Encodable>(_ value: T, forKey key: String) {
        queue.sync {
            do {
                let data = try JSONEncoder().encode(value)
                upsert(key: key, data: data)
            } catch {
                print("[SQLiteCache] encode error: \(error)")
            }
        }
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        queue.sync {
            guard let data = read(key: key) else { return nil }
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                print("[SQLiteCache] decode error: \(error)")
                return nil
            }
        }
    }

    private func upsert(key: String, data: Data) {
        let sql = "INSERT INTO kv(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        data.withUnsafeBytes { buf in
            _ = sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
        }
        _ = sqlite3_step(stmt)
    }

    private func read(key: String) -> Data? {
        let sql = "SELECT value FROM kv WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) {
            let size = Int(sqlite3_column_bytes(stmt, 0))
            return Data(bytes: blob, count: size)
        }
        return nil
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let c = err { print("[SQLiteCache] exec error: \(String(cString: c))") }
            return false
        }
        return true
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
