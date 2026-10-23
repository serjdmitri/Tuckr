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
                        .opacity(info.connected ? 1 : 0.4)
                        .overlay { if !info.connected { Slash() } }
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.connected ? "Connected" : "Disconnected")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(info.connected ? Color.gray : Color(red: 1, green: 0.42, blue: 0.38))
                        Text(info.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if info.connected, info.left != nil || info.right != nil || info.caseLevel != nil {
                            // Earbuds: each side and the case.
                            HStack(spacing: 10) {
                                part("L", info.left)
                                part("R", info.right)
                                part("Case", info.caseLevel)
                            }
                            .padding(.top, 3)
                        }
                    }
                    Spacer(minLength: 8)
                    BatteryRing(percent: info.connected ? info.battery : nil, drained: !info.connected,
                                lastPercent: info.battery)
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

extension BluetoothPopupView {
    @ViewBuilder
    fileprivate func part(_ label: String, _ percent: Int?) -> some View {
        if let percent {
            HStack(spacing: 3) {
                Text(label).foregroundStyle(.gray)
                Text("\(percent)%")
                    .foregroundStyle(percent < 20 ? Color(red: 1, green: 0.62, blue: 0.16) : .white)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }
}

/// A diagonal stroke that draws itself across the icon when a device goes away.
private struct Slash: View {
    @State private var drawn: CGFloat = 0

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 4, y: 4))
            path.addLine(to: CGPoint(x: 40, y: 36))
        }
        .trim(from: 0, to: drawn)
        .stroke(Color(red: 1, green: 0.42, blue: 0.38), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        .frame(width: 44, height: 40)
        .onAppear { withAnimation(.easeOut(duration: 0.45).delay(0.25)) { drawn = 1 } }
    }
}

private struct BatteryRing: View {
    let percent: Int?
    /// The "Disconnected" version: the ring empties and a cross takes the number's place.
    var drained = false
    var lastPercent: Int?
    @State private var level: CGFloat = 0

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
                .trim(from: 0, to: drained ? level : CGFloat(percent ?? 0) / 100)
                .stroke(drained ? Color.gray : tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if drained {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.38))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(percent.map(String.init) ?? "–")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 46, height: 46)
        .animation(.easeOut(duration: 0.6), value: percent)
        .onAppear {
            guard drained else { return }
            // Starts at the last level seen and runs down to empty.
            level = CGFloat(lastPercent ?? 100) / 100
            withAnimation(.easeIn(duration: 0.9).delay(0.2)) { level = 0 }
        }
    }
}
