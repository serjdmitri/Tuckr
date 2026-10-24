//
//  WeatherService.swift
//  The weather for the notch. Open-Meteo gives the numbers (no account, no key). Where you are
//  comes from your IP address, or from a city typed in Settings, so no location permission is
//  asked for. Off by default if you switch it off: nothing is fetched then.
//

import Defaults
import Foundation
import SwiftUI

struct WeatherNow: Equatable {
    var temperature: Double
    var code: Int
    var isDay: Bool
    var high: Double
    var low: Double
    var city: String

    /// An SF Symbol for the WMO weather code.
    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var summary: String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67, 80...82: return "Rain"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }
}

@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published private(set) var now: WeatherNow?

    private var timer: Timer?
    private var place: (lat: Double, lon: Double, city: String, at: Date, query: String)?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { _ in
            Task { @MainActor in await WeatherService.shared.refresh() }
        }
        Task { await refresh() }
    }

    /// Looks again now (the settings changed, or it is time).
    func refresh() async {
        guard Defaults[.weatherEnabled] else { now = nil; return }
        let query = Defaults[.weatherCity].trimmingCharacters(in: .whitespaces)
        guard let location = await locate(query: query) else { return }
        let fahrenheit = Defaults[.weatherFahrenheit]
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(location.lat)"),
            URLQueryItem(name: "longitude", value: "\(location.lon)"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temperature = current["temperature_2m"] as? Double,
              let code = current["weather_code"] as? Int
        else { return }
        let daily = json["daily"] as? [String: Any]
        let high = (daily?["temperature_2m_max"] as? [Double])?.first ?? temperature
        let low = (daily?["temperature_2m_min"] as? [Double])?.first ?? temperature
        now = WeatherNow(
            temperature: temperature, code: code, isDay: (current["is_day"] as? Int ?? 1) == 1,
            high: high, low: low, city: location.city)
    }

    /// Where to ask about: the city typed in Settings, or the one the IP address points to.
    private func locate(query: String) async -> (lat: Double, lon: Double, city: String)? {
        if let place, place.query == query, Date().timeIntervalSince(place.at) < 6 * 3600 {
            return (place.lat, place.lon, place.city)
        }
        var found: (Double, Double, String)?
        if query.isEmpty {
            if let url = URL(string: "https://ipwho.is/"),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double {
                found = (lat, lon, json["city"] as? String ?? "")
            }
        } else {
            var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "1")]
            if let url = components.url,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let first = (json["results"] as? [[String: Any]])?.first,
               let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double {
                found = (lat, lon, first["name"] as? String ?? query)
            }
        }
        guard let found else { return nil }
        place = (found.0, found.1, found.2, Date(), query)
        return found
    }
}

/// "☀︎ 75°", for the header on the Home page.
struct WeatherChip: View {
    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        if let now = weather.now {
            HStack(spacing: 5) {
                Image(systemName: now.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13))
                Text("\(Int(now.temperature.rounded()))°")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .fixedSize()
            .background(Capsule().fill(Color.black))
            .help("\(now.city.isEmpty ? "" : now.city + ": ")\(now.summary), high \(Int(now.high.rounded()))°, low \(Int(now.low.rounded()))°")
        }
    }
}

/// The closed notch when nothing else is going on: the sky on one side, the temperature on the other.
struct ClosedWeather: View {
    @ObservedObject private var weather = WeatherService.shared
    let notchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        if let now = weather.now {
            let ear = max(0, height - 12)
            HStack(spacing: 0) {
                Image(systemName: now.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: ear * 0.8))
                    .frame(width: ear + 10, height: ear)
                Rectangle().fill(.black).frame(width: notchWidth - 20)
                Text("\(Int(now.temperature.rounded()))°")
                    .font(.system(size: ear * 0.7, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: ear + 10, height: ear)
            }
            .frame(height: height, alignment: .center)
        }
    }
}
