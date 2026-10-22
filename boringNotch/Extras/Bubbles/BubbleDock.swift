//
//  BubbleDock.swift
//  boringNotch
//
//  Live items (so far the timer) shown as round bubbles beside the closed notch, one on
//  each side, level with it. A bubble rises out of the notch's edge like a drop of the
//  same black liquid and, when it goes, sinks back into it.
//

import SwiftUI

/// Which items have a bubble. The first takes the right side, the second the left; a
/// third waits for a free side.
@MainActor
final class BubbleDock: ObservableObject {
    static let shared = BubbleDock()

    @Published private(set) var items: [String] = []

    func show(_ id: String) {
        guard !items.contains(id), items.count < 2 else { return }
        items.append(id)
    }

    func hide(_ id: String) {
        items.removeAll { $0 == id }
    }
}

struct BubbleDockView: View {
    @ObservedObject private var dock = BubbleDock.shared
    /// False while the notch is open or hidden: the bubbles sink back in.
    let visible: Bool
    /// The closed notch's width, ears included.
    let chinWidth: CGFloat
    let height: CGFloat
    let onSelect: (String) -> Void

    // 0: sunk into the notch's edge; 1: at rest beside it. Spring overshoot gives the stretch.
    @State private var tRight: CGFloat = 0
    @State private var tLeft: CGFloat = 0
    // The item a side last showed, kept while its bubble sinks back.
    @State private var rightID: String?
    @State private var leftID: String?

    private var diameter: CGFloat { max(22, height - 4) }
    private let gap: CGFloat = 7
    private var span: CGFloat { gap + diameter + 14 }

    private var rightWanted: String? { visible ? dock.items.first : nil }
    private var leftWanted: String? { visible && dock.items.count > 1 ? dock.items[1] : nil }

    var body: some View {
        ZStack {
            GooLayer(
                tLeft: tLeft, tRight: tRight, chin: chinWidth, height: height,
                diameter: diameter, gap: gap)
            bubble(id: rightID, t: tRight, direction: 1)
            bubble(id: leftID, t: tLeft, direction: -1)
        }
        .frame(width: chinWidth + 2 * span, height: height)
        .onChange(of: rightWanted, initial: true) { _, id in move(&rightID, t: &tRight, to: id) }
        .onChange(of: leftWanted, initial: true) { _, id in move(&leftID, t: &tLeft, to: id) }
    }

    private func move(_ shownID: inout String?, t: inout CGFloat, to id: String?) {
        if let id { shownID = id }
        let target: CGFloat = id == nil ? 0 : 1
        // Out only once the notch has finished closing; back in at once as it opens.
        let spring = Animation.spring(response: 0.55, dampingFraction: 0.58)
        withAnimation(target == 1 ? spring.delay(0.6) : spring) {
            t = target
        }
    }

    @ViewBuilder
    private func bubble(id: String?, t: CGFloat, direction: CGFloat) -> some View {
        if let id, t > 0.02 {
            let x = direction * (chinWidth / 2 + (gap + diameter / 2) * t - diameter / 2 * (1 - t) * 0.3)
            content(for: id)
                .frame(width: diameter, height: diameter)
                .scaleEffect(min(1, max(0, t)))
                .opacity(min(1, max(0, (t - 0.3) / 0.5)))
                .contentShape(Circle())
                .onTapGesture { onSelect(id) }
                .offset(x: x)
        }
    }

    @ViewBuilder
    private func content(for id: String) -> some View {
        switch id {
        case "timer": TimerGlyph(size: 15)
        default: EmptyView()
        }
    }
}

/// The notch's black, drawn as liquid: circles and each side's edge are blurred together
/// and cut back to a hard edge, so a bubble stretches a neck to the notch as it leaves and
/// is drawn back in as it returns.
private struct GooLayer: View, Animatable {
    var tLeft: CGFloat
    var tRight: CGFloat
    let chin: CGFloat
    let height: CGFloat
    let diameter: CGFloat
    let gap: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(tLeft, tRight) }
        set { tLeft = newValue.first; tRight = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            guard tLeft > 0.01 || tRight > 0.01 else { return }
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: 3.5))
            context.drawLayer { layer in
                let midX = size.width / 2
                let midY = size.height / 2
                for (t, direction) in [(tRight, CGFloat(1)), (tLeft, CGFloat(-1))] where t > 0.01 {
                    let edge = midX + direction * chin / 2
                    // The notch's own edge, so the neck has something to hold on to.
                    let anchorWidth: CGFloat = 16
                    // Held a little inside the edge, so the blur does not bulge the notch.
                    let inset: CGFloat = 3
                    let anchor = CGRect(
                        x: direction > 0 ? edge - anchorWidth - inset : edge + inset,
                        y: midY - height * 0.32, width: anchorWidth, height: height * 0.64)
                    layer.fill(Path(anchor), with: .color(.black))
                    let r = diameter / 2
                    let cx = edge + direction * ((gap + r) * t - r * (1 - t) * 0.3)
                    layer.fill(
                        Path(ellipseIn: CGRect(x: cx - r, y: midY - r, width: diameter, height: diameter)),
                        with: .color(.black))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
