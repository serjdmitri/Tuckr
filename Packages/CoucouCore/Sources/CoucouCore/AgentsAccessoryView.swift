import SwiftUI

/// What Coucou's own header carries on the right of its overview: the Claude or
/// Codex plan pill (when switched on in Agents Settings) and the sound switch.
struct AgentsAccessoryView: View {
  @ObservedObject private var state = AppState.shared

  var body: some View {
    HStack(spacing: 6) {
      if state.view == .overview && state.showPlanInNotch && state.planRelayInstalled {
        ClaudePlanHeaderPill(state: state)
      } else if state.view == .overview && state.showCodexPlanInNotch {
        ClaudePlanHeaderPill(state: state, codex: true)
      }
      Button {
        state.soundEnabled.toggle()
      } label: {
        Capsule()
          .fill(.black)
          .frame(width: 30, height: 30)
          .overlay {
            Image(systemName: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
              .foregroundColor(.white)
              .imageScale(.medium)
          }
      }
      .buttonStyle(.plain)
      .help(state.soundEnabled ? "Mute Mochi's sounds" : "Unmute Mochi's sounds")
    }
  }
}
