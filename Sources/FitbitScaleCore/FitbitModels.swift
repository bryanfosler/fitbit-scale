import Foundation

public struct FitbitToken: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let scope: String
    public let tokenType: String
    public let userID: String?
    public let expiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String,
        scope: String,
        tokenType: String,
        userID: String?,
        expiresAt: Date
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.scope = scope
        self.tokenType = tokenType
        self.userID = userID
        self.expiresAt = expiresAt
    }

    public var needsRefresh: Bool {
        expiresAt <= Date().addingTimeInterval(120)
    }
}

public struct FitbitWeightMeasurement: Codable, Hashable, Identifiable {
    public let logID: String
    public let timestamp: Date
    public let value: Double
    public let unit: MassUnit
    public let source: String?

    public init(
        logID: String,
        timestamp: Date,
        value: Double,
        unit: MassUnit,
        source: String?
    ) {
        self.logID = logID
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.source = source
    }

    public var id: String { logID }

    public var kilograms: Double {
        unit.toKilograms(value)
    }
}

struct FitbitTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String
    let tokenType: String
    let userID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
        case userID = "user_id"
    }

    func makeToken(now: Date = Date()) -> FitbitToken {
        FitbitToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            scope: scope,
            tokenType: tokenType,
            userID: userID,
            expiresAt: now.addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}

struct FitbitWeightLogResponse: Decodable {
    let weight: [FitbitWeightEntry]
}

struct FitbitWeightEntry: Decodable {
    let date: String
    let logID: Int64
    let source: String?
    let time: String
    let weight: Double

    enum CodingKeys: String, CodingKey {
        case date
        case logID = "logId"
        case source
        case time
        case weight
    }
}

struct FitbitAPIErrorEnvelope: Decodable {
    let errors: [FitbitAPIErrorItem]
}

struct FitbitAPIErrorItem: Decodable {
    let message: String
}
