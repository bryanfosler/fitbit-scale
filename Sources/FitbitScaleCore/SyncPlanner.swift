import Foundation

public struct SyncPlanner {
    public init() {}

    public func pendingMeasurements(
        remote: [FitbitWeightMeasurement],
        importedLogIDs: Set<String>
    ) -> [FitbitWeightMeasurement] {
        var seen = importedLogIDs

        return remote
            .sorted { $0.timestamp < $1.timestamp }
            .filter { measurement in
                let isNew = !seen.contains(measurement.logID)
                seen.insert(measurement.logID)
                return isNew
            }
    }
}
