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
