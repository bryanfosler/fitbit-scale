import Foundation

public enum FitbitError: LocalizedError {
    case invalidResponse
    case invalidURL
    case invalidAuthorizationCallback
    case missingAuthorizationCode
    case missingBodyWeightData
    case apiError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Fitbit returned a response the app could not understand."
        case .invalidURL:
            return "The Fitbit request URL could not be created."
        case .invalidAuthorizationCallback:
            return "The Fitbit login flow returned an unexpected callback."
        case .missingAuthorizationCode:
            return "Fitbit did not include an authorization code in the callback."
        case .missingBodyWeightData:
            return "Fitbit did not return any weight log data."
        case .apiError(let statusCode, let message):
            return "Fitbit API error \(statusCode): \(message)"
        }
    }
}
