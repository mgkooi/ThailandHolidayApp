import Foundation
import Observation
import os

@MainActor
@Observable
final class TripStore {
    private static let fileName = "travel-library.json"
    private static let legacyFileName = "thailand-trip.json"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ThailandHolidayApp",
        category: "TripStore"
    )

    private let fileManager: FileManager
    private let bundle: Bundle
    private let documentsDirectory: URL?
    private var library: TravelLibrary?
    private var hasLoaded = false

    /// Compatibility facade used by all feature views: always the selected trip.
    var trip: Trip? {
        get {
            guard let library, let selected = library.selectedTripId else { return nil }
            return library.trips.first { $0.id == selected }
        }
        set {
            guard let newValue else { return }
            if library == nil { library = TravelLibrary(trips: [newValue], selectedTripId: newValue.id) }
            else if let index = library?.trips.firstIndex(where: { $0.id == newValue.id }) {
                library?.trips[index] = newValue
            } else {
                library?.trips.append(newValue)
                library?.selectedTripId = newValue.id
            }
        }
    }
    var trips: [Trip] { library?.trips ?? [] }
    var selectedTripId: UUID? { library?.selectedTripId }
    var selectedTrip: Trip? { trip }
    private(set) var nearbySuggestions: [NearbySuggestion] = []
    var favorites: [Favorite] { library?.favorites ?? [] }
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var dataRevision = 0

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        documentsDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.documentsDirectory = documentsDirectory
    }

    var documentsURL: URL? {
        (documentsDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first)?
            .appendingPathComponent(Self.fileName)
    }

    var legacyDocumentsURL: URL? {
        (documentsDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first)?
            .appendingPathComponent(Self.legacyFileName)
    }

    var attachmentStore: AttachmentStore? {
        documentsURL.map { AttachmentStore(documentsDirectory: $0.deletingLastPathComponent(), fileManager: fileManager) }
    }

    func attachmentURL(for filename: String) -> URL? {
        attachmentStore?.imageURL(for: filename)
    }

    func prepareAttachmentsDirectory() throws {
        guard let attachmentStore else { throw TripStoreError.documentsDirectoryUnavailable }
        try attachmentStore.prepareDirectory()
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let url = try ensureLibraryFile()
#if DEBUG
            Self.logger.debug("Loading live trip data from \(url.path, privacy: .private)")
#endif
            let data = try Data(contentsOf: url)
            var decodedLibrary = try TripJSONCoding.decoder().decode(TravelLibrary.self, from: data)
            decodedLibrary.repairSelection()
            library = decodedLibrary
            nearbySuggestions = decodedLibrary.nearbySuggestions
        } catch {
            let message = "Reisgegevens konden niet worden geladen: \(error.localizedDescription)"
            errorMessage = message
            Self.logger.error("\(message, privacy: .public)")
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        load()
    }

    @discardableResult
    func save() -> Bool {
        errorMessage = nil

        do {
            guard var library else { throw TripStoreError.noTripLoaded }
            guard let url = documentsURL else {
                throw TripStoreError.documentsDirectoryUnavailable
            }

            library.nearbySuggestions = nearbySuggestions
            library.repairSelection()
            let data = try TripJSONCoding.encoder().encode(library)
            try data.write(to: url, options: .atomic)
            self.library = library
            return true
        } catch {
            let message = "Reisgegevens konden niet worden opgeslagen: \(error.localizedDescription)"
            errorMessage = message
            Self.logger.error("\(message, privacy: .public)")
            return false
        }
    }

    @discardableResult
    func selectTrip(id: UUID) -> Bool {
        guard library?.trips.contains(where: { $0.id == id }) == true else { return false }
        let previous = library?.selectedTripId
        library?.selectedTripId = id
        guard save() else { library?.selectedTripId = previous; return false }
        recordMutation()
        return true
    }

    @discardableResult
    func addTrip(_ newTrip: Trip) -> Bool {
        let previous = library
        if library == nil { library = TravelLibrary(trips: [newTrip], selectedTripId: newTrip.id) }
        else { library?.trips.append(newTrip); library?.selectedTripId = newTrip.id }
        guard save() else { library = previous; return false }
        recordMutation()
        return true
    }

    @discardableResult
    func saveDiscovery(_ result: DiscoveryResult) -> Bool {
        let externalID = result.googlePlaceID ?? result.id
        if library?.favorites.contains(where: { $0.externalProvider == "Google Places" && $0.externalID == externalID }) == true {
            return true
        }
        let previous = library
        library?.favorites.append(Favorite(id: UUID(), suggestionID: nil,
            externalProvider: result.googlePlaceID == nil ? "Discovery" : "Google Places",
            externalID: externalID, name: result.name, category: result.category.rawValue,
            latitude: result.latitude, longitude: result.longitude, websiteURL: result.websiteURL,
            mapsURL: nil, savedAt: Date(), address: result.address,
            ratingSnapshot: result.rating, reviewCountSnapshot: result.reviewCount))
        guard save() else { library = previous; return false }
        recordMutation()
        return true
    }

    func isDiscoverySaved(_ result: DiscoveryResult) -> Bool {
        let identity = result.googlePlaceID ?? result.id
        return favorites.contains { $0.externalID == identity }
    }

    @discardableResult
    func importTrip(_ imported: Trip, strategy: TripImportStrategy,
                    nearbySuggestions importedSuggestions: [NearbySuggestion] = [],
                    favorites importedFavorites: [Favorite] = []) -> Bool {
        let previous = library
        let previousSuggestions = nearbySuggestions
        var value = imported
        if library?.trips.contains(where: { $0.id == imported.id }) == true {
            switch strategy {
            case .copy: value = imported.copyingAsNewTrip()
            case .replace: library?.trips.removeAll { $0.id == imported.id }
            }
        }
        library?.trips.append(value)
        library?.selectedTripId = value.id
        let suggestionIDs = Set(library?.nearbySuggestions.map(\.id) ?? [])
        library?.nearbySuggestions.append(contentsOf: importedSuggestions.filter { !suggestionIDs.contains($0.id) })
        nearbySuggestions = library?.nearbySuggestions ?? nearbySuggestions
        let favoriteIDs = Set(library?.favorites.map(\.id) ?? [])
        library?.favorites.append(contentsOf: importedFavorites.filter { !favoriteIDs.contains($0.id) })
        guard save() else { library = previous; nearbySuggestions = previousSuggestions; return false }
        recordMutation()
        return true
    }

    @discardableResult
    func updateTripMetadata(_ updated: Trip) -> Bool {
        guard let index = library?.trips.firstIndex(where: { $0.id == updated.id }) else { return false }
        let previous = library
        library?.trips[index] = updated
        guard save() else { library = previous; return false }
        recordMutation()
        return true
    }

    @discardableResult
    func deleteTrip(id: UUID) -> Bool {
        guard library?.trips.contains(where: { $0.id == id }) == true else { return false }
        let previous = library
        library?.trips.removeAll { $0.id == id }
        library?.repairSelection()
        guard save() else { library = previous; return false }
        recordMutation()
        return true
    }

    @discardableResult
    func updateActivity(_ activity: Activity) -> Bool {
        let activity = activityWithResolvedDestination(activity)
        guard var updatedTrip = trip,
              let index = updatedTrip.activities.firstIndex(where: { $0.id == activity.id }) else {
            reportActivityNotFound()
            return false
        }

        let previousTrip = updatedTrip
        updatedTrip.activities[index] = activity
        trip = updatedTrip

        guard save() else {
            trip = previousTrip
            return false
        }
        recordMutation()
        return true
    }

    @discardableResult
    func addActivity(_ activity: Activity) -> Bool {
        guard trip?.activities.contains(where: { $0.id == activity.id }) == false else {
            return updateActivity(activity)
        }
        return saveManagedItem(.activity(activityWithResolvedDestination(activity)))
    }

    @discardableResult
    func deleteActivity(id: UUID) -> Bool {
        guard let activity = trip?.activities.first(where: { $0.id == id }) else {
            reportActivityNotFound()
            return false
        }
        return deleteManagedItem(.activity(activity))
    }

    @discardableResult
    func updateActivity(_ activity: Activity, replacementImageData: Data?) -> Bool {
        guard let original = trip?.activities.first(where: { $0.id == activity.id }) else {
            reportActivityNotFound()
            return false
        }

        var updated = activity
        var newFilename: String?

        do {
            if let replacementImageData {
                guard let attachmentStore else { throw TripStoreError.documentsDirectoryUnavailable }
                newFilename = try attachmentStore.saveImageData(replacementImageData)
                updated = activity.updating(attachmentFilename: .some(newFilename))
            }
        } catch {
            reportAttachmentError("Bijlage kon niet worden opgeslagen", error: error)
            return false
        }

        guard updateActivity(updated) else {
            if let newFilename { try? attachmentStore?.deleteAttachment(filename: newFilename) }
            return false
        }

        if let oldFilename = original.attachmentFilename,
           oldFilename != updated.attachmentFilename {
            do {
                try attachmentStore?.deleteAttachment(filename: oldFilename)
            } catch {
                Self.logger.error("Old attachment could not be deleted: \(error.localizedDescription, privacy: .public)")
            }
        }
        return true
    }

    @discardableResult
    func setActivityFavorite(id: UUID, isFavorite: Bool) -> Bool {
        guard let activity = trip?.activities.first(where: { $0.id == id }) else {
            reportActivityNotFound()
            return false
        }
        return updateActivity(activity.updating(isFavorite: isFavorite))
    }

    @discardableResult
    func setActivityCompleted(id: UUID, isCompleted: Bool) -> Bool {
        guard let activity = trip?.activities.first(where: { $0.id == id }) else {
            reportActivityNotFound()
            return false
        }
        return updateActivity(activity.updating(isCompleted: isCompleted))
    }

    func destination(for date: Date) -> Destination? {
        guard let trip else { return nil }
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        let targetDay = calendar.startOfDay(for: date)

        return trip.destinations.first {
            targetDay >= calendar.startOfDay(for: $0.arrivalDate)
                && targetDay <= calendar.startOfDay(for: $0.departureDate)
        } ?? TripResolver(trip: trip).currentDestination(on: date)
    }

    func accommodation(for date: Date) -> Accommodation? {
        guard let trip else { return nil }
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        let targetDay = calendar.startOfDay(for: date)

        let result = trip.accommodations.first {
            targetDay >= calendar.startOfDay(for: $0.checkInDate)
                && targetDay < calendar.startOfDay(for: $0.checkOutDate)
        }
#if DEBUG
        Self.logger.debug("Accommodation query day \(targetDay, privacy: .public); found \(result != nil, privacy: .public)")
#endif
        return result
    }

    func flights(on date: Date) -> [Flight] {
        guard let trip else { return [] }
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        return trip.flights.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func activities(on date: Date) -> [Activity] {
        guard let trip else { return [] }
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        let result = trip.activities
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
#if DEBUG
        Self.logger.debug("Activities query day \(calendar.startOfDay(for: date), privacy: .public); count \(result.count, privacy: .public)")
#endif
        return result
    }

    func restaurants(on date: Date) -> [RestaurantReservation] {
        guard let trip else { return [] }
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        return trip.restaurants
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.time < $1.time }
    }

    func transfers(on date: Date) -> [Transfer] { items(trip?.transfers ?? [], date: date, keyPath: \.date) }
    func ferries(on date: Date) -> [Ferry] { items(trip?.ferries ?? [], date: date, keyPath: \.date) }
    func trains(on date: Date) -> [TrainTrip] { items(trip?.trains ?? [], date: date, keyPath: \.date) }
    func rentalVehicles(on date: Date) -> [RentalVehicleBooking] { items(trip?.rentalVehicles ?? [], date: date, keyPath: \.pickupDate) }
    func otherItems(on date: Date) -> [TripEvent] { items(trip?.otherItems ?? [], date: date, keyPath: \.date) }

    private func items<Value>(_ values: [Value], date: Date, keyPath: KeyPath<Value, Date>) -> [Value] {
        guard let trip else { return [] }
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        return values.filter { calendar.isDate($0[keyPath: keyPath], inSameDayAs: date) }
    }

    func timelineSections() -> [TimelineDaySection] {
        guard let trip else { return [] }
        return TripTimelineBuilder(trip: trip).sections()
    }

    func managedItem(for source: TimelineSource) -> ManagedTripItem? {
        guard let trip else { return nil }
        return switch source {
        case .flight(let id): trip.flights.first { $0.id == id }.map(ManagedTripItem.flight)
        case .accommodation(let id, _): trip.accommodations.first { $0.id == id }.map(ManagedTripItem.accommodation)
        case .activity(let id): trip.activities.first { $0.id == id }.map(ManagedTripItem.activity)
        case .transport: nil
        case .transfer(let id): trip.transfers.first { $0.id == id }.map(ManagedTripItem.transfer)
        case .ferry(let id): trip.ferries.first { $0.id == id }.map(ManagedTripItem.ferry)
        case .train(let id): trip.trains.first { $0.id == id }.map(ManagedTripItem.train)
        case .rentalVehicle(let id, _): trip.rentalVehicles.first { $0.id == id }.map(ManagedTripItem.rentalVehicle)
        case .restaurant(let id): trip.restaurants.first { $0.id == id }.map(ManagedTripItem.restaurant)
        case .other(let id): trip.otherItems.first { $0.id == id }.map(ManagedTripItem.other)
        }
    }

    func managedItem(id: UUID, kind: TripItemKind) -> ManagedTripItem? {
        existingManagedItem(id: id, kind: kind)
    }

    func trip(id: UUID) -> Trip? { library?.trips.first { $0.id == id } }

    @discardableResult
    func saveManagedItem(
        _ item: ManagedTripItem,
        replacementImageData: Data? = nil,
        removeAttachment: Bool = false,
        targetTripID: UUID? = nil
    ) -> Bool {
        let targetID = targetTripID ?? selectedTripId
        guard let targetID, let targetIndex = library?.trips.firstIndex(where: { $0.id == targetID }),
              let originalTrip = library?.trips[targetIndex] else { return false }
        let oldFilename = existingManagedItem(id: item.id, kind: item.kind, in: originalTrip)?.attachmentFilename
        let item = normalizedManagedItem(item)
        var committedItem = removeAttachment ? item.replacingAttachment(with: nil) : item
        var newFilename: String?

        do {
            if let replacementImageData {
                guard let attachmentStore else { throw TripStoreError.documentsDirectoryUnavailable }
                let savedFilename = try attachmentStore.saveImageData(replacementImageData)
                newFilename = savedFilename
                committedItem = item.assigningLocalFilename(savedFilename)
            }
        } catch {
            reportAttachmentError("Bijlage kon niet worden opgeslagen", error: error)
            return false
        }

        var updatedTrip = originalTrip
        upsert(committedItem, in: &updatedTrip)
        let originalLibrary = library
        library?.trips[targetIndex] = updatedTrip
        guard save() else {
            library = originalLibrary
            if let newFilename { try? attachmentStore?.deleteAttachment(filename: newFilename) }
            return false
        }
        recordMutation()

        if let oldFilename, oldFilename != committedItem.attachmentFilename {
            try? attachmentStore?.deleteAttachment(filename: oldFilename)
        }
        return true
    }

    @discardableResult
    func setPresentationMedia(for item: ManagedTripItem, imageData: Data?, metadata: TripMedia?) -> Bool {
        guard let targetID = selectedTripId,
              let targetIndex = library?.trips.firstIndex(where: { $0.id == targetID }),
              var updatedTrip = library?.trips[targetIndex] else { return false }
        var savedFilename: String?
        var value = metadata
        do {
            if let imageData {
                guard let attachmentStore else { throw TripStoreError.documentsDirectoryUnavailable }
                savedFilename = try attachmentStore.saveImageData(imageData)
                value?.filename = savedFilename
            }
        } catch {
            reportAttachmentError("Omslag kon niet worden opgeslagen", error: error)
            return false
        }
        let enrichedItem = value?.googlePlaceID.map { item.replacingGooglePlaceID($0) } ?? item
        upsert(enrichedItem.replacingPresentationMedia(value), in: &updatedTrip)
        let originalLibrary = library
        library?.trips[targetIndex] = updatedTrip
        guard save() else {
            library = originalLibrary
            if let savedFilename { try? attachmentStore?.deleteAttachment(filename: savedFilename) }
            return false
        }
        recordMutation()
        return true
    }

    @discardableResult
    func deleteManagedItem(_ item: ManagedTripItem) -> Bool {
        guard let originalTrip = trip else { return false }
        var updatedTrip = originalTrip
        remove(item, from: &updatedTrip)
        trip = updatedTrip
        guard save() else {
            trip = originalTrip
            return false
        }
        recordMutation()
        if let filename = item.attachmentFilename {
            try? attachmentStore?.deleteAttachment(filename: filename)
        }
        return true
    }

    private func existingManagedItem(id: UUID, kind: TripItemKind) -> ManagedTripItem? {
        guard let trip else { return nil }
        return existingManagedItem(id: id, kind: kind, in: trip)
    }

    private func existingManagedItem(id: UUID, kind: TripItemKind, in trip: Trip) -> ManagedTripItem? {
        return switch kind {
        case .flight: trip.flights.first { $0.id == id }.map(ManagedTripItem.flight)
        case .accommodation: trip.accommodations.first { $0.id == id }.map(ManagedTripItem.accommodation)
        case .transfer: trip.transfers.first { $0.id == id }.map(ManagedTripItem.transfer)
        case .ferry: trip.ferries.first { $0.id == id }.map(ManagedTripItem.ferry)
        case .train: trip.trains.first { $0.id == id }.map(ManagedTripItem.train)
        case .rentalVehicle: trip.rentalVehicles.first { $0.id == id }.map(ManagedTripItem.rentalVehicle)
        case .restaurant: trip.restaurants.first { $0.id == id }.map(ManagedTripItem.restaurant)
        case .activity: trip.activities.first { $0.id == id }.map(ManagedTripItem.activity)
        case .other: trip.otherItems.first { $0.id == id }.map(ManagedTripItem.other)
        }
    }

    private func normalizedManagedItem(_ item: ManagedTripItem) -> ManagedTripItem {
        item
    }

    private func activityWithResolvedDestination(_ activity: Activity) -> Activity {
        activity
    }

    private func recordMutation() {
        dataRevision &+= 1
#if DEBUG
        Self.logger.debug("TripStore \(ObjectIdentifier(self).debugDescription, privacy: .public) revision \(self.dataRevision, privacy: .public); activities \(self.trip?.activities.count ?? 0, privacy: .public); accommodations \(self.trip?.accommodations.count ?? 0, privacy: .public)")
#endif
    }

    private func upsert(_ item: ManagedTripItem, in trip: inout Trip) {
        switch item {
        case .flight(let value): upsert(value, in: &trip.flights)
        case .accommodation(let value): upsert(value, in: &trip.accommodations)
        case .transfer(let value): upsert(value, in: &trip.transfers)
        case .ferry(let value): upsert(value, in: &trip.ferries)
        case .train(let value): upsert(value, in: &trip.trains)
        case .rentalVehicle(let value): upsert(value, in: &trip.rentalVehicles)
        case .restaurant(let value): upsert(value, in: &trip.restaurants)
        case .activity(let value): upsert(value, in: &trip.activities)
        case .other(let value): upsert(value, in: &trip.otherItems)
        }
    }

    private func upsert<Value: Identifiable>(_ value: Value, in values: inout [Value]) where Value.ID == UUID {
        if let index = values.firstIndex(where: { $0.id == value.id }) { values[index] = value }
        else { values.append(value) }
    }

    private func remove(_ item: ManagedTripItem, from trip: inout Trip) {
        switch item.kind {
        case .flight: trip.flights.removeAll { $0.id == item.id }
        case .accommodation: trip.accommodations.removeAll { $0.id == item.id }
        case .transfer: trip.transfers.removeAll { $0.id == item.id }
        case .ferry: trip.ferries.removeAll { $0.id == item.id }
        case .train: trip.trains.removeAll { $0.id == item.id }
        case .rentalVehicle: trip.rentalVehicles.removeAll { $0.id == item.id }
        case .restaurant: trip.restaurants.removeAll { $0.id == item.id }
        case .activity: trip.activities.removeAll { $0.id == item.id }
        case .other: trip.otherItems.removeAll { $0.id == item.id }
        }
    }

    private func ensureLibraryFile() throws -> URL {
        guard let documentsURL else {
            throw TripStoreError.documentsDirectoryUnavailable
        }

        let documentsDirectory = documentsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: documentsURL.path) else { return documentsURL }

        if let legacyDocumentsURL, fileManager.fileExists(atPath: legacyDocumentsURL.path) {
            let legacyData = try Data(contentsOf: legacyDocumentsURL)
            let package = try TripJSONCoding.decoder().decode(TripDataPackage.self, from: legacyData)
            let migrated = TravelLibrary(trips: [package.trip], selectedTripId: package.trip.id,
                                         nearbySuggestions: package.nearbySuggestions, favorites: package.favorites)
            let data = try TripJSONCoding.encoder().encode(migrated)
            try data.write(to: documentsURL, options: .atomic)
            _ = try TripJSONCoding.decoder().decode(TravelLibrary.self, from: Data(contentsOf: documentsURL))
            Self.logger.info("Migrated legacy trip data; original file retained as backup.")
            return documentsURL
        }

        let bundleURL = bundle.url(forResource: "thailand-trip", withExtension: "json", subdirectory: "Data")
            ?? bundle.url(forResource: "thailand-trip", withExtension: "json")
        guard let bundleURL else {
            throw TripStoreError.bundledTripNotFound
        }

        let seed = try TripJSONCoding.decoder().decode(TripDataPackage.self, from: Data(contentsOf: bundleURL))
        let library = TravelLibrary(trips: [seed.trip], selectedTripId: seed.trip.id,
                                    nearbySuggestions: seed.nearbySuggestions, favorites: seed.favorites)
        try TripJSONCoding.encoder().encode(library).write(to: documentsURL, options: .atomic)
        Self.logger.info("Created travel library from bundled seed data at \(documentsURL.path, privacy: .private)")
        return documentsURL
    }

    private func reportActivityNotFound() {
        let message = "De activiteit kon niet worden bijgewerkt."
        errorMessage = message
        Self.logger.error("Activity update failed because its ID was not found in the current trip.")
    }


    private func reportAttachmentError(_ prefix: String, error: Error) {
        errorMessage = "De afbeelding kon niet worden opgeslagen. Probeer het opnieuw."
        Self.logger.error("\(prefix, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

enum TripStoreError: LocalizedError {
    case documentsDirectoryUnavailable
    case bundledTripNotFound
    case noTripLoaded

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            "De Documents-map is niet beschikbaar."
        case .bundledTripNotFound:
            "thailand-trip.json ontbreekt in de app-bundle."
        case .noTripLoaded:
            "Er zijn nog geen reisgegevens geladen."
        }
    }
}
