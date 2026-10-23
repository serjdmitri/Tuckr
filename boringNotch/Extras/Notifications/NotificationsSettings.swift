//
//  NotificationsSettings.swift
//  boringNotch
//
//  Settings → Notifications: which apps show up as messages in the notch.
//

import Defaults
import SwiftUI

struct NotificationsSettings: View {
    @ObservedObject private var feed = NotificationFeed.shared
    @Default(.notificationsEnabled) private var enabled
    @Default(.notificationApps) private var apps
    @Default(.notificationHideText) private var hideText
    @Default(.notificationHideFromSharing) private var hideFromSharing
    @Default(.notificationReplaceBanners) private var replaceBanners

    /// The known messaging apps plus whatever else has sent a notification lately.
    private var listed: [(id: String, name: String)] {
        var all = feed.seenApps
        for id in NotificationApps.defaults where all[id] == nil { all[id] = NotificationFeed.name(for: id) }
        return all.map { (id: $0.key, name: $0.value) }
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show messages in the notch", isOn: $enabled)
                    .onChange(of: enabled) { _, on in if on { NotificationFeed.shared.refresh() } }
                Toggle("Hide the text (show only who it is from)", isOn: $hideText)
                Toggle("Keep previews out of screen sharing", isOn: $hideFromSharing)
                Toggle("Replace macOS's own banner for these apps", isOn: $replaceBanners)
            } footer: {
                Text("Reads macOS's own notification list, so it needs Full Disk Access, and changes nothing. Replacing the banner needs Accessibility: the message still stays in Notification Center. Nothing is saved: messages exist only while the app runs.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if feed.needsAccess {
                Section {
                    Text("Full Disk Access is off for this app, so notifications can't be read.")
                        .foregroundColor(.orange)
                    Button("Open Full Disk Access Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
            }
            Section("Apps") {
                ForEach(listed, id: \.id) { app in
                    HStack {
                        Image(nsImage: NotificationFeed.icon(for: app.id)).resizable().frame(width: 20, height: 20)
                        Toggle(app.name, isOn: Binding(
                            get: { apps.contains(app.id) },
                            set: { on in if on { apps.insert(app.id) } else { apps.remove(app.id) } }))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
    }
}
