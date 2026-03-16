import Foundation

enum FitbitDateCoding {
    static func parseTimestamp(
        dateString: String,
        timeString: String,
        timeZone: TimeZone
    ) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        guard let date = formatter.date(from: "\(dateString) \(timeString)") else {
            throw FitbitError.invalidResponse
        }

        return date
    }

    static func pathDateString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
