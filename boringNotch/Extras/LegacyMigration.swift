//
//  LegacyMigration.swift
//  The app was called The BoringCoucouify before it was Tuckr. A new name is a new bundle
//  identifier to macOS, so the old settings and the folder of notes and teleprompter scripts
//  are carried over once, the first time the new app runs.
//

import Foundation

enum LegacyMigration {
    private static let oldBundleID = "com.serjdmitri.TheBoringCoucouify"
    private static let oldFolder = "The BoringCoucouify"
    private static let newFolder = "Tuckr"
    private static let doneKey = "migratedFromBoringCoucouify"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // Settings: only what this app has not already set itself.
        if let old = defaults.persistentDomain(forName: oldBundleID) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // Notes backups and teleprompter scripts.
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let old = base.appendingPathComponent(oldFolder, isDirectory: true)
        let new = base.appendingPathComponent(newFolder, isDirectory: true)
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
    }
}
