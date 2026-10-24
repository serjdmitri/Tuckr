//
//  WeatherSettings.swift
//  boringNotch
//
//  Settings → Weather.
//

import Defaults
import SwiftUI

struct WeatherSettings: View {
    @ObservedObject private var weather = WeatherService.shared
    @Default(.weatherEnabled) private var enabled
    @Default(.weatherInClosedNotch) private var closedNotch
    @Default(.weatherFahrenheit) private var fahrenheit
    @Default(.weatherCity) private var city

    var body: some View {
        Form {
            Section {
                Toggle("Show the weather", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in Task { await WeatherService.shared.refresh() } }
                Toggle("Also in the closed notch when nothing else is on it", isOn: $closedNotch)
                    .disabled(!enabled)
                Picker("Temperature", selection: $fahrenheit) {
                    Text("°F").tag(true)
                    Text("°C").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(!enabled)
                .onChange(of: fahrenheit) { _, _ in Task { await WeatherService.shared.refresh() } }
                TextField("City (empty: where this Mac is)", text: $city)
                    .disabled(!enabled)
                    .onSubmit { Task { await WeatherService.shared.refresh() } }
            } footer: {
                Text("Shown on the Home page and, if you like, on the closed notch. The numbers come from Open-Meteo; your place is guessed from your internet address unless you type a city, so no location permission is needed. Switch it off and nothing is fetched.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let now = weather.now {
                Section("Now") {
                    HStack {
                        Image(systemName: now.symbol).symbolRenderingMode(.multicolor)
                        Text("\(Int(now.temperature.rounded()))° \(now.summary)\(now.city.isEmpty ? "" : " in \(now.city)")")
                        Spacer()
                        Text("H \(Int(now.high.rounded()))°  L \(Int(now.low.rounded()))°").foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Weather")
    }
}
