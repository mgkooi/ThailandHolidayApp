import Foundation

enum UITestConfiguration {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }

    static var documentsDirectory: URL? {
        guard isEnabled else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent("ThailandHolidayApp-UITests", isDirectory: true)
    }

    static var selectedDate: Date? {
        guard isEnabled else { return nil }
        return TripCalendar.date(2026, 9, 6, hour: 12)
    }

    static func resetDocumentsIfRequested() {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("--ui-testing-reset"),
              let directory = documentsDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        ["discovery.maxDistance", "discovery.minimumRating", "discovery.minimumReviews", "discovery.openNow"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
