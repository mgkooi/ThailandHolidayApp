import Foundation
import OSLog
import UniformTypeIdentifiers

extension UTType {
    static let tripArchive = UTType(exportedAs: "nl.martijnkooi.ThailandHolidayApp.triparchive",
                                    conformingTo: .package)
}

struct TripArchiveManifest: Codable, Equatable {
    static let currentSchemaVersion = 2
    let schemaVersion: Int
    let exportedAt: Date
    var trip: Trip
    var nearbySuggestions: [NearbySuggestion]?
    var favorites: [Favorite]?
}

struct TripImportPreview: Identifiable {
    let archiveURL: URL
    let manifest: TripArchiveManifest
    var id: UUID { manifest.trip.id }
    var dayCount: Int {
        let calendar = TripCalendar.calendar(in: manifest.trip.timeZone)
        return max(1, (calendar.dateComponents([.day], from: manifest.trip.startDate,
                                                to: manifest.trip.endDate).day ?? 0) + 1)
    }
    var imageCount: Int { manifest.trip.allMedia.filter { $0.filename != nil }.count }
}

enum TripImportStrategy { case copy, replace }

enum TripArchiveError: LocalizedError {
    case invalidPackage
    case missingManifest
    case corruptManifest(String)
    case unsupportedVersion(Int)
    case cannotAccessDocument
    case cannotCopyDocument(String)
    case missingMedia(String)
    var errorDescription: String? {
        switch self {
        case .invalidPackage: "Dit bestand is geen geldig reisarchief of oude reisexportmap."
        case .missingManifest: "Het reisarchief bevat geen trip.json."
        case .corruptManifest(let reason): "trip.json kon niet worden gelezen: \(reason)"
        case .unsupportedVersion(let version): "Deze reis gebruikt een nog niet ondersteunde versie (\(version))."
        case .cannotAccessDocument: "De app heeft geen toegang tot het gekozen reisbestand. Download het bestand in Bestanden en probeer opnieuw."
        case .cannotCopyDocument(let reason): "Het reisbestand kon niet lokaal worden voorbereid: \(reason)"
        case .missingMedia(let name): "Afbeelding \(name) ontbreekt in het reisbestand."
        }
    }
}

