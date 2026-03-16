import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class FitbitAPIClient {
    private let httpClient: HTTPClient
    private let decoder = JSONDecoder()

    public init(httpClient: HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    public func exchangeCode(
        _ code: String,
        codeVerifier: String?,
        configuration: FitbitOAuthConfiguration
    ) async throws -> FitbitToken {
        try await tokenRequest(
            parameters: [
                "code": code,
                "grant_type": "authorization_code",
                "redirect_uri": configuration.redirectURI.absoluteString,
                "client_id": configuration.clientID,
                "code_verifier": codeVerifier
            ],
            configuration: configuration
        )
    }

    public func refreshToken(
        _ token: FitbitToken,
        configuration: FitbitOAuthConfiguration
    ) async throws -> FitbitToken {
        try await tokenRequest(
            parameters: [
                "grant_type": "refresh_token",
                "refresh_token": token.refreshToken,
                "client_id": configuration.clientID
            ],
            configuration: configuration
        )
    }

    public func fetchWeights(
        startDate: Date,
        endDate: Date,
        token: FitbitToken,
        unit: MassUnit,
        timeZone: TimeZone = .current
    ) async throws -> [FitbitWeightMeasurement] {
        let startString = FitbitDateCoding.pathDateString(from: startDate, timeZone: timeZone)
        let endString = FitbitDateCoding.pathDateString(from: endDate, timeZone: timeZone)

        guard let url = URL(string: "https://api.fitbit.com/1/user/-/body/log/weight/date/\(startString)/\(endString).json") else {
            throw FitbitError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)

        let payload = try decoder.decode(FitbitWeightLogResponse.self, from: data)

        return try payload.weight
            .map {
                FitbitWeightMeasurement(
                    logID: String($0.logID),
                    timestamp: try FitbitDateCoding.parseTimestamp(
                        dateString: $0.date,
                        timeString: $0.time,
                        timeZone: timeZone
                    ),
                    value: $0.weight,
                    unit: unit,
                    source: $0.source
                )
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func tokenRequest(
        parameters: [String: String?],
        configuration: FitbitOAuthConfiguration
    ) async throws -> FitbitToken {
        guard let url = URL(string: "https://api.fitbit.com/oauth2/token") else {
            throw FitbitError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        if let clientSecret = configuration.clientSecret, !clientSecret.isEmpty {
            let credentials = "\(configuration.clientID):\(clientSecret)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let body = parameters
            .compactMap { key, value -> String? in
                guard let value else { return nil }
                return "\(formURLEncode(key))=\(formURLEncode(value))"
            }
            .joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)

        let tokenResponse = try decoder.decode(FitbitTokenResponse.self, from: data)
        return tokenResponse.makeToken()
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            let message = apiErrorMessage(from: data)
            throw FitbitError.apiError(statusCode: response.statusCode, message: message)
        }
    }

    private func apiErrorMessage(from data: Data) -> String {
        if let envelope = try? decoder.decode(FitbitAPIErrorEnvelope.self, from: data),
           let message = envelope.errors.first?.message {
            return message
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "Unknown Fitbit error"
    }

    private func formURLEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "+") ?? value
    }
}
