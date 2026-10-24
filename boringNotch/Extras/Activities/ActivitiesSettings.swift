//
//  ActivitiesSettings.swift
//  boringNotch
//
//  Settings → Activities.
//

import Defaults
import SwiftUI

struct ActivitiesSettings: View {
    @Default(.activityEvents) private var events
    @Default(.activityEventLead) private var lead
    @Default(.activityDownloads) private var downloads
    @Default(.activityAirDrop) private var airDrop
    @Default(.notchHiddenFromCaptures) private var hidden

    var body: some View {
        Form {
            Section {
                Toggle("Upcoming calendar events", isOn: $events)
                Picker("Warn me", selection: $lead) {
                    ForEach([1, 5, 10, 15, 30], id: \.self) { Text("\($0) min before").tag($0) }
                }
                .disabled(!events)
                Toggle("Downloads finishing", isOn: $downloads)
                Toggle("AirDrop received", isOn: $airDrop)
            } header: {
                Text("Popups")
            } footer: {
                Text("A popup like the AirPods one. A click on an event joins its video call if it has a link; a click on a download or AirDrop shows it in Finder. Downloads and AirDrop are noticed in your Downloads folder.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section {
                Toggle("Keep the notch out of screenshots and screen recordings", isOn: $hidden)
                    .onChange(of: hidden) { _, on in NotchPrivacy.set("settings", on) }
            } header: {
                Text("Privacy")
            } footer: {
                Text("The notch stays on your screen but is left out of anything that captures it.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Activities")
    }
}
