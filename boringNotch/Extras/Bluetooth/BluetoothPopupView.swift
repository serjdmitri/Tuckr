//
//  BluetoothPopupView.swift
//  boringNotch
//
//  The connection popup: the closed notch drops down with the device's icon, "Connected",
//  its name and a ring with the battery level.
//

import SwiftUI

struct BluetoothPopupView: View {
    @ObservedObject private var popup = BluetoothPopup.shared
    let chinWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if let info = popup.info {
                let width = max(chinWidth, 340)
                HStack(spacing: 14) {
                    Image(systemName: info.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Connected")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.gray)
                        Text(info.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    BatteryRing(percent: info.battery)
                }
                .padding(.horizontal, 22)
                .padding(.top, notchHeight + 2)
                .padding(.bottom, 14)
                .frame(width: width)
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26)
                        .fill(.black)
                )
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                .transition(
                    .scale(scale: 0.55, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.74), value: popup.info?.id)
    }
}

private struct BatteryRing: View {
    let percent: Int?

    private var tint: Color {
        guard let percent else { return .gray }
        if percent < 10 { return Color(red: 1, green: 0.27, blue: 0.23) }
        if percent < 20 { return Color(red: 1, green: 0.62, blue: 0.16) }
        return Color(red: 0.2, green: 0.82, blue: 0.38)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(percent ?? 0) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percent.map(String.init) ?? "–")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(width: 46, height: 46)
        .animation(.easeOut(duration: 0.6), value: percent)
    }
}
