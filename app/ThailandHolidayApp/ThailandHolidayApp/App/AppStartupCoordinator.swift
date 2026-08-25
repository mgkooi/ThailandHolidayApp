import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppStartupCoordinator {
    private static let logger = Logger(subsystem: "nl.martijnkooi.ThailandHolidayApp", category: "Startup")

    private(set) var progress = 0.0
    private(set) var statusText = "App starten…"
    private(set) var isReady = false
    private(set) var errorMessage: String?

    private var isStarting = false
    private(set) var progressHistory: [Double] = [0]

    func start(tripStore: TripStore) async {
        guard !isStarting else { return }
        isStarting = true
        isReady = false
        errorMessage = nil
        setProgress(0.05, status: "App starten…", allowReset: true)
        await Task.yield()

        setProgress(0.20, status: "Reisgegevens voorbereiden…")
        await Task.yield()
        tripStore.load()
        guard tripStore.trip != nil, tripStore.errorMessage == nil else {
            fail("De reisgegevens konden niet worden geladen.")
            return
        }

        setProgress(0.55, status: "Reisgegevens laden…")
        await Task.yield()
        do {
            setProgress(0.70, status: "Boekingsbijlagen voorbereiden…")
            try tripStore.prepareAttachmentsDirectory()
        } catch {
            Self.logger.error("Attachments voorbereiden mislukt: \(error.localizedDescription, privacy: .public)")
            fail("De boekingsbijlagen konden niet worden voorbereid.")
            return
        }

        await Task.yield()
        setProgress(0.85, status: "Planning opbouwen…")
        _ = tripStore.timelineSections()

        await Task.yield()
        setProgress(0.96, status: "Laatste voorbereidingen…")
        await Task.yield()
        setProgress(1, status: "Klaar")
        isStarting = false
        isReady = true
    }

    func retry(tripStore: TripStore) async {
        isStarting = false
        await start(tripStore: tripStore)
    }

    private func setProgress(_ value: Double, status: String, allowReset: Bool = false) {
        let bounded = min(1, max(0, value))
        progress = allowReset ? bounded : max(progress, bounded)
        statusText = status
        progressHistory.append(progress)
    }

    private func fail(_ message: String) {
        errorMessage = message
        isStarting = false
        isReady = false
        Self.logger.error("Startup mislukt: \(message, privacy: .public)")
    }
}
