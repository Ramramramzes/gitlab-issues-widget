import Foundation

enum IssueDay {
    static func interval(on date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateInterval(of: .day, for: date)!
    }

    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func closedToday(_ issues: [Issue], on date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> [Issue] {
        let day = interval(on: date, timeZone: timeZone)
        return issues.filter {
            guard $0.state == "closed", let value = $0.closedAt, let closed = parse(value) else { return false }
            return closed >= day.start && closed < day.end
        }.sorted { parse($0.closedAt!)! > parse($1.closedAt!)! }
    }
}
