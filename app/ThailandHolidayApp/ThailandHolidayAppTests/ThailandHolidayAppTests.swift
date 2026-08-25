import Foundation
import MapKit
import Testing
import UIKit
@testable import ThailandHolidayApp

struct ThailandHolidayAppTests {
    private let repository = LocalTripRepository()

    @Test func bundledJSONDecodesCompleteTrip() throws {
        let package = try repository.loadPackage()

        #expect(package.trip.name == "Thailand 2026")
        #expect(package.trip.destinations.count == 1)
        #expect(package.trip.accommodations.count == 1)
        #expect(package.trip.transportItems.count == 1)
        #expect(package.trip.tripDays.count == 1)
        #expect(package.trip.tripDays[0].itineraryItems.count == 3)
        #expect(package.nearbySuggestions.count == 2)
    }

    @Test func tripDateRangeIncludesBothBoundaryDays() throws {
        let trip = try repository.currentTrip()
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        let before = calendar.date(byAdding: .day, value: -1, to: trip.startDate)!
        let after = calendar.date(byAdding: .day, value: 1, to: trip.endDate)!

        #expect(trip.contains(trip.startDate))
        #expect(trip.contains(trip.endDate))
        #expect(!trip.contains(before))
        #expect(!trip.contains(after))
        #expect(calendar.isDate(trip.startDate, inSameDayAs: TripCalendar.date(2026, 9, 4)))
        #expect(calendar.isDate(trip.endDate, inSameDayAs: TripCalendar.date(2026, 9, 19)))
    }

    @Test func resolverFindsTripDayUsingThailandCalendar() throws {
        let trip = try repository.currentTrip()
        let resolver = TripResolver(trip: trip)
        let thailandDate = try #require(ISO8601DateFormatter().date(from: "2026-09-09T00:30:00+07:00"))

        #expect(resolver.tripDay(on: thailandDate)?.id == trip.tripDays[0].id)
        #expect(resolver.currentDestination(on: thailandDate)?.name == "Khao Sok")
    }

    @Test func resolverFindsCurrentAccommodation() throws {
        let trip = try repository.currentTrip()
        let resolver = TripResolver(trip: trip)
        let duringStay = try #require(ISO8601DateFormatter().date(from: "2026-09-09T15:00:00+07:00"))

        #expect(resolver.currentAccommodation(on: duringStay)?.name == "Our Jungle House")
    }

    @Test func resolverSelectsNextTransport() throws {
        let trip = try repository.currentTrip()
        let resolver = TripResolver(trip: trip)
        let referenceDate = try #require(ISO8601DateFormatter().date(from: "2026-09-09T18:00:00+07:00"))

        #expect(resolver.nextTransport(after: referenceDate)?.referenceNumber == "TR-204")
    }

