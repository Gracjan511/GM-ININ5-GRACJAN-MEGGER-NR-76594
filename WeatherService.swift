//
//  WeatherService.swift
//  Pogodynka
//
//  Created by Gracjan Megger on 25/10/2025.
//

import Foundation

// MARK: - Missing Types Added

enum WeatherError: Error, LocalizedError {
    case badURL
    case invalidAPIKey(message: String?)
    case cityNotFound(message: String?)
    case rateLimited(message: String?)
    case server(status: Int, message: String?)
    case decoding(underlying: Error)
    case network(underlying: URLError)
    case unknown(message: String?)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Nieprawidłowy adres URL."
        case .invalidAPIKey(let message):
            return message ?? "Nieprawidłowy klucz API."
        case .cityNotFound(let message):
            return message ?? "Nie znaleziono miasta."
        case .rateLimited(let message):
            return message ?? "Przekroczono limit zapytań. Spróbuj ponownie później."
        case .server(let status, let message):
            return message ?? "Błąd serwera (kod: \(status))."
        case .decoding(let underlying):
            return "Błąd dekodowania danych: \(underlying.localizedDescription)"
        case .network(let underlying):
            return "Błąd sieci: \(underlying.localizedDescription)"
        case .unknown(let message):
            return message ?? "Nieznany błąd."
        }
    }
}

struct OpenWeatherErrorResponse: Decodable {
    // OpenWeather returns "cod" as either Int or String in error payloads
    let cod: String?
    let message: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let intCod = try? container.decode(Int.self, forKey: .cod) {
            self.cod = String(intCod)
        } else {
            self.cod = try? container.decode(String.self, forKey: .cod)
        }

        self.message = try? container.decode(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case cod
        case message
    }
}

// MARK: - API Models

struct WeatherResponse: Codable {
    let name: String
    let main: Main
    let weather: [Weather]
    let wind: Wind
}

struct Main: Codable {
    let temp: Double
    let feelsLike: Double?
    let pressure: Int
   
}

struct Weather: Codable {
    let main: String
    let description: String
    let icon: String
}

struct Wind: Codable {
    let speed: Double
    
}

// MARK: - Service

final class WeatherService {
    private let apiKey = "6772bf335cca534b703ecd07f466b8cd" 

    func fetchWeather(for city: String) async throws -> WeatherResponse {
        guard let cityEscaped = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw WeatherError.badURL
        }

        let urlString = "https://api.openweathermap.org/data/2.5/weather?q=\(cityEscaped)&appid=\(apiKey)&units=metric&lang=pl"
        guard let url = URL(string: urlString) else {
            throw WeatherError.badURL
        }

        #if DEBUG
        print("WeatherService → URL:", url.absoluteString)
        #endif

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WeatherError.unknown(message: "Nieprawidłowa odpowiedź serwera.")
            }

            let status = httpResponse.statusCode

            if status != 200 {
                let messageText = String(data: data, encoding: .utf8)

                #if DEBUG
                print("WeatherService → status:", status)
                if let messageText { print("WeatherService → body:", messageText) }
                #endif

                let apiMessage = (try? JSONDecoder().decode(OpenWeatherErrorResponse.self, from: data).message) ?? messageText

                switch status {
                case 401:
                    throw WeatherError.invalidAPIKey(message: apiMessage)
                case 404:
                    throw WeatherError.cityNotFound(message: apiMessage)
                case 429:
                    throw WeatherError.rateLimited(message: apiMessage)
                default:
                    throw WeatherError.server(status: status, message: apiMessage)
                }
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            do {
                let result = try decoder.decode(WeatherResponse.self, from: data)
                return result
            } catch {
                #if DEBUG
                print("WeatherService → decoding error:", error)
                if let json = String(data: data, encoding: .utf8) {
                    print("WeatherService → raw JSON:", json)
                }
                #endif
                throw WeatherError.decoding(underlying: error)
            }

        } catch {
            if let urlError = error as? URLError {
                throw WeatherError.network(underlying: urlError)
            }
            throw error
        }
    }
}
