//
//  PrivateStorage.swift
//  What the app keeps on disk (notes backups, teleprompter scripts) is for its owner only:
//  the folder is closed to other accounts on the Mac, the files readable by this user alone.
//  Also removes the temporary copies of the Notifications and Notes databases that a crash
//  could have left behind.
//

import Foundation

enum PrivateStorage {
    /// The app's own folder in Application Support.
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tuckr", isDirectory: true)
    }

    /// Owner-only: 0700 for a folder, 0600 for a file.
    static func secure(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: isDirectory.boolValue ? 0o700 : 0o600], ofItemAtPath: url.path)
    }

    /// At launch: everything already in the app's folder, and any leftover scratch copies.
    static func lockDown() {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            secure(folder)
            if let walker = fm.enumerator(at: folder, includingPropertiesForKeys: nil) {
                for case let url as URL in walker { secure(url) }
            }
        }
        let temporary = fm.temporaryDirectory
        for name in (try? fm.contentsOfDirectory(atPath: temporary.path)) ?? []
        where name.hasPrefix("notch-un-") || name.hasPrefix("notch-notes-") {
            try? fm.removeItem(at: temporary.appendingPathComponent(name))
        }
    }
}