    @Test func itineraryIsSortedChronologically() throws {
        let day = try #require(try repository.currentTrip().tripDays.first)
        let reversed = TripDay(
            id: day.id,
            date: day.date,
            destinationID: day.destinationID,
            accommodationID: day.accommodationID,
            itineraryItems: day.itineraryItems.reversed(),
            notes: day.notes
        )

        #expect(reversed.sortedItinerary.map(\.title) == [
            "Ontbijt aan de rivier",
            "Kanoën op de Sok-rivier",
            "Lunch in het dorp"
        ])
    }

    @Test func thailandDateDoesNotDependOnDeviceTimeZone() throws {
        let trip = try repository.currentTrip()
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-09T00:30:00+07:00"))
        let thailandCalendar = TripCalendar.calendar(in: trip.timeZone)
        var losAngelesCalendar = Calendar(identifier: .gregorian)
        losAngelesCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(thailandCalendar.component(.day, from: instant) == 9)
        #expect(losAngelesCalendar.component(.day, from: instant) == 8)
        #expect(TripResolver(trip: trip).tripDay(on: instant) != nil)
    }

    @Test @MainActor func JSONEncoderUsesISO8601Dates() throws {
        let package = try repository.loadPackage()
        let encoded = try TripJSONCoding.encoder().encode(package)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(json.contains("2026-09-08T17:00:00Z"))
    }

    @Test @MainActor func todayStoreResolvesBundledTripDates() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = fixture.store

        #expect(store.errorMessage == nil)

        let september4 = TripCalendar.date(2026, 9, 4, hour: 12)
        let september6 = TripCalendar.date(2026, 9, 6, hour: 12)
        let september9 = TripCalendar.date(2026, 9, 9, hour: 12)
        let september18 = TripCalendar.date(2026, 9, 18, hour: 12)

        #expect(store.destination(for: september4) == nil)
        #expect(store.destination(for: september6) == nil)
        #expect(store.destination(for: september9)?.name == "Khao Sok")
        #expect(store.accommodation(for: september9)?.name == "Our Jungle House")
        #expect(store.flights(on: september9).map(\.flightNumber) == ["TG123"])
        #expect(store.activities(on: september9).map(\.title) == ["Kanoën op de Sok-rivier"])
        #expect(store.destination(for: september18) == nil)
    }

    @Test @MainActor func editingActivityUpdatesSavesAndReloadsTripStore() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try #require(fixture.store.trip?.activities.first)
        let changed = original.updating(
            title: "Bijgewerkte kano-tocht",
            startTime: TripCalendar.date(2026, 9, 9, hour: 14, minute: 15),
            description: .some("Aangepast vanuit de app."),
            notes: .some("Neem water mee.")
        )

        #expect(fixture.store.updateActivity(changed))
        #expect(fixture.store.trip?.activities.first?.title == "Bijgewerkte kano-tocht")

        let persistedData = try Data(contentsOf: try #require(fixture.store.documentsURL))
        let persisted = try TripJSONCoding.decoder().decode(TravelLibrary.self, from: persistedData)
        #expect(persisted.trips.first?.activities.first?.notes == "Neem water mee.")

        let reloaded = TripStore(documentsDirectory: fixture.directory)
        reloaded.load()
        #expect(reloaded.trip?.activities.first?.title == "Bijgewerkte kano-tocht")
        #expect(reloaded.trip?.activities.first?.startTime == changed.startTime)
    }

    @Test @MainActor func cancellingActivityDraftDoesNotChangeOrPersistActivity() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try #require(fixture.store.trip?.activities.first)
        let draft = ActivityEditDraft(activity: original)
        draft.title = "Dit mag niet worden opgeslagen"
        draft.replacementImageData = testImageData(color: .green)

        #expect(fixture.store.trip?.activities.first == original)
        let attachmentsDirectory = fixture.directory.appendingPathComponent("Attachments", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: attachmentsDirectory.path))

        let reloaded = TripStore(documentsDirectory: fixture.directory)
        reloaded.load()
        #expect(reloaded.trip?.activities.first == original)
    }

    @Test @MainActor func favoriteAndCompletedTogglesPersist() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let activity = try #require(fixture.store.trip?.activities.first)

        #expect(fixture.store.setActivityFavorite(id: activity.id, isFavorite: false))
        #expect(fixture.store.setActivityCompleted(id: activity.id, isCompleted: true))

        let reloaded = TripStore(documentsDirectory: fixture.directory)
        reloaded.load()
        let persisted = try #require(reloaded.trip?.activities.first { $0.id == activity.id })
        #expect(!persisted.isFavorite)
        #expect(persisted.isCompleted)
    }

    @Test @MainActor func changedDateAndURLPersistAndMoveActivityBetweenDays() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let activity = try #require(fixture.store.trip?.activities.first)
        #expect(activity.url == nil)
        let oldDate = activity.date
        let newDate = TripCalendar.date(2026, 9, 10)
        let url = try #require(URL(string: "https://example.com/booking"))
        let changed = activity.updating(
            date: newDate,
            startTime: TripCalendar.date(2026, 9, 10, hour: 10),
            endTime: .some(TripCalendar.date(2026, 9, 10, hour: 12)),
            url: .some(url)
        )

        #expect(fixture.store.updateActivity(changed))
        #expect(fixture.store.activities(on: oldDate).allSatisfy { $0.id != activity.id })
        #expect(fixture.store.activities(on: newDate).contains { $0.id == activity.id })

        let reloaded = TripStore(documentsDirectory: fixture.directory)
        reloaded.load()
        let persisted = try #require(reloaded.trip?.activities.first { $0.id == activity.id })
        #expect(persisted.url == url)
        #expect(TripCalendar.calendar().isDate(persisted.date, inSameDayAs: newDate))
    }

    @Test @MainActor func attachmentPersistsResolvesDeletesAndReplacesWithoutOrphans() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let activity = try #require(fixture.store.trip?.activities.first)
        let firstData = testImageData(color: .red)

        #expect(fixture.store.updateActivity(activity, replacementImageData: firstData))
        let firstFilename = try #require(fixture.store.trip?.activities.first?.attachmentFilename)
        let firstURL = try #require(fixture.store.attachmentURL(for: firstFilename))
        #expect(FileManager.default.fileExists(atPath: firstURL.path))

        let firstReload = TripStore(documentsDirectory: fixture.directory)
        firstReload.load()
        #expect(firstReload.trip?.activities.first?.attachmentFilename == firstFilename)

        let secondData = testImageData(color: .blue)
        let current = try #require(fixture.store.trip?.activities.first)
        #expect(fixture.store.updateActivity(current, replacementImageData: secondData))
        let secondFilename = try #require(fixture.store.trip?.activities.first?.attachmentFilename)
        #expect(secondFilename != firstFilename)
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: try #require(fixture.store.attachmentURL(for: secondFilename)).path))

        let withoutAttachment = try #require(fixture.store.trip?.activities.first)
            .updating(attachmentFilename: .some(nil))
        #expect(fixture.store.updateActivity(withoutAttachment, replacementImageData: nil))
        #expect(!FileManager.default.fileExists(atPath: try #require(fixture.store.attachmentURL(for: secondFilename)).path))

        let reloaded = TripStore(documentsDirectory: fixture.directory)
        reloaded.load()
        #expect(reloaded.trip?.activities.first?.attachmentFilename == nil)
    }

    @Test func weatherSelectorUsesRequestedThailandHoursAndFormatsCelsius() {
        let day = TripCalendar.date(2026, 9, 9)
        let forecast = [20, 8, 16, 12].map { hour in
            TripHourWeather(
                date: TripCalendar.date(2026, 9, 9, hour: hour),
                temperatureCelsius: Double(hour) + 10.4,
                symbolName: "sun.max.fill"
            )
        }

        let selected = TripWeatherSelector.select(
            from: forecast,
            for: day,
            timeZone: TripCalendar.thailandTimeZone
        )
        let calendar = TripCalendar.calendar()

        #expect(selected.map { calendar.component(.hour, from: $0.date) } == [8, 12, 16, 20])
        #expect(TripWeatherSelector.celsiusText(28.6) == "29°")
    }

    @Test @MainActor func weatherServiceShowsUnavailableAndChangesWithDestination() async throws {
        let trip = try repository.currentTrip()
        let firstDestination = try #require(trip.destinations.first)
        let day = TripCalendar.date(2026, 9, 9)
        let available = TripWeatherSelector.requestedHours.map { hour in
            TripHourWeather(
                date: TripCalendar.date(2026, 9, 9, hour: hour),
                temperatureCelsius: 29,
                symbolName: "cloud.sun.fill"
            )
        }
        let secondDestination = Destination(
            id: UUID(),
            name: "Bangkok",
            country: "Thailand",
            region: "Bangkok",
            arrivalDate: trip.startDate,
            departureDate: trip.endDate,
            latitude: 13.7563,
            longitude: 100.5018,
            description: nil,
            imageReference: nil,
            notes: nil
        )
        let provider = WeatherFixtureProvider(forecastsByLatitude: [
            firstDestination.latitude: available,
            secondDestination.latitude: []
        ])
        let service = TripWeatherService(provider: provider)

        await service.refresh(destination: firstDestination, date: day, timeZone: trip.timeZone)
        #expect(service.state == .available)
        #expect(service.hourlyForecast.count == 4)

        await service.refresh(destination: secondDestination, date: day, timeZone: trip.timeZone)
        #expect(service.state == .unavailable)
        #expect(service.hourlyForecast.isEmpty)
        #expect(service.errorMessage == nil)
    }

    @Test @MainActor func unavailableWeatherProviderProducesCleanUnavailableState() async throws {
        let trip = try repository.currentTrip()
        let destination = try #require(trip.destinations.first)
        let service = TripWeatherService(provider: UnavailableTripWeatherProvider())

        await service.refresh(
            destination: destination,
            date: TripCalendar.date(2026, 9, 9),
            timeZone: trip.timeZone
        )

        #expect(service.state == .unavailable)
        #expect(service.hourlyForecast.isEmpty)
        #expect(service.errorMessage == nil)
    }

    @Test func timelineBuilderMapsSourcesAndGroupsThailandDays() throws {
        let trip = try repository.currentTrip()
        let sections = TripTimelineBuilder(trip: trip).sections()
        let items = sections.flatMap(\.items)
        let calendar = TripCalendar.calendar(in: trip.timeZone)

        let flight = try #require(items.first { if case .flight = $0.source { true } else { false } })
        #expect(flight.title == "Bangkok (BKK) → Surat Thani (URT)")
        #expect(flight.subtitle == "Thai Airways · TG123")
        #expect(flight.type == .flight)

        let activity = try #require(items.first { if case .activity = $0.source { true } else { false } })
        #expect(activity.title == "Kanoën op de Sok-rivier")
        #expect(activity.isFavorite)

        let accommodationEvents = items.filter {
            if case .accommodation = $0.source { true } else { false }
        }
        #expect(accommodationEvents.count == 2)
        #expect(calendar.component(.day, from: accommodationEvents[0].date) == 9)
        #expect(calendar.component(.day, from: accommodationEvents[1].date) == 11)

        #expect(sections.map { calendar.component(.day, from: $0.day) } == [9, 10, 11])
    }

    @Test func timelineItemsSortChronologicallyAcrossTypes() throws {
        let trip = try repository.currentTrip()
        let section = try #require(TripTimelineBuilder(trip: trip).sections().first)

        #expect(section.items.map(\.type) == [.flight, .activity, .accommodation])
        #expect(section.items.compactMap(\.startDate) == section.items.compactMap(\.startDate).sorted())
    }

    @Test func timelineDateOnlyAccommodationUsesStableUntimedOrdering() throws {
        let trip = try repository.currentTrip()
        let original = try #require(trip.accommodations.first)
        let midnight = TripCalendar.date(2026, 9, 9)
        let dateOnlyAccommodation = Accommodation(
            id: original.id,
            name: original.name,
            type: original.type,
            destinationID: original.destinationID,
            checkIn: midnight,
            checkOut: TripCalendar.date(2026, 9, 11),
            address: original.address,
            latitude: original.latitude,
            longitude: original.longitude,
            roomDescription: original.roomDescription,
            bookingReference: original.bookingReference,
            websiteURL: original.websiteURL,
            bookingURL: original.bookingURL,
            phoneNumber: original.phoneNumber
        )
        let adjustedTrip = Trip(
            id: trip.id,
            name: trip.name,
            country: trip.country,
            startDate: trip.startDate,
            endDate: trip.endDate,
            travelers: trip.travelers,
            timeZoneIdentifier: trip.timeZoneIdentifier,
            destinations: trip.destinations,
            flights: trip.flights,
            accommodations: [dateOnlyAccommodation],
            activities: trip.activities,
            transportItems: trip.transportItems,
            tripDays: trip.tripDays,
            bookingLinks: trip.bookingLinks
        )

        let builder = TripTimelineBuilder(trip: adjustedTrip)
        let firstResult = builder.items()
        let secondResult = builder.items()
        let checkIn = try #require(firstResult.first { $0.id.hasSuffix("checkin") })

        #expect(checkIn.startDate == nil)
        #expect(firstResult.map(\.id) == secondResult.map(\.id))
        #expect(TripCalendar.calendar().component(.day, from: checkIn.date) == 9)
    }

    @Test @MainActor func createsAllManagedTripItemTypesAndReloadsNewArrays() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let trip = try #require(fixture.store.trip)
        let kinds: [TripItemKind] = [.flight, .accommodation, .transfer, .ferry, .train, .restaurant, .activity, .other]

        for kind in kinds {
            let draft = TripItemDraft(kind: kind, trip: trip)
            draft.urlString = "https://example.com/\(kind.rawValue)"
            draft.a = "Test \(kind.title)"
            draft.b = "Vertrek"
            draft.c = "Aankomst"
            draft.d = "Bestemming"
            let item = draft.makeItem(kind: kind, id: UUID(), trip: trip)
            #expect(fixture.store.saveManagedItem(item))
        }

        let reloaded = TripStore(documentsDirectory: fixture.directory)
        reloaded.load()
        let saved = try #require(reloaded.trip)
        #expect(saved.flights.count == trip.flights.count + 1)
        #expect(saved.accommodations.count == trip.accommodations.count + 1)
        #expect(saved.transfers.count == 1)
        #expect(saved.ferries.count == 1)
        #expect(saved.trains.count == 1)
        #expect(saved.restaurants.count == 1)
        #expect(saved.activities.count == trip.activities.count + 1)
        #expect(saved.otherItems.count == 1)
        #expect(saved.transfers.first?.url?.host == "example.com")
    }

    @Test @MainActor func editingKeepsIDDeletingRemovesOnlyCorrectItemAndAttachment() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let trip = try #require(fixture.store.trip)
        let draft = TripItemDraft(kind: .other, trip: trip)
        draft.a = "Eerste titel"
        let id = UUID()
        let original = draft.makeItem(kind: .other, id: id, trip: trip)
        #expect(fixture.store.saveManagedItem(original, replacementImageData: testImageData(color: .purple)))

        let stored = try #require(fixture.store.managedItem(id: id, kind: .other))
        let filename = try #require(stored.attachmentFilename)
        let editedDraft = TripItemDraft(item: stored, trip: trip)
        editedDraft.a = "Nieuwe titel"
        let edited = editedDraft.makeItem(kind: .other, id: id, trip: trip)
        #expect(edited.id == id)
        #expect(fixture.store.saveManagedItem(edited))
        #expect(fixture.store.trip?.otherItems.first { $0.id == id }?.title == "Nieuwe titel")

        let unrelated = TripEvent(id: UUID(), date: trip.startDate, startTime: nil, endTime: nil,
            title: "Blijft bestaan", location: nil, notes: nil, url: nil, attachmentFilename: nil)
        #expect(fixture.store.saveManagedItem(.other(unrelated)))
        #expect(fixture.store.deleteManagedItem(try #require(fixture.store.managedItem(id: id, kind: .other))))
        #expect(fixture.store.trip?.otherItems.contains { $0.id == id } == false)
        #expect(fixture.store.trip?.otherItems.contains { $0.id == unrelated.id } == true)
        #expect(!FileManager.default.fileExists(atPath: try #require(fixture.store.attachmentURL(for: filename)).path))
    }

    @Test @MainActor func oldJSONWithoutPhaseTwoArraysDecodesWithEmptyCollections() throws {
        let package = try repository.loadPackage()
        let data = try TripJSONCoding.encoder().encode(package)
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var trip = try #require(root["trip"] as? [String: Any])
        ["transfers", "ferries", "trains", "restaurants", "otherItems"].forEach { trip.removeValue(forKey: $0) }
        root["trip"] = trip
        let legacyData = try JSONSerialization.data(withJSONObject: root)

        let decoded = try TripJSONCoding.decoder().decode(TripDataPackage.self, from: legacyData)
        #expect(decoded.trip.transfers.isEmpty)
        #expect(decoded.trip.ferries.isEmpty)
        #expect(decoded.trip.trains.isEmpty)
        #expect(decoded.trip.restaurants.isEmpty)
        #expect(decoded.trip.otherItems.isEmpty)
    }

    @Test @MainActor func timelineMapsEveryPhaseTwoTypeAndKeepsAccommodationSourceID() throws {
        var trip = try repository.currentTrip()
        let day = TripCalendar.date(2026, 9, 10)
        trip.transfers = [Transfer(id: UUID(), date: day, startTime: day, endTime: nil, type: .taxi,
            provider: "Taxi", origin: "A", destination: "B", bookingReference: nil, notes: nil, url: nil, attachmentFilename: "transfer.jpg")]
        trip.ferries = [Ferry(id: UUID(), date: day, operatorName: "Ferry", departureLocation: "B", arrivalLocation: "C",
            departureTime: TripCalendar.date(2026, 9, 10, hour: 9), arrivalTime: nil, bookingReference: nil, notes: nil, url: nil, attachmentFilename: nil)]
        trip.trains = [TrainTrip(id: UUID(), date: day, operatorName: "Rail", trainNumber: "1", originStation: "C",
            destinationStation: "D", departureTime: TripCalendar.date(2026, 9, 10, hour: 10), arrivalTime: nil,
            carriage: nil, seat: nil, notes: nil, url: nil, attachmentFilename: nil)]
        trip.restaurants = [RestaurantReservation(id: UUID(), date: day, time: TripCalendar.date(2026, 9, 10, hour: 18),
            name: "Diner", address: nil, latitude: nil, longitude: nil, reservationName: nil,
            reservationReference: nil, notes: nil, url: nil, attachmentFilename: nil)]
        trip.otherItems = [TripEvent(id: UUID(), date: day, startTime: TripCalendar.date(2026, 9, 10, hour: 20),
            endTime: nil, title: "Overig", location: nil, notes: nil, url: nil, attachmentFilename: nil)]

        let items = TripTimelineBuilder(trip: trip).items()
        #expect(items.contains { item in
            guard item.type == .transfer else { return false }
            if case .transfer = item.source { return true }
            return false
        })
        #expect(items.contains { $0.type == .ferry })
        #expect(items.contains { $0.type == .train })
        #expect(items.contains { $0.type == .restaurant })
        #expect(items.contains { $0.type == .other })
        let accommodationIDs = items.compactMap { item -> UUID? in
            if case .accommodation(let id, _) = item.source { return id }
            return nil
        }
        #expect(Set(accommodationIDs).count == 1)
    }

    @Test @MainActor func cancellingManagedDraftDoesNotModifyStore() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let before = fixture.store.trip
        let draft = TripItemDraft(kind: .train, trip: try #require(before))
        draft.a = "Niet opslaan"
        draft.replacementImageData = testImageData(color: .orange)
        #expect(fixture.store.trip == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Attachments").path))
    }

    @Test @MainActor func rentalVehicleTypesClassificationAndTimelineEvents() throws {
        let parser = BookingTextParser()
        #expect(parser.classify("Avis car rental pickup and return") == .rentalVehicle)
        #expect(parser.classify("Honda Click scooter rental pick-up") == .rentalVehicle)
        #expect(parser.classify("Trek bicycle rental drop-off") == .rentalVehicle)
        #expect(parser.rentalVehicleType(in: "Car rental") == .car)
        #expect(parser.rentalVehicleType(in: "Scooter rental") == .scooter)
        #expect(parser.rentalVehicleType(in: "Bicycle rental") == .bicycle)
        #expect(parser.rentalVehicleType(in: "Trek e-bike") == .eBike)
        #expect(parser.rentalVehicleType(in: "ATV quad rental") == .quad)
        #expect(parser.rentalVehicleType(in: "Unknown rental vehicle") == .other)

        var trip = try repository.currentTrip()
        let id = UUID()
        trip.rentalVehicles = [RentalVehicleBooking(id: id, vehicleType: .scooter, company: "Budget Bike Rental",
            pickupDate: TripCalendar.date(2026, 9, 10), pickupTime: TripCalendar.date(2026, 9, 10, hour: 7, minute: 30),
            pickupLocation: "Surat Thani", dropoffDate: TripCalendar.date(2026, 9, 11),
            dropoffTime: TripCalendar.date(2026, 9, 11, hour: 18), dropoffLocation: "Koh Tao",
            vehicleDescription: "Honda Click 125", bookingReference: "R-1", renterName: "Martijn",
            notes: nil, url: URL(string: "https://example.com/rental"), attachmentFilename: "proof.jpg")]
        let events = TripTimelineBuilder(trip: trip).items().filter { $0.type == .rentalVehicle }
        #expect(events.map(\.title) == ["Scooter ophalen", "Scooter inleveren"])
        #expect(events.allSatisfy { item in
            if case .rentalVehicle(let sourceID, _) = item.source { return sourceID == id }
            return false
        })
    }

    @Test @MainActor func rentalVehiclesPersistAndLegacyRentalCarsDecode() throws {
        let originalPackage = try repository.loadPackage()
        var trip = originalPackage.trip
        trip.rentalVehicles = [RentalVehicleBooking(id: UUID(), vehicleType: .motorcycle,
            company: "Moto", pickupDate: trip.startDate, pickupTime: trip.startDate,
            pickupLocation: "Bangkok", dropoffDate: nil, dropoffTime: nil, dropoffLocation: nil,
            vehicleDescription: "Yamaha NMAX", bookingReference: nil, renterName: nil, notes: nil,
            url: URL(string: "https://example.com"), attachmentFilename: "booking.jpg")]
        let package = TripDataPackage(trip: trip, nearbySuggestions: originalPackage.nearbySuggestions, favorites: originalPackage.favorites)
        let encoded = try TripJSONCoding.encoder().encode(package)
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var tripJSON = try #require(root["trip"] as? [String: Any])
        tripJSON["rentalCars"] = tripJSON.removeValue(forKey: "rentalVehicles")
        root["trip"] = tripJSON
        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let decoded = try TripJSONCoding.decoder().decode(TripDataPackage.self, from: legacyData)
        #expect(decoded.trip.rentalVehicles.first?.vehicleType == .motorcycle)
        #expect(decoded.trip.rentalVehicles.first?.url?.host == "example.com")
        #expect(decoded.trip.rentalVehicles.first?.attachmentFilename == "booking.jpg")
    }

    @Test @MainActor func autoOphalenLegacyEventMigratesToEditableRentalVehicle() throws {
        let originalPackage = try repository.loadPackage()
        var trip = originalPackage.trip
        let id = UUID()
        trip.otherItems = [TripEvent(id: id, date: TripCalendar.date(2026, 9, 10),
            startTime: TripCalendar.date(2026, 9, 10, hour: 7, minute: 30), endTime: nil,
            title: "Auto ophalen", location: "Chiang Mai Airport", notes: nil, url: nil,
            attachmentFilename: nil)]
        let package = TripDataPackage(trip: trip, nearbySuggestions: originalPackage.nearbySuggestions, favorites: originalPackage.favorites)
        let data = try TripJSONCoding.encoder().encode(package)
        let decoded = try TripJSONCoding.decoder().decode(TripDataPackage.self, from: data)
        #expect(decoded.trip.rentalVehicles.first?.id == id)
        #expect(decoded.trip.rentalVehicles.first?.vehicleType == .car)
        #expect(!decoded.trip.otherItems.contains { $0.id == id })
    }

    @Test @MainActor func bookingNormalizationExtractionAndAirportEnrichment() async throws {
        let recognized = RecognizedBookingText(originalText: " KLM  \nKL875\nCNX\nURT\nO8:25\nI0:15\nCNX\n")
        #expect(recognized.normalizedText.contains("08:25"))
        #expect(recognized.normalizedText.contains("10:15"))
        #expect(recognized.normalizedText.components(separatedBy: "CNX").count == 2)
        let result = try await DeterministicBookingExtractor().extract(text: recognized, trip: repository.currentTrip())
        #expect(result.detectedType == .flight)
        #expect(result.fields["flightNumber"]?.value == "KL875")
        #expect(result.fields["originAirportCode"]?.value == "CNX")
        #expect(result.fields["originAirportName"]?.value.contains("Chiang Mai") == true)
        #expect(result.fields["destinationAirportCode"]?.value == "URT")
        #expect(result.originalRecognizedText.contains("O8:25"))
    }

    @Test @MainActor func knownThailandFlightsInferTripYearTimesAirportsAndDetails() async throws {
        let trip = try repository.currentTrip()
        let extractor = DeterministicBookingExtractor()
        let airAsia = try await extractor.extract(text: RecognizedBookingText(originalText: """
        Thai AirAsia
        FD5422
        Wednesday 9 Sep
        Chiang Mai CNX
        08:25
        Surat Thani URT
        10:15
        Economy
        Airbus A320
        """), trip: trip)
        #expect(airAsia.detectedType == .flight)
        #expect(airAsia.fields["flightNumber"]?.value == "FD5422")
        #expect(airAsia.fields["originAirportCode"]?.value == "CNX")
        #expect(airAsia.fields["destinationAirportCode"]?.value == "URT")
        #expect(airAsia.fields["departureTime"]?.value == "08:25")
        #expect(airAsia.fields["arrivalTime"]?.value == "10:15")
        #expect(airAsia.fields["cabin"]?.value == "Economy")
        #expect(airAsia.fields["aircraft"]?.value == "Airbus A320")
        let dateText = try #require(airAsia.fields["date"]?.value)
        let date = try #require(ISO8601DateFormatter().date(from: dateText))
        let components = TripCalendar.calendar(in: trip.timeZone).dateComponents([.year,.month,.day], from: date)
        #expect(components.year == 2026 && components.month == 9 && components.day == 9)

        let bangkokAirways = try await extractor.extract(text: RecognizedBookingText(originalText: """
        Bangkok Airways
        PG122
        Friday 18 Sep
        USM 09:15
        BKK 10:30
        """), trip: trip)
        #expect(bangkokAirways.fields["flightNumber"]?.value == "PG122")
        #expect(bangkokAirways.fields["originAirportCode"]?.value == "USM")
        #expect(bangkokAirways.fields["destinationAirportCode"]?.value == "BKK")
    }

    @Test @MainActor func classifierSupportsEveryBookingTypeAndUnknown() async throws {
        let trip = try repository.currentTrip(), extractor = DeterministicBookingExtractor()
        let fixtures: [(String, BookingDetectedType)] = [
            ("Flight boarding KL875", .flight), ("Hotel check-in check-out", .accommodation),
            ("Private transfer driver will meet you at arrivals", .transfer),
            ("Scooter rental return vehicle", .rentalVehicle), ("Ferry catamaran boarding pier", .ferry),
            ("Train railway carriage station", .train), ("Restaurant table reservation dinner", .restaurant),
            ("Activity tour admission ticket", .activity), ("A vague receipt", .other)
        ]
        for fixture in fixtures {
            let result = try await extractor.extract(text: RecognizedBookingText(originalText: fixture.0), trip: trip)
            #expect(result.detectedType == fixture.1)
        }
    }

    @Test @MainActor func normalizationURLReferenceAndTwelveHourTimeAreExtracted() async throws {
        let trip = try repository.currentTrip()
        let recognized = RecognizedBookingText(originalText: "Booking reference: ABC123\n8.25 PM\nhttps://example.com/booking\nABC123")
        let result = DeterministicBookingExtractor().extract(text: recognized, trip: trip, forcedType: .restaurant)
        #expect(result.fields["bookingReference"]?.value == "ABC123")
        #expect(result.fields["url"]?.value == "https://example.com/booking")
        #expect(result.fields["departureTime"]?.value == "8:25 PM")
    }

    @Test @MainActor func extractionDistinguishesTransferFromRentalAndAddsWarnings() async throws {
        let extractor = DeterministicBookingExtractor()
        let trip = try repository.currentTrip()
        let transfer = try await extractor.extract(text: RecognizedBookingText(
            originalText: "Private transfer\nDriver will meet you at arrivals\nHotel pickup"), trip: trip)
        #expect(transfer.detectedType == .transfer)
        let rental = try await extractor.extract(text: RecognizedBookingText(
            originalText: "Scooter rental\nVehicle: Honda Click 125\nDrop-off location: Koh Tao"), trip: trip)
        #expect(rental.detectedType == .rentalVehicle)
        #expect(rental.fields["vehicleType"]?.value == RentalVehicleType.scooter.rawValue)
        #expect(rental.warnings.contains("Controleer ophaallocatie"))
    }

    @Test @MainActor func startupCoordinatorSucceedsAndProgressNeverMovesBackwards() async throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let coordinator = AppStartupCoordinator()
        #expect(!coordinator.isReady)
        await coordinator.start(tripStore: fixture.store)
        #expect(coordinator.isReady)
        #expect(coordinator.progress == 1)
        #expect(zip(coordinator.progressHistory, coordinator.progressHistory.dropFirst()).allSatisfy(<=))
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Attachments").path))
    }

    @Test @MainActor func startupRetryRecoversAndDoesNotOverwriteLocalJSON() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Startup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TripStore(documentsDirectory: directory)
        let coordinator = AppStartupCoordinator()
        await coordinator.start(tripStore: store)
        #expect(coordinator.isReady)
        let file = directory.appendingPathComponent("travel-library.json")
        let original = try Data(contentsOf: file)
        await coordinator.retry(tripStore: store)
        #expect(coordinator.isReady)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test @MainActor func activityCreatedFromReisIsImmediatelyVisibleToTodayAndTimeline() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let september6 = TripCalendar.date(2026, 9, 6)
        let destination = Destination(id: UUID(), name: "Chiang Mai", country: "Thailand", region: "Chiang Mai",
            arrivalDate: TripCalendar.date(2026, 9, 4), departureDate: TripCalendar.date(2026, 9, 8, hour: 23),
            latitude: 18.7883, longitude: 98.9853, description: nil, imageReference: nil, notes: nil)
        fixture.store.trip = tripReplacingDestinations(try #require(fixture.store.trip), with: [destination])
        let id = UUID()
        let activity = Activity(id: id, destinationId: UUID(), date: september6,
            startTime: TripCalendar.date(2026, 9, 6, hour: 10), endTime: nil, title: "Test activiteit",
            category: ItineraryCategory.activity.rawValue, description: nil, latitude: nil, longitude: nil,
            websiteURL: nil, bookingURL: nil, notes: nil, url: nil, attachmentFilename: nil,
            isFavorite: false, isCompleted: false)

        #expect(fixture.store.addActivity(activity))
        let todayActivity = try #require(fixture.store.activities(on: september6).first { $0.id == id })
        #expect(todayActivity.destinationId == activity.destinationId)
        let timelineActivity = try #require(fixture.store.timelineSections().flatMap(\.items).first {
            if case .activity(let sourceID) = $0.source { return sourceID == id }
            return false
        })
        #expect(timelineActivity.title == todayActivity.title)
    }

    @Test @MainActor func movingActivityChangesTodayDayDestinationAndTimelineWithoutDuplicate() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let september6 = TripCalendar.date(2026, 9, 6)
        let september9 = TripCalendar.date(2026, 9, 9)
        let chiangMai = Destination(id: UUID(), name: "Chiang Mai", country: "Thailand", region: "Chiang Mai",
            arrivalDate: TripCalendar.date(2026, 9, 4), departureDate: TripCalendar.date(2026, 9, 8, hour: 23),
            latitude: 18.7883, longitude: 98.9853, description: nil, imageReference: nil, notes: nil)
        let khaoSok = Destination(id: UUID(), name: "Khao Sok", country: "Thailand", region: "Surat Thani",
            arrivalDate: september9, departureDate: TripCalendar.date(2026, 9, 10, hour: 23), latitude: 8.91,
            longitude: 98.53, description: nil, imageReference: nil, notes: nil)
        fixture.store.trip = tripReplacingDestinations(try #require(fixture.store.trip), with: [chiangMai, khaoSok])
        let id = UUID()
        let original = Activity(id: id, destinationId: chiangMai.id, date: september6,
            startTime: TripCalendar.date(2026, 9, 6, hour: 9), endTime: nil, title: "Verplaats mij",
            category: "activity", description: nil, latitude: nil, longitude: nil, websiteURL: nil,
            bookingURL: nil, notes: nil, url: nil, attachmentFilename: nil, isFavorite: false, isCompleted: false)
        #expect(fixture.store.addActivity(original))
        let moved = original.updating(date: september9, startTime: TripCalendar.date(2026, 9, 9, hour: 11))
        #expect(fixture.store.updateActivity(moved))

        #expect(!fixture.store.activities(on: september6).contains { $0.id == id })
        #expect(fixture.store.activities(on: september9).first { $0.id == id }?.destinationId == chiangMai.id)
        #expect(fixture.store.trip?.activities.filter { $0.id == id }.count == 1)
        let timeline = fixture.store.timelineSections().flatMap(\.items).filter {
            if case .activity(let sourceID) = $0.source { return sourceID == id }
            return false
        }
        #expect(timeline.count == 1)
        #expect(TripCalendar.calendar(in: try #require(fixture.store.trip).timeZone).isDate(timeline[0].date, inSameDayAs: september9))
    }

    @Test @MainActor func accommodationCreatedFromReisIsImmediatelyActiveUntilCheckout() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let september6 = TripCalendar.date(2026, 9, 6)
        let september7 = TripCalendar.date(2026, 9, 7)
        let september8 = TripCalendar.date(2026, 9, 8)
        let destination = Destination(id: UUID(), name: "Bangkok", country: "Thailand", region: "Bangkok",
            arrivalDate: TripCalendar.date(2026, 9, 4), departureDate: september8,
            latitude: 13.7563, longitude: 100.5018, description: nil, imageReference: nil, notes: nil)
        fixture.store.trip = tripReplacingDestinations(try #require(fixture.store.trip), with: [destination])
        let id = UUID()
        let accommodation = Accommodation(id: id, name: "Test Hotel Bangkok", type: .hotel,
            destinationID: UUID(), checkIn: september6, checkOut: september8, address: "Bangkok, Thailand",
            latitude: 13.7563, longitude: 100.5018, roomDescription: "", bookingReference: nil,
            websiteURL: nil, bookingURL: nil, phoneNumber: nil)
        let revision = fixture.store.dataRevision

        #expect(fixture.store.saveManagedItem(.accommodation(accommodation)))
        #expect(fixture.store.dataRevision == revision + 1)
        #expect(fixture.store.accommodation(for: september6)?.id == id)
        #expect(fixture.store.accommodation(for: september7)?.id == id)
        #expect(fixture.store.accommodation(for: september8) == nil)
        #expect(fixture.store.trip?.accommodations.first { $0.id == id }?.destinationID == accommodation.destinationID)
        #expect(fixture.store.timelineSections().flatMap(\.items).contains {
            if case .accommodation(let sourceID, _) = $0.source { return sourceID == id }
            return false
        })
    }

    @Test @MainActor func addressGeocodingPreservesUnchangedCoordinatesAndResolvesChangedAddress() async {
        let old = Coordinate(latitude: 1, longitude: 2)
        let replacement = Coordinate(latitude: 13.7563, longitude: 100.5018)
        let resolver = AddressCoordinateResolver(geocoder: GeocodingFixture(result: replacement))

        #expect(await resolver.resolve(address: "Bangkok", originalAddress: "Bangkok", existingCoordinate: old) == old)
        #expect(await resolver.resolve(address: "", originalAddress: "Bangkok", existingCoordinate: old) == nil)
        #expect(await resolver.resolve(address: "Bangkok, Thailand", originalAddress: "Bangkok", existingCoordinate: old) == replacement)
    }

    @Test @MainActor func addressGeocodingFailureDoesNotBlockSavingAddress() async {
        let resolver = AddressCoordinateResolver(geocoder: GeocodingFixture(result: nil))
        #expect(await resolver.resolve(address: "Onbekend adres", originalAddress: "Oud", existingCoordinate: Coordinate(latitude: 1, longitude: 2)) == nil)
    }

    @Test @MainActor func arbitraryDatesPersistAppearInTodayQueriesAndTimeline() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let activityDate = TripCalendar.date(2026, 9, 1)
        let hotelStart = TripCalendar.date(2026, 9, 20)
        let hotelEnd = TripCalendar.date(2026, 9, 22)
        let flightDate = TripCalendar.date(2026, 9, 25)

        let activity = Activity(id: UUID(), destinationId: nil, date: activityDate,
            startTime: TripCalendar.date(2026, 9, 1, hour: 10), endTime: nil, title: "Vroege activiteit",
            category: "activity", description: nil, latitude: nil, longitude: nil, websiteURL: nil,
            bookingURL: nil, notes: nil, url: nil, attachmentFilename: nil, isFavorite: false, isCompleted: false)
        let hotel = Accommodation(id: UUID(), name: "Extra hotel", type: .hotel, destinationID: nil,
            placeName: "Ayutthaya", checkIn: hotelStart, checkOut: hotelEnd, address: "Ayutthaya, Thailand",
            latitude: nil, longitude: nil, roomDescription: "", bookingReference: nil, websiteURL: nil,
            bookingURL: nil, phoneNumber: nil)
        let flight = Flight(id: UUID(), date: flightDate, airline: "Test Air", flightNumber: "TA25",
            originAirport: "BKK", destinationAirport: "AMS", departureTime: TripCalendar.date(2026, 9, 25, hour: 8),
            arrivalTime: TripCalendar.date(2026, 9, 25, hour: 16), aircraft: nil, cabin: nil)

        #expect(fixture.store.saveManagedItem(.activity(activity)))
        #expect(fixture.store.saveManagedItem(.accommodation(hotel)))
        #expect(fixture.store.saveManagedItem(.flight(flight)))
        #expect(fixture.store.activities(on: activityDate).contains { $0.id == activity.id })
        #expect(fixture.store.accommodation(for: TripCalendar.date(2026, 9, 21))?.id == hotel.id)
        #expect(fixture.store.flights(on: flightDate).contains { $0.id == flight.id })

        let trip = try #require(fixture.store.trip)
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        #expect(calendar.isDate(trip.effectiveStartDate, inSameDayAs: activityDate))
        #expect(calendar.isDate(trip.effectiveEndDate, inSameDayAs: flightDate))
        let days = fixture.store.timelineSections().map(\.day)
        #expect(days == days.sorted())
        #expect(days.contains { calendar.isDate($0, inSameDayAs: activityDate) })
        #expect(days.contains { calendar.isDate($0, inSameDayAs: flightDate) })
    }

    @Test @MainActor func accommodationWithoutKnownDestinationPersistsAndRemainsActive() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let hotel = Accommodation(id: UUID(), name: "Remote Lodge", type: .hotel, destinationID: nil,
            placeName: "Ban Something", checkIn: TripCalendar.date(2026, 9, 20),
            checkOut: TripCalendar.date(2026, 9, 22), address: "Remote road 1", latitude: nil,
            longitude: nil, roomDescription: "Bungalow", bookingReference: nil, websiteURL: nil,
            bookingURL: nil, phoneNumber: nil)

        #expect(fixture.store.saveManagedItem(.accommodation(hotel)))
        let saved = try #require(fixture.store.accommodation(for: TripCalendar.date(2026, 9, 21)))
        #expect(saved.destinationID == nil)
        #expect(saved.placeName == "Ban Something")
        #expect(saved.address == "Remote road 1")
        #expect(saved.location.hasUsableLocation)

        let reloaded = TripStore(documentsDirectory: fixture.directory)
        reloaded.load()
        #expect(reloaded.accommodation(for: TripCalendar.date(2026, 9, 21))?.id == hotel.id)
    }

    @Test @MainActor func appleMapsResolutionPrefersCoordinatesThenAddressThenPlace() {
        let resolver = MapLocationResolver()
        #expect(resolver.resolution(for: TripLocation(placeName: "Bangkok", address: "Street", latitude: 1, longitude: 2)) == .coordinate(1, 2))
        #expect(resolver.resolution(for: TripLocation(placeName: "Bangkok", address: "Street", latitude: nil, longitude: nil)) == .address("Street"))
        #expect(resolver.resolution(for: TripLocation(placeName: "Bangkok", address: nil, latitude: nil, longitude: nil)) == .placeName("Bangkok"))
        #expect(resolver.resolution(for: TripLocation(placeName: " ", address: nil, latitude: nil, longitude: nil)) == .unavailable)
    }

    @Test @MainActor func accommodationDraftGeocodesCombinedAddressAndPlaceAndMatchesExactDestination() async throws {
        let trip = try repository.currentTrip()
        let draft = TripItemDraft(kind: .accommodation, trip: trip)
        draft.a = "Test Hotel"
        draft.f = "Khao Sok"
        draft.c = "62 Khlong Sok"
        draft.matchDestination(in: trip.destinations)
        let query = [draft.c.nilIfBlank, draft.f.nilIfBlank].compactMap { $0 }.joined(separator: ", ")
        let coordinate = await AddressCoordinateResolver(
            geocoder: GeocodingFixture(result: Coordinate(latitude: 14.35, longitude: 100.56))
        ).resolve(address: query, originalAddress: "", existingCoordinate: nil)
        if let coordinate { draft.setCoordinate(coordinate) }
        let item = draft.makeItem(kind: .accommodation, id: UUID(), trip: trip)
        guard case .accommodation(let hotel) = item else { Issue.record("Expected accommodation"); return }
        #expect(hotel.placeName == "Khao Sok")
        #expect(hotel.address == "62 Khlong Sok")
        #expect(hotel.destinationID == trip.destinations.first?.id)
        #expect(hotel.latitude == 14.35)
        #expect(hotel.longitude == 100.56)
    }

    @Test @MainActor func flightWithoutArrivalDateMigratesToDepartureDate() throws {
        let flight = try #require(repository.currentTrip().flights.first)
        let encoded = try TripJSONCoding.encoder().encode(flight)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "arrivalDate")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try TripJSONCoding.decoder().decode(Flight.self, from: legacyData)
        #expect(migrated.arrivalDate == migrated.date)
        #expect(migrated.arrivalTime == flight.arrivalTime)
    }

    @Test @MainActor func flightDraftSupportsSameDayAndOvernightAndRejectsEarlierArrival() throws {
        let trip = try repository.currentTrip()
        let draft = TripItemDraft(kind: .flight, trip: trip)
        draft.c = "BKK"; draft.d = "AMS"
        draft.date = TripCalendar.date(2026, 9, 24)
        draft.startTime = TripCalendar.date(2026, 9, 24, hour: 22)
        draft.secondaryDate = TripCalendar.date(2026, 9, 24)
        draft.endTime = TripCalendar.date(2026, 9, 24, hour: 23)
        #expect(draft.hasValidFlightArrival(in: trip.timeZone))

        draft.secondaryDate = TripCalendar.date(2026, 9, 25)
        draft.endTime = TripCalendar.date(2026, 9, 25, hour: 6)
        #expect(draft.hasValidFlightArrival(in: trip.timeZone))
        guard case .flight(let overnight) = draft.makeItem(kind: .flight, id: UUID(), trip: trip) else {
            Issue.record("Expected flight"); return
        }
        #expect(TripCalendar.calendar(in: trip.timeZone).component(.day, from: overnight.arrivalDate) == 25)
        #expect(overnight.arrivalDateTime(in: trip.timeZone) > overnight.departureTime)

        draft.secondaryDate = TripCalendar.date(2026, 9, 24)
        draft.endTime = TripCalendar.date(2026, 9, 24, hour: 21)
        #expect(!draft.hasValidFlightArrival(in: trip.timeZone))
        #expect(!draft.isValid)
    }

    @Test @MainActor func flightArrivalDatePersistsAfterStoreReload() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let departure = TripCalendar.date(2026, 9, 24, hour: 22)
        let arrivalDay = TripCalendar.date(2026, 9, 25)
        let arrival = TripCalendar.date(2026, 9, 25, hour: 6)
        let flight = Flight(id: UUID(), date: TripCalendar.date(2026, 9, 24), airline: "Test Air",
            flightNumber: "TA1", originAirport: "BKK", destinationAirport: "AMS", departureTime: departure,
            arrivalDate: arrivalDay, arrivalTime: arrival, aircraft: nil, cabin: nil)
        #expect(fixture.store.saveManagedItem(.flight(flight)))
        let reloaded = TripStore(documentsDirectory: fixture.directory); reloaded.load()
        let saved = try #require(reloaded.trip?.flights.first { $0.id == flight.id })
        #expect(saved.arrivalDate == arrivalDay)
        #expect(saved.arrivalDateTime(in: try #require(reloaded.trip).timeZone) == arrival)
    }

    @Test @MainActor func todaySearchLocationUsesAccommodationThenDestinationThenActivity() async throws {
        let trip = try repository.currentTrip()
        let date = TripCalendar.date(2026, 9, 9, hour: 12)
        let resolver = TripSearchLocationResolver(geocoder: GeocodingFixture(result: nil))
        let accommodationLocation = await resolver.resolve(for: date, in: trip)
        #expect(accommodationLocation?.name == trip.accommodations.first?.placeName ?? trip.accommodations.first?.name)
        #expect(accommodationLocation?.latitude == trip.accommodations.first?.latitude)

        let destinationOnly = tripReplacingLocationSources(trip, accommodations: [], activities: trip.activities,
            destinations: trip.destinations)
        let destinationLocation = await resolver.resolve(for: date, in: destinationOnly)
        #expect(destinationLocation?.name == trip.destinations.first?.name)

        let activity = Activity(id: UUID(), destinationId: nil, date: date, startTime: date, endTime: nil,
            title: "Tempel", category: "activity", description: nil,
            location: TripLocation(placeName: "Mae Rim", address: nil, latitude: 18.9, longitude: 98.9),
            latitude: 18.9, longitude: 98.9, websiteURL: nil, bookingURL: nil, notes: nil, url: nil,
            attachmentFilename: nil, isFavorite: false, isCompleted: false)
        let activityOnly = tripReplacingLocationSources(trip, accommodations: [], activities: [activity], destinations: [])
        #expect(await resolver.resolve(for: date, in: activityOnly)?.name == "Mae Rim")

        let noLocation = tripReplacingLocationSources(trip, accommodations: [], activities: [], destinations: [])
        #expect(await resolver.resolve(for: date, in: noLocation) == nil)
    }

    @Test @MainActor func discoveryRequestsEveryCategoryAndSortsNearestFirst() async {
        let searcher = DiscoveryFixtureSearcher()
        let session = DiscoverySession(searcher: searcher, geocoder: GeocodingFixture(result: nil))
        let location = SearchLocation(name: "Khao Sok", latitude: 8.91, longitude: 98.53)
        await session.activate(location)
        for category in DiscoveryCategory.allCases { await session.select(category) }
        #expect(Set(searcher.requests.map(\.category)) == Set(DiscoveryCategory.allCases))
        #expect(session.results.compactMap(\.distanceMeters) == [100, 800])
    }

    @Test @MainActor func manualPlaceSearchChangesCoordinatesAndNavigationKeepsTodayLocation() async {
        let searcher = DiscoveryFixtureSearcher()
        let session = DiscoverySession(searcher: searcher,
            geocoder: GeocodingFixture(result: Coordinate(latitude: 10.1, longitude: 99.8)))
        #expect(await session.searchPlace("Koh Tao"))
        #expect(session.activeLocation?.name == "Koh Tao")
        #expect(session.activeLocation?.latitude == 10.1)
        #expect(session.activeLocation?.longitude == 99.8)
        #expect(searcher.requests.last?.location.name == "Koh Tao")

        let navigation = AppNavigationState()
        await session.activate(SearchLocation(name: "Our Jungle House", latitude: 8.9, longitude: 98.5))
        navigation.openDiscover()
        #expect(navigation.selectedTab == .discover)
        #expect(session.activeLocation?.name == "Our Jungle House")
        #expect(session.selectedCategory == .restaurant)
    }

    @Test @MainActor func bangkokDiscoveryRejectsWorldwideResultsWithAndWithoutStrictFilter() async {
        let provider = RadiusDiscoveryFixture()
        let session = DiscoverySession(searcher: provider,
            geocoder: GeocodingFixture(result: Coordinate(latitude: 13.7563, longitude: 100.5018)))
        #expect(await session.searchPlace("Bangkok", radiusMeters: 10_000))
        #expect(session.activeLocation == SearchLocation(name: "Bangkok", latitude: 13.7563, longitude: 100.5018))
        #expect(session.results.map(\.name) == ["Restaurant A", "Restaurant B"])
        #expect(session.results.allSatisfy { ($0.distanceMeters ?? .greatestFiniteMagnitude) <= 10_000 })
        #expect(provider.requests.last?.radius == 10_000)

        await session.refresh(radiusMeters: 25_000)
        #expect(session.results.map(\.name) == ["Restaurant A", "Restaurant B"])
        #expect(!session.results.contains { $0.name == "Restaurant C France" })
        #expect(session.activeLocation?.name == "Bangkok")
        #expect(provider.requests.last?.radius == 25_000)
    }

    @Test @MainActor func parisThenBangkokUsesDistinctLocationAndRadiusCacheKeys() async {
        let provider = RadiusDiscoveryFixture()
        let geocoder = QueryGeocodingFixture(coordinates: [
            "Paris": Coordinate(latitude: 48.8566, longitude: 2.3522),
            "Bangkok": Coordinate(latitude: 13.7563, longitude: 100.5018)
        ])
        let session = DiscoverySession(searcher: provider, geocoder: geocoder)
        #expect(await session.searchPlace("Paris", radiusMeters: 10_000))
        #expect(await session.searchPlace("Bangkok", radiusMeters: 10_000))
        await session.refresh(radiusMeters: 25_000)
        #expect(provider.requests.map(\.location.name).suffix(2) == ["Bangkok", "Bangkok"])
        #expect(session.activeLocation?.name == "Bangkok")

        let paris = DiscoveryCacheKey(latitudeBucket: 48_857, longitudeBucket: 2_352,
                                      category: .restaurant, radiusBucket: 10_000)
        let bangkok = DiscoveryCacheKey(latitudeBucket: 13_756, longitudeBucket: 100_502,
                                        category: .restaurant, radiusBucket: 10_000)
        let bangkokWide = DiscoveryCacheKey(latitudeBucket: 13_756, longitudeBucket: 100_502,
                                            category: .restaurant, radiusBucket: 25_000)
        #expect(paris != bangkok)
        #expect(bangkok != bangkokWide)
    }

    @Test func todayDefaultsToInjectedCurrentDateAndCalendarJumpQueriesThatDay() throws {
        let now = TripCalendar.date(2031, 2, 3, hour: 12)
        #expect(TodayDateSelection.initialDate(selectedDate: nil, now: now) == now)
        let jump = TripCalendar.date(2026, 9, 9, hour: 12)
        #expect(TodayDateSelection.initialDate(selectedDate: jump, now: now) == jump)
        let trip = try repository.currentTrip()
        #expect(TripCalendar.calendar(in: trip.timeZone).isDate(jump, inSameDayAs: trip.activities.first?.date ?? .distantPast))
        #expect(TodayDateSelection.moving(jump, by: 1, timeZone: trip.timeZone) > jump)
    }

    @Test @MainActor func accommodationBoundaryChangesDailyLocation() async throws {
        let trip = try repository.currentTrip()
        let first = Accommodation(id: UUID(), name: "Hotel Chiang Mai", type: .hotel, destinationID: nil,
            placeName: "Chiang Mai", checkIn: TripCalendar.date(2026, 9, 6), checkOut: TripCalendar.date(2026, 9, 9),
            address: "", latitude: 18.78, longitude: 98.98, roomDescription: "", bookingReference: nil,
            websiteURL: nil, bookingURL: nil, phoneNumber: nil)
        let second = Accommodation(id: UUID(), name: "Our Jungle House", type: .hotel, destinationID: nil,
            placeName: "Khao Sok", checkIn: TripCalendar.date(2026, 9, 9), checkOut: TripCalendar.date(2026, 9, 10),
            address: "", latitude: 8.91, longitude: 98.53, roomDescription: "", bookingReference: nil,
            websiteURL: nil, bookingURL: nil, phoneNumber: nil)
        let fixture = tripReplacingLocationSources(trip, accommodations: [first, second], activities: [], destinations: [])
        let resolver = TripSearchLocationResolver(geocoder: GeocodingFixture(result: nil))
        #expect(await resolver.resolve(for: TripCalendar.date(2026, 9, 8), in: fixture)?.name == "Chiang Mai")
        #expect(await resolver.resolve(for: TripCalendar.date(2026, 9, 9), in: fixture)?.name == "Khao Sok")
    }

    @Test func airportLookupSupportsCodesAndAmbiguousCities() {
        let lookup = AirportLookup()
        #expect(lookup.airport(for: "BKK")?.name == "Suvarnabhumi Airport")
        #expect(lookup.airport(for: "DMK")?.name == "Don Mueang International Airport")
        #expect(lookup.airport(for: "CNX")?.city == "Chiang Mai")
        #expect(lookup.airport(for: "URT")?.city == "Surat Thani")
        #expect(lookup.airport(for: "USM")?.city == "Koh Samui")
        #expect(Set(lookup.suggestions(for: "Bangkok").map(\.code)) == Set(["BKK", "DMK"]))
        #expect(lookup.bestMatch(for: "Bangkok") == nil)
    }

    @Test @MainActor func structuredFlightAirportsAndBookingReferencePersist() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let lookup = AirportLookup(), departure = try #require(lookup.airport(for: "CNX")), arrival = try #require(lookup.airport(for: "URT"))
        let flight = Flight(id: UUID(), date: TripCalendar.date(2026, 9, 25), airline: "Thai AirAsia",
            flightNumber: "FD5422", originAirport: departure.code, destinationAirport: arrival.code,
            departureTime: TripCalendar.date(2026, 9, 25, hour: 8, minute: 25), arrivalDate: TripCalendar.date(2026, 9, 25),
            arrivalTime: TripCalendar.date(2026, 9, 25, hour: 10, minute: 15), departureAirport: departure,
            arrivalAirport: arrival, bookingReference: "ABC123", aircraft: nil, cabin: nil)
        #expect(fixture.store.saveManagedItem(.flight(flight)))
        let reloaded = TripStore(documentsDirectory: fixture.directory); reloaded.load()
        let saved = try #require(reloaded.trip?.flights.first { $0.id == flight.id })
        #expect(saved.departureAirport == departure)
        #expect(saved.arrivalAirport == arrival)
        #expect(saved.bookingReference == "ABC123")
    }

    @Test func mapAnnotationsIncludeStructuredLocationsAndTenKilometerFocus() throws {
        let original = try repository.currentTrip()
        let restaurant = RestaurantReservation(id: UUID(), date: original.startDate, time: original.startDate,
            name: "Test restaurant", address: "Bangkok", latitude: 13.75, longitude: 100.50,
            reservationName: nil, reservationReference: nil, notes: nil, url: nil, attachmentFilename: nil)
        let activity = Activity(id: UUID(), destinationId: nil, date: original.startDate, startTime: original.startDate,
            endTime: nil, title: "Test activiteit", category: "activity", description: nil,
            location: TripLocation(placeName: "Bangkok", address: nil, latitude: 13.76, longitude: 100.51),
            latitude: 13.76, longitude: 100.51, websiteURL: nil, bookingURL: nil, notes: nil, url: nil,
            attachmentFilename: nil, isFavorite: false, isCompleted: false)
        let lookup = AirportLookup(), airport = try #require(lookup.airport(for: "BKK"))
        let flight = Flight(id: UUID(), date: original.startDate, airline: "Test", flightNumber: "T1",
            originAirport: "BKK", destinationAirport: "BKK", departureTime: original.startDate,
            arrivalTime: original.startDate, departureAirport: airport, arrivalAirport: airport, aircraft: nil, cabin: nil)
        let trip = Trip(id: original.id, name: original.name, country: original.country, startDate: original.startDate,
            endDate: original.endDate, travelers: original.travelers, timeZoneIdentifier: original.timeZoneIdentifier,
            destinations: original.destinations, flights: [flight], accommodations: original.accommodations,
            activities: [activity], restaurants: [restaurant], transportItems: original.transportItems,
            tripDays: original.tripDays, bookingLinks: original.bookingLinks)
        let annotations = TripMapAnnotationBuilder(airportLookup: AirportLookup()).annotations(for: trip)
        #expect(annotations.contains { $0.type == .accommodation })
        #expect(annotations.contains { $0.type == .airport })
        #expect(annotations.contains { $0.type == .restaurant })
        #expect(annotations.contains { $0.type == .activity })
        let focus = SearchLocation(name: "Khao Sok", latitude: 8.91, longitude: 98.53)
        let region = TripMapRegionBuilder.region(around: focus)
        #expect(region.center.latitude == focus.latitude)
        #expect(region.center.longitude == focus.longitude)
        #expect(region.span.latitudeDelta > 0)
        #expect(region.span.longitudeDelta > 0)
    }

    @Test @MainActor func OCRExtractsReferencesAirportsAndAccommodationPlace() async throws {
        let trip = try repository.currentTrip(), extractor = DeterministicBookingExtractor()
        let flight = try await extractor.extract(text: RecognizedBookingText(originalText: """
        Thai AirAsia
        FD5422
        Booking reference: ABC123
        CNX 08:25
        URT 10:15
        """), trip: trip)
        #expect(flight.detectedType == .flight)
        #expect(flight.fields["bookingReference"]?.value == "ABC123")
        #expect(flight.fields["originAirportCode"]?.value == "CNX")
        #expect(flight.fields["originAirportName"]?.value == "Chiang Mai International Airport")
        #expect(flight.fields["destinationAirportCode"]?.value == "URT")
        #expect(flight.fields["destinationAirportLatitude"] != nil)

        let hotel = extractor.extract(text: RecognizedBookingText(originalText: """
        Hotel: Our Jungle House
        Confirmation number: KH12345
        Khao Sok
        Check-in: 9 Sep
        Check-out: 10 Sep
        """), trip: trip, forcedType: .accommodation)
        #expect(hotel.fields["bookingReference"]?.value == "KH12345")
        #expect(hotel.fields["placeName"]?.value == "Khao Sok")
    }

    @Test @MainActor func OCRTypeSwitchReparsesTargetFieldsAndKeepsReference() throws {
        let trip = try repository.currentTrip()
        let text = RecognizedBookingText(originalText: """
        Flight FD5422
        Booking reference: ABC123
        Hotel: Our Jungle House
        Place: Khao Sok
        Check-in: 9 Sep
        Check-out: 10 Sep
        CNX 08:25
        URT 10:15
        """)
        let extractor = DeterministicBookingExtractor()
        let flight = extractor.extract(text: text, trip: trip, forcedType: .flight)
        #expect(flight.detectedType == .flight)
        #expect(flight.fields["flightNumber"]?.value == "FD5422")

        let hotel = BookingReclassificationService().reparse(flight, as: .accommodation, trip: trip)
        #expect(hotel.detectedType == .accommodation)
        #expect(hotel.fields["name"]?.value == "Our Jungle House")
        #expect(hotel.fields["placeName"]?.value == "Khao Sok")
        #expect(hotel.fields["bookingReference"]?.value == "ABC123")

        let flightAgain = BookingReclassificationService().reparse(hotel, as: .flight, trip: trip)
        #expect(flightAgain.detectedType == .flight)
        #expect(flightAgain.fields["originAirportCode"]?.value == "CNX")
        #expect(flightAgain.fields["bookingReference"]?.value == "ABC123")
    }

    @Test @MainActor func saveConfirmationOnlyAppearsAfterSuccessfulPersistence() {
        let feedback = AppFeedbackState()
        feedback.reportSave(kind: .flight, isNew: true, succeeded: false)
        #expect(feedback.message == nil)
        feedback.reportSave(kind: .flight, isNew: true, succeeded: true)
        #expect(feedback.message == "Vlucht toegevoegd")
        feedback.clear()
        feedback.reportSave(kind: .accommodation, isNew: true, succeeded: true)
        #expect(feedback.message == "Accommodatie toegevoegd")
        feedback.clear()
        feedback.reportSave(kind: .flight, isNew: false, succeeded: true)
        #expect(feedback.message == "Wijzigingen opgeslagen")
    }

    @Test @MainActor func todayDiscoverNavigationCarriesLocationCategoryAndSelection() {
        let navigation = AppNavigationState()
        let location = SearchLocation(name: "Our Jungle House", latitude: 8.91, longitude: 98.53)
        navigation.openDiscover(location: location, category: .restaurant, selectedResultID: "restaurant-a")
        #expect(navigation.selectedTab == .discover)
        #expect(navigation.discoverLocation == location)
        #expect(navigation.discoverCategory == .restaurant)
        #expect(navigation.discoverResultID == "restaurant-a")
    }

    @Test @MainActor func discoveryActionsSeparatePlaceDetailsFromNavigation() async {
        let opener = MapOpeningSpy()
        let result = DiscoveryResult(id: "one", name: "Restaurant A", category: .restaurant,
            address: "Khao Sok", latitude: 8.91, longitude: 98.53, distanceMeters: 350,
            phone: nil, websiteURL: nil)
        let actions = DiscoveryMapActions(opener: opener)
        await actions.discover(result)
        #expect(opener.openedPlaceNames == ["Restaurant A"])
        #expect(opener.navigatedNames.isEmpty)
        await actions.navigate(result)
        #expect(opener.navigatedNames == ["Restaurant A"])
    }

    @Test func travelDurationUsesCompleteDateTimesAndDutchCompactFormat() {
        let calendar = TripCalendar.calendar(in: TripCalendar.thailandTimeZone)
        let day = TripCalendar.date(2026, 9, 9)
        let flightStart = calendar.date(bySettingHour: 8, minute: 25, second: 0, of: day)!
        let flightEnd = calendar.date(bySettingHour: 10, minute: 15, second: 0, of: day)!
        let taxiEnd = calendar.date(bySettingHour: 12, minute: 45, second: 0, of: day)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let ferryStart = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: day)!
        let ferryEnd = calendar.date(bySettingHour: 1, minute: 15, second: 0, of: nextDay)!
        #expect(TravelDurationFormatter.string(from: flightStart, to: flightEnd) == "1u 50m")
        #expect(TravelDurationFormatter.string(from: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day), to: taxiEnd) == "45m")
        #expect(TravelDurationFormatter.string(from: ferryStart, to: ferryEnd) == "1u 45m")
        #expect(TravelDurationFormatter.string(from: ferryEnd, to: ferryStart) == nil)
    }

    @Test @MainActor func legacySingleTripMigratesToVersionedLibraryWithoutDeletingBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Migration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let package = try repository.loadPackage()
        let legacyURL = directory.appendingPathComponent("thailand-trip.json")
        try TripJSONCoding.encoder().encode(package).write(to: legacyURL)

        let store = TripStore(documentsDirectory: directory)
        store.load()
        #expect(store.errorMessage == nil)
        #expect(store.trips == [package.trip])
        #expect(store.selectedTripId == package.trip.id)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
        let data = try Data(contentsOf: directory.appendingPathComponent("travel-library.json"))
        let library = try TripJSONCoding.decoder().decode(TravelLibrary.self, from: data)
        #expect(library.schemaVersion == TravelLibrary.currentSchemaVersion)
        #expect(library.trips.first?.flights == package.trip.flights)
        #expect(library.trips.first?.accommodations == package.trip.accommodations)
        #expect(library.trips.first?.activities == package.trip.activities)
    }

    @Test @MainActor func itemsStaySeparatedAndSelectedTripPersists() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let thailand = try #require(fixture.store.trip)
        let paris = Trip.empty(name: "Parijs 2027", country: "Frankrijk", startDate: Date(), endDate: Date())
        #expect(fixture.store.addTrip(paris))
        let activity = Activity(id: UUID(), destinationId: nil, date: Date(), startTime: Date(), endTime: nil,
            title: "Louvre", category: ItineraryCategory.activity.rawValue, description: nil,
            location: TripLocation(placeName: "Parijs", address: nil, latitude: 48.8606, longitude: 2.3376),
            latitude: 48.8606, longitude: 2.3376, websiteURL: nil, bookingURL: nil, notes: nil, url: nil,
            attachmentFilename: nil, isFavorite: false, isCompleted: false)
        #expect(fixture.store.addActivity(activity))
        #expect(fixture.store.trip?.activities.contains(where: { $0.id == activity.id }) == true)
        #expect(fixture.store.selectTrip(id: thailand.id))
        #expect(fixture.store.trip?.activities.contains(where: { $0.id == activity.id }) == false)
        #expect(fixture.store.selectTrip(id: paris.id))
        let reloaded = TripStore(documentsDirectory: fixture.directory); reloaded.load()
        #expect(reloaded.selectedTripId == paris.id)
        #expect(reloaded.trip?.activities.contains(where: { $0.id == activity.id }) == true)
    }

    @Test func activityFiltersUseOnlyRealAvailableMetadata() {
        let complete = DiscoveryResult(id: "complete", name: "Temple", category: .activity, address: nil,
            latitude: 1, longitude: 1, distanceMeters: 900, phone: nil, websiteURL: nil,
            rating: 4.7, reviewCount: 500, priceLevel: .inexpensive,
            editorialSignals: [.init(source: .reisjunk, sourceURL: nil, matchConfidence: 0.9),
                               .init(source: .lonelyPlanet, sourceURL: nil, matchConfidence: 0.9)])
        let unknown = DiscoveryResult(id: "unknown", name: "Park", category: .activity, address: nil,
            latitude: 1, longitude: 1, distanceMeters: 500, phone: nil, websiteURL: nil)
        var filters = ActivityFilters(maxDistanceMeters: 2_000, minimumRating: 4.5, minimumReviewCount: 100,
                                      starWorthyOnly: true)
        filters.priceLevels = [.inexpensive]
        #expect(filters.includes(complete))
        #expect(!filters.includes(unknown))
        filters = ActivityFilters(maxDistanceMeters: 1_000)
        #expect(filters.includes(unknown))
    }

    @Test func discoveryFiltersExcludeUnknownMetadataOnlyWhenRelevant() {
        let known = DiscoveryResult(id: "known", name: "Known", category: .restaurant, address: nil,
            latitude: 1, longitude: 1, distanceMeters: 800, phone: nil, websiteURL: nil,
            rating: 4.6, reviewCount: 600, priceLevel: .moderate)
        let unknown = DiscoveryResult(id: "unknown", name: "Unknown", category: .restaurant, address: nil,
            latitude: 1, longitude: 1, distanceMeters: 500, phone: nil, websiteURL: nil)
        #expect(DiscoveryFilters(maxDistanceMeters: 1_000).includes(unknown))
        #expect(DiscoveryFilters(maxDistanceMeters: nil, priceLevels: [.moderate]).includes(known))
        #expect(!DiscoveryFilters(maxDistanceMeters: nil, priceLevels: [.moderate]).includes(unknown))
        #expect(DiscoveryFilters(maxDistanceMeters: nil, minimumRating: 4.5).includes(known))
        #expect(!DiscoveryFilters(maxDistanceMeters: nil, minimumRating: 4.5).includes(unknown))
        #expect(DiscoveryFilters(maxDistanceMeters: nil, minimumReviewCount: 500).includes(known))
        #expect(!DiscoveryFilters(maxDistanceMeters: nil, minimumReviewCount: 500).includes(unknown))
    }

    @Test func recommendationBadgesAreConservativeAndCategoryAware() {
        let editorial = EditorialSignal(source: .reisjunk, sourceURL: nil, matchConfidence: 0.95)
        let second = EditorialSignal(source: .travelfish, sourceURL: nil, matchConfidence: 0.9)
        func item(_ id: String, category: DiscoveryCategory, rating: Double, reviews: Int,
                  signals: [EditorialSignal]) -> DiscoveryRecommendation {
            DiscoveryRecommendation(id: id, name: id, category: category, address: nil, latitude: 1,
                longitude: 1, distanceMeters: 500, phone: nil, websiteURL: nil, rating: rating,
                reviewCount: reviews, editorialSignals: signals)
        }
        let scorer = RecommendationScorer()
        #expect(scorer.score(item("popular", category: .activity, rating: 4.8, reviews: 3_000,
                                  signals: [editorial, second])).badges.contains(.starWorthy))
        #expect(scorer.score(item("gem", category: .restaurant, rating: 4.7, reviews: 150,
                                  signals: [editorial, second])).badges.contains(.hiddenGem))
        #expect(scorer.score(item("view", category: .viewpoint, rating: 4.7, reviews: 900,
                                  signals: [editorial])).badges.contains(.instagramWorthy))
        #expect(!scorer.score(item("weak", category: .activity, rating: 5, reviews: 3,
                                   signals: [])).badges.contains(.starWorthy))
        #expect(scorer.score(item("atm", category: .atm, rating: 5, reviews: 5_000,
                                  signals: [editorial])).badges.isEmpty)
    }

    @Test func editorialMatchingRequiresNormalizedNameAndCity() {
        let signal = EditorialSignal(source: .lonelyPlanet, sourceURL: nil, matchConfidence: 0.9)
        let place = DiscoveryRecommendation(id: "p", name: "Karon Viewpoint", category: .viewpoint,
            address: nil, latitude: 7.797, longitude: 98.302, distanceMeters: nil, phone: nil, websiteURL: nil)
        let matches = [
            EditorialRecommendation(normalizedName: "karon-viewpoint", city: "Phuket", latitude: 7.797,
                                    longitude: 98.302, signal: signal),
            EditorialRecommendation(normalizedName: "Karon Viewpoint", city: "Chiang Mai", latitude: nil,
                                    longitude: nil, signal: .init(source: .reisjunk, sourceURL: nil, matchConfidence: 1))
        ]
        let found = EditorialRecommendationMatcher().signals(for: place, city: "PHUKET", recommendations: matches)
        #expect(found == [signal])
    }

    @Test func editorialMatchingMergesSourcesButRejectsWrongCityAndCategory() {
        let place = DiscoveryRecommendation(id: "wat-pho", name: "Wat Pho", category: .activity,
            address: "Bangkok", latitude: 13.7465, longitude: 100.4930, distanceMeters: 3_000,
            phone: nil, websiteURL: nil)
        let recommendations = [
            EditorialRecommendation(normalizedName: "Wat Pho", city: "Bangkok", latitude: nil, longitude: nil,
                signal: .init(source: .reisjunk, sourceURL: URL(string: "https://example.com/reisjunk"), matchConfidence: 0.9),
                category: .activity),
            EditorialRecommendation(normalizedName: "wat-pho", city: "Bangkok", latitude: 13.7465, longitude: 100.493,
                signal: .init(source: .lonelyPlanet, sourceURL: URL(string: "https://example.com/lp"), matchConfidence: 0.95),
                category: .activity),
            EditorialRecommendation(normalizedName: "Wat Pho", city: "Paris", latitude: nil, longitude: nil,
                signal: .init(source: .tipsThailand, sourceURL: nil, matchConfidence: 1), category: .activity),
            EditorialRecommendation(normalizedName: "Wat Pho", city: "Bangkok", latitude: nil, longitude: nil,
                signal: .init(source: .tripAdvisor, sourceURL: nil, matchConfidence: 1), category: .restaurant)
        ]
        let found = EditorialRecommendationMatcher().signals(for: place, city: "Bangkok", recommendations: recommendations)
        #expect(Set(found.map(\.source)) == [.reisjunk, .lonelyPlanet])
    }

    @Test func rankingBalancesEvidenceAgainstBareRating() {
        let sources = [
            EditorialSignal(source: .reisjunk, sourceURL: nil, matchConfidence: 0.9),
            EditorialSignal(source: .lonelyPlanet, sourceURL: nil, matchConfidence: 0.9)
        ]
        let evidence = DiscoveryRecommendation(id: "a", name: "A", category: .activity, address: nil,
            latitude: 1, longitude: 1, distanceMeters: 3_000, phone: nil, websiteURL: nil,
            rating: 4.7, reviewCount: 2_500, editorialSignals: sources)
        let bareRating = DiscoveryRecommendation(id: "b", name: "B", category: .activity, address: nil,
            latitude: 1, longitude: 1, distanceMeters: 500, phone: nil, websiteURL: nil,
            rating: 4.8, reviewCount: 20)
        let ranked = RecommendationScorer().enrichAndRank([bareRating, evidence])
        #expect(ranked.first?.id == "a")
        #expect(ranked.first?.badges.contains(.starWorthy) == true)
        #expect(ranked.last?.badges.contains(.starWorthy) == false)
    }

    @Test @MainActor func targetTripSaveDoesNotChangeActiveTrip() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let thailand = try #require(fixture.store.trip)
        let paris = Trip.empty(name: "Parijs 2027", country: "Frankrijk", startDate: Date(), endDate: Date())
        #expect(fixture.store.addTrip(paris))
        #expect(fixture.store.selectTrip(id: thailand.id))
        let reservation = RestaurantReservation(id: UUID(), date: Date(), time: Date(), name: "Paris Bistro",
            address: "1 Rue de Test, Paris", latitude: 48.85, longitude: 2.35, reservationName: nil,
            reservationReference: nil, notes: nil, url: nil, attachmentFilename: nil)
        #expect(fixture.store.saveManagedItem(.restaurant(reservation), targetTripID: paris.id))
        #expect(fixture.store.selectedTripId == thailand.id)
        #expect(fixture.store.trip?.restaurants.contains(where: { $0.id == reservation.id }) == false)
        #expect(fixture.store.trip(id: paris.id)?.restaurants.contains(where: { $0.id == reservation.id }) == true)
    }

    @Test @MainActor func mapPlacePrefillsExistingEditorsWithoutManualCoordinates() throws {
        let trip = try repository.currentTrip()
        let place = MapPlace(id: "hotel", name: "Our Test House", placeName: "Khao Sok",
            address: "62 Khlong Sok, Phanom", latitude: 8.91, longitude: 98.53,
            websiteURL: URL(string: "https://example.com"))
        let hotel = TripItemDraft(kind: .accommodation, trip: trip)
        hotel.apply(mapPlace: place)
        #expect(hotel.a == "Our Test House")
        #expect(hotel.f == "Khao Sok")
        #expect(hotel.c == "62 Khlong Sok, Phanom")
        #expect(hotel.coordinate == Coordinate(latitude: 8.91, longitude: 98.53))

        let transfer = TripItemDraft(kind: .transfer, trip: trip)
        transfer.apply(mapPlace: place, routeRole: .destination)
        #expect(transfer.c == "62 Khlong Sok, Phanom")
    }

    @Test @MainActor func mapAccommodationPreservesPingnakornStructuredLocationForToday() async throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let trip = try #require(fixture.store.trip)
        let place = MapPlace(id: "pingnakorn", name: "At Pingnakorn Huaykaew", category: "Hotel",
            placeName: "Chiang Mai", address: "24 Soi Plubplueng, Huay Kaew Road, Chiang Mai, Thailand",
            latitude: 18.7982, longitude: 98.9685, websiteURL: URL(string: "https://www.atpingnakorn.com"))
        let draft = TripItemDraft(kind: .accommodation, trip: trip)
        draft.apply(mapPlace: place)
        let day = draft.startTime
        let item = draft.makeItem(kind: .accommodation, id: UUID(), trip: trip)
        #expect(fixture.store.saveManagedItem(item))
        let saved = try #require(fixture.store.accommodation(for: day))
        #expect(saved.name == "At Pingnakorn Huaykaew")
        #expect(saved.placeName == "Chiang Mai")
        #expect(saved.address.contains("Huay Kaew"))
        #expect(saved.latitude == 18.7982)
        #expect(saved.longitude == 98.9685)
        let location = await TripSearchLocationResolver(geocoder: GeocodingFixture(result: nil))
            .resolve(for: day, in: try #require(fixture.store.trip))
        #expect(location == SearchLocation(name: "Chiang Mai", latitude: 18.7982, longitude: 98.9685))
    }

    @Test @MainActor func bookedRestaurantsAppearImmediatelyInTodayQuery() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let trip = try #require(fixture.store.trip)
        let day = trip.startDate
        let lunch = RestaurantReservation(id: UUID(), date: day,
            time: TripCalendar.calendar(in: trip.timeZone).date(bySettingHour: 12, minute: 0, second: 0, of: day)!,
            name: "Restaurant Lunch", address: "Chiang Mai", latitude: nil, longitude: nil,
            reservationName: nil, reservationReference: nil, notes: nil, url: nil, attachmentFilename: nil)
        let dinner = RestaurantReservation(id: UUID(), date: day,
            time: TripCalendar.calendar(in: trip.timeZone).date(bySettingHour: 19, minute: 0, second: 0, of: day)!,
            name: "Restaurant Dinner", address: "Chiang Mai", latitude: nil, longitude: nil,
            reservationName: nil, reservationReference: nil, notes: nil, url: nil, attachmentFilename: nil)
        #expect(fixture.store.saveManagedItem(.restaurant(lunch)))
        #expect(fixture.store.saveManagedItem(.restaurant(dinner)))
        #expect(fixture.store.restaurants(on: day).map(\.name) == ["Restaurant Lunch", "Restaurant Dinner"])
        #expect(fixture.store.timelineSections().flatMap(\.items).filter { $0.type == .restaurant }.count >= 2)
    }

    @Test func airportLookupSupportsInternationalCodesNamesAndAmbiguousCities() {
        let lookup = AirportLookup()
        #expect(lookup.bestMatch(for: "AMS")?.name == "Amsterdam Airport Schiphol")
        #expect(lookup.bestMatch(for: "BKK")?.name == "Suvarnabhumi Airport")
        #expect(Set(lookup.suggestions(for: "Bangkok").map(\.code)) == ["BKK", "DMK"])
        #expect(lookup.suggestions(for: "London").count >= 2)
        #expect(lookup.suggestions(for: "Amsterdam").contains { $0.code == "AMS" })
    }

    @Test func semanticDateEditorsDoNotExposeGenericDate() {
        #expect(!TripItemKind.flight.showsGenericDate)
        #expect(!TripItemKind.accommodation.showsGenericDate)
        #expect(!TripItemKind.transfer.showsGenericDate)
        #expect(!TripItemKind.ferry.showsGenericDate)
        #expect(!TripItemKind.train.showsGenericDate)
        #expect(!TripItemKind.rentalVehicle.showsGenericDate)
        #expect(TripItemKind.restaurant.showsGenericDate)
        #expect(TripItemKind.activity.showsGenericDate)
    }

    @Test func duplicateDetectorFindsSameNamedNearbyBookedLocation() throws {
        let trip = try repository.currentTrip()
        let accommodation = try #require(trip.accommodations.first)
        let latitude = try #require(accommodation.latitude)
        let longitude = try #require(accommodation.longitude)
        let place = MapPlace(id: "duplicate", name: accommodation.name, placeName: accommodation.placeName,
            address: accommodation.address, latitude: latitude, longitude: longitude)
        let duplicate = TripMapDuplicateDetector().duplicate(of: place, in: trip)
        #expect(duplicate?.sourceID == accommodation.id)
    }

    @Test @MainActor func mapItemConversionPreservesNameAndCoordinates() {
        let mapItem = MKMapItem(location: CLLocation(latitude: 13.69, longitude: 100.75), address: nil)
        mapItem.name = "Suvarnabhumi Airport"
        let place = MapPlace(mapItem: mapItem)
        #expect(place.name == "Suvarnabhumi Airport")
        #expect(place.latitude == 13.69)
        #expect(place.longitude == 100.75)
    }

    private func tripReplacingDestinations(_ trip: Trip, with destinations: [Destination]) -> Trip {
        Trip(id: trip.id, name: trip.name, country: trip.country, startDate: trip.startDate, endDate: trip.endDate,
            travelers: trip.travelers, timeZoneIdentifier: trip.timeZoneIdentifier, destinations: destinations,
            flights: trip.flights, accommodations: trip.accommodations, activities: trip.activities,
            transfers: trip.transfers, ferries: trip.ferries, trains: trip.trains, restaurants: trip.restaurants,
            rentalVehicles: trip.rentalVehicles, otherItems: trip.otherItems, transportItems: trip.transportItems,
            tripDays: trip.tripDays, bookingLinks: trip.bookingLinks)
    }

    private func tripReplacingLocationSources(_ trip: Trip, accommodations: [Accommodation], activities: [Activity],
                                              destinations: [Destination]) -> Trip {
        Trip(id: trip.id, name: trip.name, country: trip.country, startDate: trip.startDate, endDate: trip.endDate,
            travelers: trip.travelers, timeZoneIdentifier: trip.timeZoneIdentifier, destinations: destinations,
            flights: trip.flights, accommodations: accommodations, activities: activities, transfers: trip.transfers,
            ferries: trip.ferries, trains: trip.trains, restaurants: trip.restaurants,
            rentalVehicles: trip.rentalVehicles, otherItems: trip.otherItems, transportItems: trip.transportItems,
            tripDays: trip.tripDays, bookingLinks: trip.bookingLinks)
    }

    @Test func mediaQueriesUseSpecificItemNames() {
        let builder = MediaQueryBuilder()
        #expect(builder.accommodation(name: "At Pingnakorn Huaykaew", place: "Chiang Mai",
            country: "Thailand", address: nil) == "At Pingnakorn Huaykaew Chiang Mai Thailand")
        #expect(builder.flight(carrierName: "Bangkok Airways", aircraft: "Airbus A319") ==
                "Bangkok Airways Airbus A319")
        #expect(builder.activity(name: "Wat Phra That Doi Suthep", place: "Chiang Mai",
            country: "Thailand") == "Wat Phra That Doi Suthep Chiang Mai Thailand")
    }

    @Test func todaySwipeRequiresDominantHorizontalMovement() {
        #expect(TodaySwipeNavigation.dayOffset(horizontal: -80, vertical: 10) == 1)
        #expect(TodaySwipeNavigation.dayOffset(horizontal: 80, vertical: 10) == -1)
        #expect(TodaySwipeNavigation.dayOffset(horizontal: 70, vertical: 90) == nil)
        #expect(TodaySwipeNavigation.dayOffset(horizontal: 40, vertical: 5) == nil)
    }

    @Test func todayNavigationStopsAtTripBoundaries() throws {
        let trip = try repository.currentTrip()
        #expect(TodayDateSelection.moving(trip.startDate, by: -1, in: trip) == nil)
        #expect(TodayDateSelection.moving(trip.endDate, by: 1, in: trip) == nil)
        #expect(TodayDateSelection.moving(trip.startDate, by: 1, in: trip) != nil)
    }

    @Test func oldTripJSONWithoutMediaStillDecodes() throws {
        let trip = try repository.currentTrip()
        let data = try TripJSONCoding.encoder().encode(trip)
        let json = try #require(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: ",\"media\":null", with: "")
        let decoded = try TripJSONCoding.decoder().decode(Trip.self, from: Data(json.utf8))
        #expect(decoded.accommodations.first?.mediaItems.isEmpty == true)
        #expect(decoded.flights.first?.mediaItems.isEmpty == true)
        #expect(decoded.activities.first?.mediaItems.isEmpty == true)
    }

    @Test func tripArchiveRoundTripPreservesRelationshipsAndMedia() throws {
        var trip = try repository.currentTrip()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Archive-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let attachments = AttachmentStore(documentsDirectory: directory)
        let filename = try attachments.saveImageData(testImageData(color: .systemBlue))
        trip.accommodations[0].media = [TripMedia(filename: filename, sourceName: "Eigen foto", isCover: true)]
        let package = try TripArchiveService().export(trip: trip, attachmentStore: attachments,
                                                       destinationDirectory: directory)
        let preview = try TripArchiveService().preview(url: package)
        let importedDirectory = directory.appendingPathComponent("Imported", isDirectory: true)
        let importedStore = AttachmentStore(documentsDirectory: importedDirectory)
        let imported = try TripArchiveService().importedTrip(from: preview, attachmentStore: importedStore)
        #expect(imported.id == trip.id)
        #expect(imported.activities.first?.destinationId == trip.activities.first?.destinationId)
        let importedFilename = try #require(imported.accommodations.first?.coverMedia?.filename)
        #expect(FileManager.default.fileExists(atPath: importedStore.imageURL(for: importedFilename).path))
        #expect(imported.accommodations.first?.coverMedia?.sourceName == "Eigen foto")
    }

    @Test @MainActor func duplicateTripImportCanCopyOrReplace() throws {
        let fixture = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let trip = try #require(fixture.store.trip)
        let originalCount = fixture.store.trips.count
        #expect(fixture.store.importTrip(trip, strategy: .copy))
        #expect(fixture.store.trips.count == originalCount + 1)
        #expect(fixture.store.trips.last?.id != trip.id)
        #expect(fixture.store.importTrip(trip, strategy: .replace))
        #expect(fixture.store.trips.filter { $0.id == trip.id }.count == 1)
    }

    @MainActor
    private func makeTemporaryStore() throws -> (store: TripStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThailandHolidayAppTests-\(UUID().uuidString)", isDirectory: true)
        let store = TripStore(documentsDirectory: directory)
        store.load()
        try #require(store.errorMessage == nil)
        return (store, directory)
    }

    private func testImageData(color: UIColor) -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        return image.pngData()!
    }
}

