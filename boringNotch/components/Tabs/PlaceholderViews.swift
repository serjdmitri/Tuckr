//
//  PlaceholderViews.swift
//  boringNotch
//
//  Stand-ins for the tabs and shelf panels that later steps fill in.
//

import SwiftUI

struct TabPlaceholderView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .imageScale(.large)
                .foregroundStyle(.white, .gray)
            Text(title)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TranscribePanelPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)

                    Text("Transcribe")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
                .padding()
            }
    }
}
