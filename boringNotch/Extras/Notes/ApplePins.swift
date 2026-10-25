//
//  ApplePins.swift
//  boringNotch
//
//  Which notes are pinned in Apple Notes. AppleScript does not expose that, so it is read
//  (never written) from Notes' own database, which macOS only lets an app with Full Disk
//  Access see. A copy of the database is read, so Notes is never held up.
//

import Foundation
import SQLite3

enum ApplePins {
    enum Result: Equatable {
        /// The numbers in the ids of the pinned notes (…/ICNote/p123 is 123).
        case pins(Set<Int>)
        /// macOS refused the file: the app has no Full Disk Access.
        case noAccess
        case failed
    }

    static func read() async -> Result {
        await Task.detached(priority: .utility) { readNow() }.value
    }

    private static func readNow() -> Result {
        let fm = FileManager.default
        let source = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes", isDirectory: true)
        let scratch = fm.temporaryDirectory.appendingPathComponent("notch-notes-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // The write-ahead files hold the newest changes, so they come along.
            for name in ["NoteStore.sqlite", "NoteStore.sqlite-wal", "NoteStore.sqlite-shm"] {
                let from = source.appendingPathComponent(name)
                if name == "NoteStore.sqlite" || fm.fileExists(atPath: from.path) {
                    try fm.copyItem(at: from, to: scratch.appendingPathComponent(name))
                }
            }
        } catch {
            let code = (error as NSError).code
            // 513: no permission; 257: not readable; 1: operation not permitted.
            return [513, 257, 1].contains(code) || (error as NSError).domain == NSPOSIXErrorDomain ? .noAccess : .failed
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(scratch.appendingPathComponent("NoteStore.sqlite").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return .failed
        }
        defer { sqlite3_close(db) }
        // The full query first; a plainer one if this version of Notes names things differently.
        let queries = [
            """
            SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZISPINNED = 1
              AND Z_ENT = (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'ICNote')
              AND (ZMARKEDFORDELETION IS NULL OR ZMARKEDFORDELETION = 0)
            """,
            "SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE ZISPINNED = 1",
        ]
        var statement: OpaquePointer?
        guard queries.contains(where: { sqlite3_prepare_v2(db, $0, -1, &statement, nil) == SQLITE_OK }) else { return .failed }
        defer { sqlite3_finalize(statement) }
        var pins = Set<Int>()
        while sqlite3_step(statement) == SQLITE_ROW { pins.insert(Int(sqlite3_column_int64(statement, 0))) }
        return .pins(pins)
    }
}
