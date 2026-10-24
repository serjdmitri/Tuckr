//
//  CallPopup.swift
//  An incoming call (FaceTime, a phone call from your iPhone, WhatsApp) said in the notch: who
//  is calling, and buttons to answer or decline. macOS shows a call as an alert with its own
//  Answer and Decline buttons; the notch's buttons press those, so the alert has to stay. The
//  popup goes when the alert does, or after a minute.
//

import AppKit
import ApplicationServices
import Defaults
import SwiftUI

struct IncomingCall: Identifiable {
    let id = UUID()
    let appID: String
    let appName: String
    let caller: String
    let detail: String
    let alert: AXUIElement
    let answer: String
    let decline: String
}

@MainActor
final class CallPopup: ObservableObject {
    static let shared = CallPopup()

    @Published private(set) var call: IncomingCall?
    private var watch: Task<Void, Never>?

    /// The apps whose calls show here, by the name macOS gives them.
    private static let apps: [String: String] = [
        "facetime": "com.apple.facetime", "phone": "com.apple.mobilephone",
        "messages": "com.apple.mobilesms", "whatsapp": "net.whatsapp.whatsapp",
    ]

    /// Called for every alert the Notification Center shows. True when it is a call.
    func consider(appName: String, title: String, subtitle: String, body: String, alert: AXUIElement, actions: [String]) -> Bool {
        guard Defaults[.activityCalls], let appID = Self.apps[appName.lowercased()] else { return false }
        let answer = actions.first { let a = $0.lowercased(); return a.hasPrefix("name:accept") || a.hasPrefix("name:answer") }
        let decline = actions.first { $0.lowercased().hasPrefix("name:decline") }
        guard let answer, let decline else { return false }
        let detail = [subtitle, body].filter { !$0.isEmpty }.joined(separator: " · ")
        call = IncomingCall(
            appID: appID, appName: NotificationFeed.name(for: appID), caller: title.isEmpty ? appName : title,
            detail: detail.isEmpty ? "Incoming call" : detail, alert: alert, answer: answer, decline: decline)
        watchAlert()
        return true
    }

    func answer() { press(\.answer) }
    func decline() { press(\.decline) }

    private func press(_ action: KeyPath<IncomingCall, String>) {
        guard let call else { return }
        AXUIElementPerformAction(call.alert, call[keyPath: action] as CFString)
        dismiss()
    }

    func dismiss() {
        watch?.cancel()
        call = nil
    }

    /// The popup leaves with the alert: when it is answered on the Mac or the caller hangs up.
    private func watchAlert() {
        watch?.cancel()
        let mine = call?.id
        watch = Task { @MainActor [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, let call = self.call, call.id == mine else { return }
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(call.alert, kAXRoleAttribute as CFString, &value) != .success { break }
            }
            guard let self, self.call?.id == mine else { return }
            self.dismiss()
        }
    }
}

struct CallPopupView: View {
    @ObservedObject private var popup = CallPopup.shared
    let chinWidth: CGFloat
    let notchHeight: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .top) {
            if let call = popup.call {
                HStack(spacing: 14) {
                    Image(nsImage: NotificationFeed.icon(for: call.appID))
                        .resizable().interpolation(.high).frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.2, green: 0.82, blue: 0.38), lineWidth: 2)
                                .scaleEffect(pulse ? 1.25 : 1).opacity(pulse ? 0 : 0.9)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(call.detail)
                            .font(.system(size: 13)).foregroundStyle(.gray).lineLimit(1)
                        Text(call.caller)
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        Text(call.appName)
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    button("phone.down.fill", Color(red: 1, green: 0.27, blue: 0.23), "Decline") { popup.decline() }
                    button("phone.fill", Color(red: 0.2, green: 0.78, blue: 0.35), "Answer") { popup.answer() }
                }
                .padding(.horizontal, 22)
                .padding(.top, notchHeight + 2)
                .padding(.bottom, 14)
                .frame(width: max(chinWidth, 400))
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26).fill(.black))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                .transition(.scale(scale: 0.55, anchor: .top).combined(with: .opacity))
                .onAppear { withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true } }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.74), value: popup.call?.id)
    }

    private func button(_ symbol: String, _ color: Color, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(color))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
