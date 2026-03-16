import Testing
@testable import FitbitScaleCore

struct SyncPlannerTests {
    @Test func filtersAlreadyImportedAndDuplicateMeasurements() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let planner = SyncPlanner()
        let remote = [
            FitbitWeightMeasurement(logID: "1", timestamp: timestamp, value: 180, unit: .pounds, source: "Aria"),
            FitbitWeightMeasurement(logID: "1", timestamp: timestamp, value: 180, unit: .pounds, source: "Aria"),
            FitbitWeightMeasurement(logID: "2", timestamp: timestamp.addingTimeInterval(60), value: 179.5, unit: .pounds, source: "Aria")
        ]

        let pending = planner.pendingMeasurements(
            remote: remote,
            importedLogIDs: ["1"]
        )

        #expect(pending.count == 1)
        #expect(pending.first?.logID == "2")
    }

    @Test func convertsPoundsToKilograms() {
        let measurement = FitbitWeightMeasurement(
            logID: "abc",
            timestamp: Date(timeIntervalSince1970: 0),
            value: 180,
            unit: .pounds,
            source: nil
        )

        #expect(abs(measurement.kilograms - 81.6466266) < 0.000001)
    }

    @Test func buildsAuthorizationURLWithPKCEChallenge() throws {
        let configuration = FitbitOAuthConfiguration(
            clientID: "client-id",
            redirectURI: URL(string: "fitbitscalesync://auth/callback")!
        )

        let url = try configuration.authorizationURL(
            state: "state-123",
            codeChallenge: "challenge"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(items["client_id"] == "client-id")
        #expect(items["state"] == "state-123")
        #expect(items["code_challenge"] == "challenge")
        #expect(items["scope"] == "weight profile")
    }
}
