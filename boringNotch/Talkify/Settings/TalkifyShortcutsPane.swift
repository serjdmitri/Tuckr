import SwiftUI

/// Talkify's Shortcuts board and bindings, for the host app's Settings window.
struct TalkifyShortcutsPane: View {
  var body: some View {
    if let settings = TalkifyRuntime.current?.sharedSettings {
      ScrollView {
        ShortcutsSettingsView(settings: settings)
          // The keyboard has a fixed width; with 20 points here the page asks for more
          // than the window's content column and pushes the sidebar narrower than on
          // the other pages.
          .padding(.horizontal, 12)
          .padding(.vertical, 20)
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
