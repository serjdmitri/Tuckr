import SwiftUI

/// Agents Settings, Notetaker: where the recording pill sits on screen and
/// who writes the summaries. In the standalone Coucou these two lived on the
/// Coucou Flow settings page, which this app does not have.
struct NotetakerSettingsSection: View {
  @ObservedObject private var flow = FlowDictation.shared
  @ObservedObject private var taker = NoteTaker.shared

  var body: some View {
    GroupBox("Recording pill") {
      VStack(alignment: .leading, spacing: 10) {
        Text("The small pill that shows a call being recorded and says when the notes are ready.")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
          Text(String(localized: "flow.edge"))
          Picker("", selection: $flow.pillEdge) {
            ForEach(FlowPillEdge.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
        }
      }
      .padding(6)
    }

    GroupBox("Summaries") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Text(String(localized: "notes.engine"))
          Picker("", selection: $taker.summaryEngine) {
            ForEach(NoteSummaryEngine.allCases) { Text($0.label).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
        }
        Text("Apple Intelligence writes them on this Mac. Claude sends the transcript to Anthropic and needs your key, saved in the Chat section.")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(6)
    }
  }
}
