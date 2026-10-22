import SwiftUI

/// The call recorder in the notch's Meetings tab: record or stop on the left,
/// the latest calls on the right. The full Notetaker page (transcript by
/// speaker, summary, to-dos) opens in its own window.
struct MeetingsTabView: View {
  @ObservedObject private var taker = NoteTaker.shared
  @ObservedObject private var parakeet = Parakeet.shared

  /// The same two-card band as the Agents tab.
  private static let contentSize = CGSize(width: 620, height: 98)

  var body: some View {
    HStack(spacing: 10) {
      CardBackground(wash: nil) {
        recordCard.padding(.horizontal, 14).padding(.vertical, 10)
      }
      .frame(width: 322)

      CardBackground(wash: nil) {
        recentCard.padding(.horizontal, 14).padding(.vertical, 10)
      }
    }
    .frame(width: Self.contentSize.width, height: Self.contentSize.height)
    .foregroundColor(HubTheme.text)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  // MARK: Record

  @ViewBuilder
  private var recordCard: some View {
    if let note = taker.recording {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 8) {
          Circle().fill(HubTheme.red).frame(width: 9, height: 9)
          TimelineView(.periodic(from: note.start, by: 1)) { context in
            Text(NoteBuilder.clock(context.date.timeIntervalSince(note.start)))
              .font(.system(size: 18, weight: .bold).monospacedDigit())
          }
          Spacer()
          Button("Stop") { taker.stop() }
            .buttonStyle(HubButtonStyle(primary: true))
        }
        HStack(spacing: 12) {
          LevelBar(label: "Me", level: taker.micLevel, color: HubTheme.speaker(0))
          LevelBar(label: "Others", level: taker.systemLevel, color: HubTheme.speaker(1))
        }
        Text(note.lines.last?.text ?? "Listening…")
          .font(.system(size: 11))
          .foregroundColor(HubTheme.secondary)
          .lineLimit(1)
      }
    } else {
      VStack(alignment: .leading, spacing: 7) {
        HubRecordButton()
        if let error = taker.startError {
          Text(error)
            .font(.system(size: 11))
            .foregroundColor(HubTheme.red)
            .lineLimit(2)
        } else if !taker.working.isEmpty {
          HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Writing the transcript…")
              .font(.system(size: 11))
              .foregroundColor(HubTheme.secondary)
          }
        } else if !parakeet.isReady {
          Text("Speech models are not set up yet: open Meetings.")
            .font(.system(size: 11))
            .foregroundColor(HubTheme.secondary)
            .lineLimit(2)
        } else {
          Text("Your microphone and what your Mac plays.")
            .font(.system(size: 11))
            .foregroundColor(HubTheme.secondary)
        }
      }
      .frame(maxHeight: .infinity, alignment: .center)
    }
  }

  // MARK: Recent

  private var recentCard: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text("Recent calls")
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button("Open Meetings") { CoucouHost.showMeetings() }
          .buttonStyle(.plain)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(HubTheme.accent)
      }
      if taker.notes.isEmpty {
        Spacer(minLength: 0)
        Text("No calls recorded yet.")
          .font(.system(size: 11))
          .foregroundColor(HubTheme.secondary)
        Spacer(minLength: 0)
      } else {
        ForEach(taker.notes.prefix(3)) { note in
          HStack(spacing: 6) {
            Text(note.title)
              .font(.system(size: 11, weight: .medium))
              .lineLimit(1)
            Spacer(minLength: 4)
            if taker.working.contains(note.id) {
              ProgressView().controlSize(.mini)
            } else if note.status == .failed {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundColor(HubTheme.red)
            } else {
              Text(note.start, format: .relative(presentation: .named))
                .font(.system(size: 10))
                .foregroundColor(HubTheme.muted)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture { CoucouHost.showMeetings() }
        }
        Spacer(minLength: 0)
      }
    }
  }
}

private struct LevelBar: View {
  let label: String
  let level: Float
  let color: Color

  var body: some View {
    HStack(spacing: 6) {
      Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(HubTheme.secondary)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.06))
          Capsule().fill(color)
            .frame(width: max(4, geo.size.width * CGFloat(min(1, sqrt(Double(level)) * 3))))
            .animation(.easeOut(duration: 0.3), value: level)
        }
      }
      .frame(height: 5)
    }
  }
}
