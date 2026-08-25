import Foundation
import OSLog

struct TripArchiveManifest: Codable, Equatable {
    static let currentSchemaVersion = 1
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
    case invalidPackage, unsupportedVersion(Int), missingMedia(String)
    var errorDescription: String? {
        switch self {
        case .invalidPackage: "Dit bestand is geen geldig reisbestand."
        case .unsupportedVersion(let version): "Deze reis gebruikt een nog niet ondersteunde versie (\(version))."
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
        let package = destinationDirectory.appendingPathComponent("\(safeName).trip", isDirectory: true)
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

    func preview(url: URL) throws -> TripImportPreview {
        let manifestURL = url.hasDirectoryPath ? url.appendingPathComponent("trip.json") : url
        let manifest = try TripJSONCoding.decoder().decode(TripArchiveManifest.self,
            from: Data(contentsOf: manifestURL))
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
        for index in trip.flights.indices { trip.flights[index].attachmentFilename = mapped(trip.flights[index].attachmentFilename); trip.flights[index].media = media(trip.flights[index].media) }
        for index in trip.accommodations.indices { trip.accommodations[index].attachmentFilename = mapped(trip.accommodations[index].attachmentFilename); trip.accommodations[index].media = media(trip.accommodations[index].media) }
        for index in trip.activities.indices {
            let old = trip.activities[index]
            trip.activities[index] = old.updating(attachmentFilename: .some(mapped(old.attachmentFilename)))
            trip.activities[index].media = media(old.media)
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
