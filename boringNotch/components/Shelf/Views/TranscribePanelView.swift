//
//  TranscribePanelView.swift
//  boringNotch
//
//  The Shelf's third panel: drop an audio or video file to have Talkify
//  transcribe it. The finished transcript appears on Talkify's own HUD card.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class TranscribeProgress: ObservableObject {
    static let shared = TranscribeProgress()

    /// 0...1 while a file is being transcribed, nil otherwise.
    @Published var fraction: Double?
}

struct TranscribePanelView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var progress = TranscribeProgress.shared
    @Environment(\.shelfPanelCompact) private var compact
    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                isTargeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            .onChange(of: isTargeted) { _, on in ShelfPanelFocus.shared.setTargeted(.transcribe, on) }
            .onTapGesture {
                TalkifyRuntime.current?.pickTranscriptionFile()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let fraction = progress.fraction {
            VStack(spacing: 10) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                Text("Transcribing… \(Int(fraction * 100))%")
                    .foregroundStyle(.gray)
                    .font(.system(.subheadline, design: .rounded))
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, .gray)
                    .imageScale(.large)

                if !compact {
                    Text("Transcribe")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)

                    Text("Drop audio or video")
                        .foregroundStyle(.gray.opacity(0.7))
                        .font(.system(.caption, design: .rounded))
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                vm.dropEvent = true
                TalkifyRuntime.current?.transcribeDropped(url)
            }
        }
        return true
    }
}