struct TripArchiveService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThailandHolidayApp",
                                       category: "TripArchive")
    private let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func export(trip: Trip, nearbySuggestions: [NearbySuggestion] = [], favorites: [Favorite] = [],
                attachmentStore: AttachmentStore, destinationDirectory: URL) throws -> URL {
        let safeName = trip.name.replacingOccurrences(of: "[^A-Za-z0-9À-ÿ _-]", with: "-",
                                                       options: .regularExpression).nilIfBlank ?? "Reis"
        let package = destinationDirectory.appendingPathComponent("\(safeName).triparchive", isDirectory: true)
        if fileManager.fileExists(atPath: package.path) { try fileManager.removeItem(at: package) }
        let mediaDirectory = package.appendingPathComponent("media", isDirectory: true)
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        for filename in localFilenames(in: trip) {
            let source = attachmentStore.imageURL(for: filename)
            guard fileManager.fileExists(atPath: source.path) else {
                Self.logger.warning("Skipping unavailable local media \(filename, privacy: .private)")
                continue
            }
            try fileManager.copyItem(at: source, to: mediaDirectory.appendingPathComponent(filename))
        }
        let manifest = TripArchiveManifest(schemaVersion: TripArchiveManifest.currentSchemaVersion,
                                           exportedAt: .now, trip: trip,
                                           nearbySuggestions: nearbySuggestions, favorites: favorites)
        try TripJSONCoding.encoder().encode(manifest).write(
            to: package.appendingPathComponent("trip.json"), options: .atomic)
        Self.logger.info("Exported trip with \(trip.allMedia.count, privacy: .public) media records")
        return package
    }

    func stageImport(from source: URL, temporaryDirectory: URL = .temporaryDirectory,
                     accessSecurityScope: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
                     stopSecurityScope: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) throws -> URL {
        let accessed = accessSecurityScope(source)
        defer { if accessed { stopSecurityScope(source) } }

        do { try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true) }
        catch { throw TripArchiveError.cannotCopyDocument(error.localizedDescription) }
        let suffix = source.pathExtension.nilIfBlank.map { ".\($0)" } ?? ".triparchive"
        let destination = temporaryDirectory
            .appendingPathComponent("Imported-\(UUID().uuidString)\(suffix)", isDirectory: isDirectory(source))
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [.withoutChanges],
                                                          error: &coordinationError) { coordinatedURL in
            do {
                if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
                try fileManager.copyItem(at: coordinatedURL, to: destination)
            } catch { copyError = error }
        }
        if let coordinationError {
            if !fileManager.isReadableFile(atPath: source.path) { throw TripArchiveError.cannotAccessDocument }
            throw TripArchiveError.cannotCopyDocument(coordinationError.localizedDescription)
        }
        if let copyError { throw TripArchiveError.cannotCopyDocument(copyError.localizedDescription) }
        guard fileManager.fileExists(atPath: destination.path) else { throw TripArchiveError.cannotAccessDocument }
        return destination
    }

    func preview(url: URL) throws -> TripImportPreview {
        let manifestURL: URL
        if isDirectory(url) {
            manifestURL = url.appendingPathComponent("trip.json", isDirectory: false)
            guard fileManager.fileExists(atPath: manifestURL.path) else { throw TripArchiveError.missingManifest }
        } else if url.lastPathComponent == "trip.json" || url.pathExtension.lowercased() == "json" {
            manifestURL = url
        } else {
            throw TripArchiveError.invalidPackage
        }
        let data: Data
        do { data = try Data(contentsOf: manifestURL) }
        catch { throw TripArchiveError.corruptManifest("bestand is niet leesbaar (\(error.localizedDescription))") }
        let manifest: TripArchiveManifest
        do { manifest = try TripJSONCoding.decoder().decode(TripArchiveManifest.self, from: data) }
        catch { throw TripArchiveError.corruptManifest(error.localizedDescription) }
        guard manifest.schemaVersion <= TripArchiveManifest.currentSchemaVersion else {
            throw TripArchiveError.unsupportedVersion(manifest.schemaVersion)
        }
        return TripImportPreview(archiveURL: url, manifest: manifest)
    }

    func importedTrip(from preview: TripImportPreview, attachmentStore: AttachmentStore) throws -> Trip {
        var trip = preview.manifest.trip
        let mediaDirectory = preview.archiveURL.appendingPathComponent("media", isDirectory: true)
        try attachmentStore.prepareDirectory()
        var replacements: [String: String] = [:]
        for filename in localFilenames(in: trip) {
            let source = mediaDirectory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let ext = source.pathExtension.nilIfBlank ?? "jpg"
            let replacement = "\(UUID().uuidString).\(ext)"
            try fileManager.copyItem(at: source, to: attachmentStore.imageURL(for: replacement))
            replacements[filename] = replacement
        }
        trip = replacingFilenames(in: trip, using: replacements)
        Self.logger.info("Prepared imported trip with \(replacements.count, privacy: .public) local media files")
        return trip
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func localFilenames(in trip: Trip) -> Set<String> {
        var names = Set(trip.allMedia.compactMap(\.filename))
        names.formUnion(trip.flights.compactMap(\.attachmentFilename))
        names.formUnion(trip.accommodations.compactMap(\.attachmentFilename))
        names.formUnion(trip.activities.compactMap(\.attachmentFilename))
        names.formUnion(trip.transfers.compactMap(\.attachmentFilename))
        names.formUnion(trip.ferries.compactMap(\.attachmentFilename))
        names.formUnion(trip.trains.compactMap(\.attachmentFilename))
        names.formUnion(trip.restaurants.compactMap(\.attachmentFilename))
        names.formUnion(trip.rentalVehicles.compactMap(\.attachmentFilename))
        names.formUnion(trip.otherItems.compactMap(\.attachmentFilename))
        return names
    }

    private func replacingFilenames(in original: Trip, using names: [String: String]) -> Trip {
        var trip = original
        func mapped(_ value: String?) -> String? { value.flatMap { names[$0] ?? $0 } }
        func media(_ values: [TripMedia]?) -> [TripMedia]? {
            values?.map { value in var result = value; result.filename = mapped(value.filename); return result }
        }
        func presentation(_ value: TripMedia?) -> TripMedia? {
            value.map { value in var result = value; result.filename = mapped(value.filename); return result }
        }
        for index in trip.flights.indices { trip.flights[index].attachmentFilename = mapped(trip.flights[index].attachmentFilename); trip.flights[index].media = media(trip.flights[index].media); trip.flights[index].presentationMedia = presentation(trip.flights[index].presentationMedia) }
        for index in trip.accommodations.indices { trip.accommodations[index].attachmentFilename = mapped(trip.accommodations[index].attachmentFilename); trip.accommodations[index].media = media(trip.accommodations[index].media); trip.accommodations[index].presentationMedia = presentation(trip.accommodations[index].presentationMedia) }
        for index in trip.activities.indices {
            let old = trip.activities[index]
            trip.activities[index] = old.updating(attachmentFilename: .some(mapped(old.attachmentFilename)))
            trip.activities[index].media = media(old.media)
            trip.activities[index].presentationMedia = presentation(old.presentationMedia)
        }
        for index in trip.transfers.indices { trip.transfers[index].attachmentFilename = mapped(trip.transfers[index].attachmentFilename) }
        for index in trip.ferries.indices { trip.ferries[index].attachmentFilename = mapped(trip.ferries[index].attachmentFilename) }
        for index in trip.trains.indices { trip.trains[index].attachmentFilename = mapped(trip.trains[index].attachmentFilename) }
        for index in trip.restaurants.indices { trip.restaurants[index].attachmentFilename = mapped(trip.restaurants[index].attachmentFilename) }
        for index in trip.rentalVehicles.indices { trip.rentalVehicles[index].attachmentFilename = mapped(trip.rentalVehicles[index].attachmentFilename) }
        for index in trip.otherItems.indices { trip.otherItems[index].attachmentFilename = mapped(trip.otherItems[index].attachmentFilename) }
        return trip
    }
}

extension Trip {
    func copyingAsNewTrip() -> Trip {
        Trip(id: UUID(), name: name + " (kopie)", country: country, startDate: startDate, endDate: endDate,
             travelers: travelers, timeZoneIdentifier: timeZoneIdentifier, destinations: destinations,
             flights: flights, accommodations: accommodations, activities: activities, transfers: transfers,
             ferries: ferries, trains: trains, restaurants: restaurants, rentalVehicles: rentalVehicles,
             otherItems: otherItems, transportItems: transportItems, tripDays: tripDays, bookingLinks: bookingLinks)
    }
}
