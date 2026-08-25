import Foundation

enum BookingClassification: String, Codable, Equatable {
    case rentalVehicle
    case unknown
}

struct RentalVehicleDraft: Equatable {
    var vehicleType: RentalVehicleType
    var company: String?
    var pickupDate: Date?
    var pickupTime: Date?
    var pickupLocation: String?
    var dropoffDate: Date?
    var dropoffTime: Date?
    var dropoffLocation: String?
    var vehicleDescription: String?
    var bookingReference: String?
    var renterName: String?
}

struct BookingTextParser {
    func classify(_ text: String) -> BookingClassification {
        let normalized = text.lowercased()
        let rentalTerms = [
            "rental car", "car rental", "car hire", "vehicle rental", "scooter rental",
            "motorbike rental", "motorcycle rental", "bike rental", "bike hire",
            "bicycle rental", "e-bike", "ebike", "quad rental", "atv", "all-terrain vehicle"
        ]
        let generalTerms = ["pick-up", "pickup", "drop-off", "return", "rental", "hire", "renter", "vehicle"]
        if rentalTerms.contains(where: normalized.contains)
            || generalTerms.filter({ normalized.contains($0) }).count >= 2 {
            return .rentalVehicle
        }
        return .unknown
    }

    func rentalVehicleType(in text: String) -> RentalVehicleType {
        let value = text.lowercased()
        if value.contains("e-bike") || value.contains("ebike") || value.contains("electric bike") { return .eBike }
        if value.contains("scooter") { return .scooter }
        if value.contains("motorcycle") || value.contains("motorbike") { return .motorcycle }
        if value.contains("bicycle") || value.contains("bike hire") || value.contains("bike rental") { return .bicycle }
        if value.contains("quad") || value.contains("atv") || value.contains("all-terrain") { return .quad }
        if value.contains("rental car") || value.contains("car rental") || value.contains("car hire") { return .car }
        return .other
    }

    func parseRentalVehicle(_ text: String) -> RentalVehicleDraft {
        let pickupDateText = value(afterAny: ["pick-up date", "pickup date", "ophaaldatum"], in: text)
        let pickupTimeText = value(afterAny: ["pick-up time", "pickup time", "ophaaltijd"], in: text)
        let dropoffDateText = value(afterAny: ["drop-off date", "dropoff date", "return date", "inleverdatum"], in: text)
        let dropoffTimeText = value(afterAny: ["drop-off time", "dropoff time", "return time", "inlevertijd"], in: text)
        return RentalVehicleDraft(
            vehicleType: rentalVehicleType(in: text),
            company: value(afterAny: ["company", "rental company", "verhuurder"], in: text),
            pickupDate: pickupDateText.flatMap(parseDate),
            pickupTime: pickupTimeText.flatMap(parseTime),
            pickupLocation: value(afterAny: ["pick-up location", "pickup location", "ophaallocatie"], in: text),
            dropoffDate: dropoffDateText.flatMap(parseDate),
            dropoffTime: dropoffTimeText.flatMap(parseTime),
            dropoffLocation: value(afterAny: ["drop-off location", "dropoff location", "inleverlocatie"], in: text),
            vehicleDescription: value(afterAny: ["vehicle", "model", "voertuig"], in: text),
            bookingReference: value(afterAny: ["booking reference", "reservation number", "reserveringsnummer"], in: text),
            renterName: value(afterAny: ["renter", "driver", "naam huurder"], in: text)
        )
    }

    private func parseDate(_ value: String) -> Date? {
        for format in ["yyyy-MM-dd", "dd-MM-yyyy", "dd/MM/yyyy", "d MMM yyyy", "d MMMM yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TripCalendar.thailandTimeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private func parseTime(_ value: String) -> Date? {
        for format in ["HH:mm", "H:mm", "h:mm a"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TripCalendar.thailandTimeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: value.uppercased()) { return date }
        }
        return nil
    }

    private func value(afterAny labels: [String], in text: String) -> String? {
        for line in text.split(whereSeparator: \Character.isNewline) {
            let value = String(line)
            let lower = value.lowercased()
            for label in labels where lower.hasPrefix(label) {
                let suffix = value.dropFirst(label.count).trimmingCharacters(in: CharacterSet(charactersIn: ": -"))
                if !suffix.isEmpty { return suffix }
            }
        }
        return nil
    }
}
