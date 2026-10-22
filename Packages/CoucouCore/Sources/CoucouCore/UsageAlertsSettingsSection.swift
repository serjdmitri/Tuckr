import SwiftUI

/// Agents Settings, Usage alerts: at which percentages the notch warns about an agent's
/// plan usage.
struct UsageAlertsSettingsSection: View {
  @ObservedObject private var settings = UsageAlertSettings.shared
  @State private var texts: [UsageAgent: String] = [:]

  var body: some View {
    GroupBox("When to warn") {
      VStack(alignment: .leading, spacing: 14) {
        Text("The notch drops a popup, with a sound, when an agent's 5-hour or weekly usage passes one of these percentages. Each level warns once per window.")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        ForEach(UsageAgent.allCases) { agent in
          HStack(spacing: 12) {
            Toggle(
              agent.title,
              isOn: Binding(get: { settings.enabled(agent) }, set: { settings.setEnabled(agent, $0) })
            )
            .toggleStyle(.switch)
            .frame(width: 110, alignment: .leading)
            TextField(
              "50, 75, 90",
              text: Binding(
                get: { texts[agent] ?? settings.levelsText(agent) },
                set: { texts[agent] = $0 }
              )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
            .disabled(!settings.enabled(agent))
            .onSubmit { commit(agent) }
            Button("Save") { commit(agent) }
              .disabled(!settings.enabled(agent))
            Text(settings.levels(agent).map { "\($0)%" }.joined(separator: " · "))
              .font(.system(size: 11))
              .foregroundColor(.secondary)
          }
        }
      }
      .padding(6)
    }
  }

  private func commit(_ agent: UsageAgent) {
    guard let text = texts[agent] else { return }
    let levels = UsageAlertSettings.parse(text)
    settings.setLevels(agent, text: levels.map(String.init).joined(separator: ", "))
    texts[agent] = nil
  }
}