private struct WeatherFixtureProvider: TripWeatherProviding {
    let forecastsByLatitude: [Double: [TripHourWeather]]

    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather] {
        forecastsByLatitude[latitude] ?? []
    }
}

private struct GeocodingFixture: LocationGeocoding {
    let result: Coordinate?
    func geocode(address: String) async throws -> Coordinate? { result }
}

private struct QueryGeocodingFixture: LocationGeocoding {
    let coordinates: [String: Coordinate]
    func geocode(address: String) async throws -> Coordinate? { coordinates[address] }
}

@MainActor
private final class RadiusDiscoveryFixture: LocalDiscoverySearching, RadiusLocalDiscoverySearching {
    struct Request { let location: SearchLocation; let category: DiscoveryCategory; let radius: Double }
    var requests: [Request] = []

    func search(around location: SearchLocation, category: DiscoveryCategory) async throws -> [DiscoveryResult] {
        try await search(around: location, category: category, radiusMeters: 25_000)
    }

    func search(around location: SearchLocation, category: DiscoveryCategory,
                radiusMeters: Double) async throws -> [DiscoveryResult] {
        requests.append(Request(location: location, category: category, radius: radiusMeters))
        return [
            DiscoveryResult(id: "a", name: "Restaurant A", category: category, address: "Bangkok",
                latitude: 13.77, longitude: 100.51, distanceMeters: 2_000, phone: nil, websiteURL: nil),
            DiscoveryResult(id: "b", name: "Restaurant B", category: category, address: "Bangkok",
                latitude: 13.80, longitude: 100.55, distanceMeters: 8_000, phone: nil, websiteURL: nil),
            DiscoveryResult(id: "fr", name: "Restaurant C France", category: category, address: "France",
                latitude: 48.85, longitude: 2.35, distanceMeters: 9_000_000, phone: nil, websiteURL: nil)
        ]
    }
}

@MainActor
private final class DiscoveryFixtureSearcher: LocalDiscoverySearching {
    struct Request { let location: SearchLocation; let category: DiscoveryCategory }
    var requests: [Request] = []

    func search(around location: SearchLocation, category: DiscoveryCategory) async throws -> [DiscoveryResult] {
        requests.append(Request(location: location, category: category))
        return [
            DiscoveryResult(id: "far-\(category.rawValue)", name: "Verder", category: category, address: nil,
                latitude: location.latitude, longitude: location.longitude, distanceMeters: 800, phone: nil, websiteURL: nil),
            DiscoveryResult(id: "near-\(category.rawValue)", name: "Dichtbij", category: category, address: nil,
                latitude: location.latitude, longitude: location.longitude, distanceMeters: 100, phone: nil, websiteURL: nil)
        ]
    }
}

@MainActor
private final class MapOpeningSpy: MapOpening {
    var navigatedNames: [String] = []
    var openedPlaceNames: [String] = []
    func navigate(to location: TripLocation, name: String?) async -> Bool {
        navigatedNames.append(name ?? ""); return true
    }
    func openPlace(_ location: TripLocation, name: String?) async -> Bool {
        openedPlaceNames.append(name ?? ""); return true
    }
}
