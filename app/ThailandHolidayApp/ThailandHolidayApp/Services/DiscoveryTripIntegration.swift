import Foundation

struct DiscoveryTripItemMapper {
    func kind(for category: DiscoveryCategory) -> TripItemKind {
        if category.isFood { return .restaurant }
        if category.supportsRecommendations { return .activity }
        return .other
    }

    func item(from result: DiscoveryResult, date: Date, time: Date,
              trip: Trip, id: UUID = UUID()) -> ManagedTripItem {
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        let day = calendar.startOfDay(for: date)
        let scheduled = calendar.combining(day: day, time: time)
        switch kind(for: result.category) {
        case .restaurant:
            return .restaurant(RestaurantReservation(id: id, date: day, time: scheduled, name: result.name,
                address: result.address, latitude: result.latitude, longitude: result.longitude,
                reservationName: nil, reservationReference: nil, notes: nil, url: result.websiteURL,
                attachmentFilename: nil, googlePlaceID: result.googlePlaceID))
        case .activity:
            let itineraryCategory: ItineraryCategory = result.category == .viewpoint ? .viewpoint : .activity
            return .activity(Activity(id: id, destinationId: nil, date: day, startTime: scheduled, endTime: nil,
                title: result.name, category: itineraryCategory.rawValue, description: nil,
                location: TripLocation(placeName: result.name, address: result.address,
                    latitude: result.latitude, longitude: result.longitude, googlePlaceID: result.googlePlaceID),
                latitude: result.latitude, longitude: result.longitude, websiteURL: result.websiteURL,
                bookingURL: nil, notes: nil, url: result.websiteURL, attachmentFilename: nil,
                isFavorite: false, isCompleted: false))
        default:
            return .other(TripEvent(id: id, date: day, startTime: scheduled, endTime: nil,
                title: result.name, location: result.address ?? result.name, notes: nil,
                url: result.websiteURL, attachmentFilename: nil, googlePlaceID: result.googlePlaceID))
        }
    }
}

struct DiscoveryDuplicateDetector {
    func contains(_ result: DiscoveryResult, on date: Date? = nil, in trip: Trip) -> Bool {
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        func sameDay(_ itemDate: Date) -> Bool { date.map { calendar.isDate(itemDate, inSameDayAs: $0) } ?? true }
        if let placeID = result.googlePlaceID {
            if trip.restaurants.contains(where: { $0.googlePlaceID == placeID && sameDay($0.date) }) { return true }
            if trip.activities.contains(where: { $0.location?.googlePlaceID == placeID && sameDay($0.date) }) { return true }
            if trip.otherItems.contains(where: { $0.googlePlaceID == placeID && sameDay($0.date) }) { return true }
            if trip.accommodations.contains(where: { $0.googlePlaceID == placeID }) { return true }
        }
        let normalizedName = normalize(result.name)
        let candidates: [(String, Double?, Double?, Date?)] =
            trip.restaurants.map { ($0.name, $0.latitude, $0.longitude, $0.date) }
            + trip.activities.map { ($0.title, $0.latitude, $0.longitude, $0.date) }
            + trip.otherItems.map { ($0.title, nil, nil, $0.date) }
        return candidates.contains { name, latitude, longitude, itemDate in
            guard normalize(name) == normalizedName,
                  itemDate.map(sameDay) ?? true else { return false }
            guard let latitude, let longitude else { return true }
            return hypot(latitude - result.latitude, longitude - result.longitude) < 0.001
        }
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
