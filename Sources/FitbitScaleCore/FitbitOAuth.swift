import Foundation

public struct FitbitOAuthConfiguration {
    public static let defaultRedirectURI = URL(string: "fitbitscalesync://auth/callback")!

    public let clientID: String
    public let clientSecret: String?
    public let redirectURI: URL
    public let scopes: [String]

    public init(
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: URL = Self.defaultRedirectURI,
        scopes: [String] = ["weight", "profile"]
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    public func authorizationURL(
        state: String,
        codeChallenge: String? = nil
    ) throws -> URL {
        var components = URLComponents(string: "https://www.fitbit.com/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]

        if let codeChallenge {
            components?.queryItems?.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
            components?.queryItems?.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }

        guard let url = components?.url else {
            throw FitbitError.invalidURL
        }

        return url
    }
}
