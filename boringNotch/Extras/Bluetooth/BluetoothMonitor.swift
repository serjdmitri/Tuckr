//
//  BluetoothMonitor.swift
//  boringNotch
//
//  Watches for Bluetooth devices connecting and, for AirPods and the like, reads their
//  battery level from the system's Bluetooth report. It only does work at the moment a
//  device connects.
//

import CoucouCore
import AppKit
import IOBluetooth

struct BluetoothInfo: Equatable {
    var id = UUID()
    var name: String
    /// An SF Symbol name for the kind of device.
    var symbol: String
    /// Battery percent, nil while unknown or when the device does not report one. For earbuds,
    /// the lower of the two.
    var battery: Int?
    /// Earbuds report each side and the case on its own.
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// False for the "Disconnected" version of the popup.
    var connected = true
}

/// The connection popup's state: what to show and for how long.
@MainActor
final class BluetoothPopup: ObservableObject {
    static let shared = BluetoothPopup()

    @Published private(set) var info: BluetoothInfo?
    private var hideTask: Task<Void, Never>?

    func present(_ info: BluetoothInfo) {
        CoucouHost.react(.wink)
        self.info = info
        scheduleHide(after: 5)
    }

    /// A battery level that arrived after the popup opened: fill the ring in and keep the
    /// popup up a little longer.
    func update(report: BluetoothMonitor.Report, forDeviceNamed name: String) {
        guard let current = info, current.name == name else { return }
        guard current.battery != report.battery || current.left != report.left
            || current.right != report.right || current.caseLevel != report.caseLevel
        else { return }
        info?.battery = report.battery
        info?.left = report.left
        info?.right = report.right
        info?.caseLevel = report.caseLevel
        scheduleHide(after: 4)
    }

    func dismiss() {
        hideTask?.cancel()
        info = nil
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.info = nil
        }
    }
}

final class BluetoothMonitor: NSObject {
    static let shared = BluetoothMonitor()

    private var notification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// The last battery level seen for each device (by address), for the disconnect popup.
    private var lastBattery: [String: Int] = [:]
    private var startedAt = Date()

    /// Call once at launch.
    @MainActor func start() {
        guard notification == nil else { return }
        startedAt = Date()
        notification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        // Devices already connected: watch for them going away too.
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() && !Self.isPhone(device) {
            watchDisconnect(of: device)
        }
    }

    /// Phones come and go all day (Continuity, hotspots): they are not announced.
    static func isPhone(_ device: IOBluetoothDevice) -> Bool {
        let name = (device.name ?? "").lowercased()
        return device.deviceClassMajor == 0x02 || name.contains("iphone")
    }

    private func watchDisconnect(of device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Delivered on a background thread. The notification is spent: a new connection
        // registers a fresh one.
        let name = device.name ?? "Bluetooth device"
        let address = device.addressString ?? ""
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.disconnectNotifications[address]?.unregister()
                self.disconnectNotifications[address] = nil
                self.announceDisconnect(name: name, address: address)
            }
        }
    }

    @MainActor private func announceDisconnect(name: String, address: String) {
        BluetoothPopup.shared.present(
            BluetoothInfo(
                name: name, symbol: Self.symbol(forName: name, kind: nil),
                battery: lastBattery[address], connected: false))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Delivered on a background thread.
        guard !Self.isPhone(device) else { return }
        let name = device.name ?? "Bluetooth device"
        let address = device.addressString ?? ""
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.watchDisconnect(of: device)
                // Devices already connected can be reported as the monitor starts: those are
                // not news.
                guard Date().timeIntervalSince(self.startedAt) > 5 else { return }
                self.announce(name: name, address: address)
            }
        }
    }

    @MainActor private func announce(name: String, address: String) {
        BluetoothPopup.shared.present(
            BluetoothInfo(name: name, symbol: Self.symbol(forName: name, kind: nil), battery: nil))
        // The battery is not always known the moment a device connects: ask again a little
        // later too.
        for delay in [1.2, 4.0] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                let report = await Self.report(name: name, address: address)
                if let report {
                    if let level = report.battery { self.lastBattery[address] = level }
                    BluetoothPopup.shared.update(report: report, forDeviceNamed: name)
                }
            }
        }
    }

    // MARK: - System report

    struct Report { var battery: Int?; var left: Int?; var right: Int?; var caseLevel: Int?; var kind: String? }

    /// Runs `system_profiler SPBluetoothDataType` off the main thread and reads the
    /// connected device's battery.
    static func report(name: String, address: String) async -> Report? {
        await Task.detached(priority: .utility) { () -> Report? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let sections = root["SPBluetoothDataType"] as? [[String: Any]]
            else { return nil }
            for section in sections {
                for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                    for (deviceName, value) in entry {
                        guard let fields = value as? [String: Any] else { continue }
                        let sameAddress = (fields["device_address"] as? String)?.lowercased() == address.lowercased()
                        guard sameAddress || deviceName == name else { continue }
                        func percent(_ key: String) -> Int? {
                            (fields[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
                        }
                        let left = percent("device_batteryLevelLeft"), right = percent("device_batteryLevelRight")
                        let sides = [left, right].compactMap { $0 }
                        // Earbuds: the weaker side tells how long they will last.
                        let level = sides.isEmpty
                            ? (percent("device_batteryLevelMain") ?? percent("device_batteryLevelCase"))
                            : sides.min()
                        return Report(
                            battery: level, left: left, right: right, caseLevel: percent("device_batteryLevelCase"),
                            kind: fields["device_minorType"] as? String)
                    }
                }
            }
            return nil
        }.value
    }

    /// An icon for the kind of device, from its name or its report type.
    static func symbol(forName name: String, kind: String?) -> String {
        let n = name.lowercased(), k = (kind ?? "").lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if k.contains("headphone") || k.contains("headset") || n.contains("buds") || n.contains("headphone") {
            return "headphones"
        }
        if k.contains("keyboard") || n.contains("keyboard") { return "keyboard" }
        if k.contains("mouse") || n.contains("mouse") || n.contains("mx master") { return "computermouse" }
        if k.contains("trackpad") || n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if k.contains("speaker") || n.contains("speaker") || n.contains("homepod") { return "hifispeaker" }
        return "dot.radiowaves.left.and.right"
    }
}
