import SwiftUI

/// Talkify's Shortcuts board and bindings, for the host app's Settings window.
struct TalkifyShortcutsPane: View {
  var body: some View {
    if let settings = TalkifyRuntime.current?.sharedSettings {
      ScrollView {
        ShortcutsSettingsView(settings: settings)
          .padding(20)
      }
      .background(SettingsTheme.background)
      .environment(\.colorScheme, .dark)
    } else {
      Text("Shortcuts are available once the app has finished starting.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
