//
//  VoiceMessages.swift
//  Hearing a voice message from the notch. A notification only says "Voice message"; the
//  sound itself is a file the chat app has already saved. This finds that file in WhatsApp's
//  or Messages' own database (read-only, with Full Disk Access) and plays it. Nothing is
//  copied or kept.
//

import AVFoundation
import Foundation
import SQLite3

enum VoiceLocator {
    /// Whether a notification is a voice message, going by the words the apps use.
    static func looksLikeVoice(title: String, body: String) -> Bool {
        let text = (title + " " + body).lowercased()
        return ["voice message", "voice note", "audio message", "audio", "🎤", "🎙", "🔊"].contains { text.contains($0) }
    }

    /// The saved sound for the newest incoming voice message that came in lately.
    static func locate(appID: String) async -> URL? {
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            switch appID {
            case "net.whatsapp.whatsapp": return whatsApp()
            case "com.apple.mobilesms": return messages()
            default: return nil
            }
        }.value
    }

    // MARK: WhatsApp

    private static func whatsApp() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared", isDirectory: true)
        // Apple's reference date, in seconds.
        let since = Date().timeIntervalSinceReferenceDate - 120
        let sql = """
            SELECT i.ZMEDIALOCALPATH FROM ZWAMESSAGE m JOIN ZWAMEDIAITEM i ON i.ZMESSAGE = m.Z_PK
            WHERE m.ZMESSAGETYPE = 3 AND m.ZISFROMME = 0 AND m.ZMESSAGEDATE > ?
            ORDER BY m.ZMESSAGEDATE DESC LIMIT 1
            """
        guard let path = firstString(database: base.appendingPathComponent("ChatStorage.sqlite"), sql: sql, bind: since)
        else { return nil }
        let fm = FileManager.default
        return [base.appendingPathComponent(path), base.appendingPathComponent("Message").appendingPathComponent(path)]
            .first { fm.fileExists(atPath: $0.path) }
    }

    // MARK: Messages

    private static func messages() -> URL? {
        let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")
        // Messages counts its dates in nanoseconds from the reference date.
        let since = (Date().timeIntervalSinceReferenceDate - 120) * 1_000_000_000
        let sql = """
            SELECT a.filename FROM message m
            JOIN message_attachment_join j ON j.message_id = m.ROWID
            JOIN attachment a ON a.ROWID = j.attachment_id
            WHERE m.is_audio_message = 1 AND m.is_from_me = 0 AND m.date > ?
            ORDER BY m.date DESC LIMIT 1
            """
        guard let path = firstString(database: db, sql: sql, bind: since) else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: SQLite

    /// The first column of the first row, from a database opened read-only in place.
    private static func firstString(database: URL, sql: String, bind: Double) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 300)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, bind)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }
}

/// Plays one voice message at a time, for the popup and the Messages page.
@MainActor
final class VoicePlayer: ObservableObject {
    static let shared = VoicePlayer()

    @Published private(set) var playingID: Int?
    @Published private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func isPlaying(_ id: Int) -> Bool { playingID == id }

    func toggle(_ item: NotificationItem) {
        guard let url = item.audioURL else { return }
        if playingID == item.id { stop(); return }
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        player.play()
        playingID = item.id
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let voice = VoicePlayer.shared
                guard let p = voice.player, p.isPlaying else { voice.stop(); return }
                voice.progress = p.duration > 0 ? p.currentTime / p.duration : 0
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        playingID = nil
        progress = 0
    }
}

/// A play button with a ring that fills as the message plays.
import SwiftUI

struct VoiceButton: View {
    let item: NotificationItem
    var size: CGFloat = 40
    @ObservedObject private var player = VoicePlayer.shared

    var body: some View {
        if item.audioURL != nil {
            let playing = player.isPlaying(item.id)
            Button { player.toggle(item) } label: {
                ZStack {
                    Circle().fill(Color.white.opacity(0.14))
                    Circle()
                        .trim(from: 0, to: playing ? player.progress : 0)
                        .stroke(Color(red: 0.2, green: 0.82, blue: 0.38), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: player.progress)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: size * 0.38, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(playing ? "Pause" : "Play the voice message")
        }
    }
}
