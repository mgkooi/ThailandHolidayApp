import Foundation
import MapKit
import OSLog

struct RecognizedBookingText: Equatable, Sendable {
    let originalText: String
    let normalizedText: String

    init(originalText: String, normalizer: BookingTextNormalizer = BookingTextNormalizer()) {
        self.originalText = originalText
        normalizedText = normalizer.normalize(originalText)
    }
}

struct BookingTextNormalizer: Sendable {
    func normalize(_ text: String) -> String {
        var seen = Set<String>()
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { rawLine -> String? in
                var line = rawLine.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { return nil }
                line = normalizeContextualTime(in: line)
                line = normalizeDateSeparators(in: line)
                let duplicateKey = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                guard seen.insert(duplicateKey).inserted else { return nil }
                return line
            }
            .joined(separator: "\n")
    }

    private func normalizeContextualTime(in line: String) -> String {
        line.replacingOccurrences(of: #"(?<![A-Z0-9])[Oo](?=\d:\d{2}\b)"#, with: "0", options: .regularExpression)
            .replacingOccurrences(of: #"(?<![A-Z0-9])[Il](?=\d:\d{2}\b)"#, with: "1", options: .regularExpression)
    }

    private func normalizeDateSeparators(in line: String) -> String {
        line.replacingOccurrences(of: #"\b(\d{1,2})[.]([0-1]?\d)[.](\d{4})\b"#, with: "$1-$2-$3", options: .regularExpression)
    }
}

enum BookingDetectedType: String, Codable, Equatable, Sendable {
    case flight, accommodation, transfer, rentalVehicle, ferry, train, restaurant, activity, other
}

struct ExtractedBookingField: Equatable, Sendable {
    let value: String
    let confidence: Double
}

struct BookingExtractionResult: Equatable, Sendable {
    let detectedType: BookingDetectedType
    let classificationConfidence: Double
    let fields: [String: ExtractedBookingField]
    let warnings: [String]
    let originalRecognizedText: String
    let normalizedText: String

    var recognitionLabel: String { classificationConfidence >= 0.8 && warnings.isEmpty ? "Goed" : "Controleer" }
}

protocol BookingExtracting {
    func extract(text: RecognizedBookingText, trip: Trip) async throws -> BookingExtractionResult
}

struct AirportInfo: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(code)-\(name)" }
    let code: String
    let name: String
    let city: String
    let country: String
    let address: String
    let latitude: Double
    let longitude: Double

    var location: TripLocation {
        TripLocation(placeName: "\(code) · \(name)", address: address, latitude: latitude, longitude: longitude)
    }
}

struct AirportLookup: Sendable {
    let airports: [AirportInfo] = [
        AirportInfo(code:"BKK",name:"Suvarnabhumi Airport",city:"Bangkok",country:"Thailand",address:"999 Nong Prue, Bang Phli, Samut Prakan, Thailand",latitude:13.6900,longitude:100.7501),
        AirportInfo(code:"DMK",name:"Don Mueang International Airport",city:"Bangkok",country:"Thailand",address:"222 Vibhavadi Rangsit Road, Bangkok, Thailand",latitude:13.9126,longitude:100.6068),
        AirportInfo(code:"CNX",name:"Chiang Mai International Airport",city:"Chiang Mai",country:"Thailand",address:"60 Mahidol Road, Chiang Mai, Thailand",latitude:18.7668,longitude:98.9626),
        AirportInfo(code:"URT",name:"Surat Thani International Airport",city:"Surat Thani",country:"Thailand",address:"Maluan, Phunphin, Surat Thani, Thailand",latitude:9.1326,longitude:99.1356),
        AirportInfo(code:"USM",name:"Samui International Airport",city:"Koh Samui",country:"Thailand",address:"Bo Put, Ko Samui, Surat Thani, Thailand",latitude:9.5478,longitude:100.0623)
        ,AirportInfo(code:"AMS",name:"Amsterdam Airport Schiphol",city:"Amsterdam",country:"Netherlands",address:"Evert van de Beekstraat 202, Schiphol, Netherlands",latitude:52.3105,longitude:4.7683)
        ,AirportInfo(code:"CDG",name:"Paris Charles de Gaulle Airport",city:"Paris",country:"France",address:"95700 Roissy-en-France, France",latitude:49.0097,longitude:2.5479)
        ,AirportInfo(code:"ORY",name:"Paris Orly Airport",city:"Paris",country:"France",address:"94390 Orly, France",latitude:48.7262,longitude:2.3652)
        ,AirportInfo(code:"JFK",name:"John F. Kennedy International Airport",city:"New York",country:"United States",address:"Queens, NY 11430, United States",latitude:40.6413,longitude:-73.7781)
        ,AirportInfo(code:"LHR",name:"London Heathrow Airport",city:"London",country:"United Kingdom",address:"Hounslow, United Kingdom",latitude:51.4700,longitude:-0.4543)
        ,AirportInfo(code:"LGW",name:"London Gatwick Airport",city:"London",country:"United Kingdom",address:"Horley, Gatwick, United Kingdom",latitude:51.1537,longitude:-0.1821)
        ,AirportInfo(code:"LCY",name:"London City Airport",city:"London",country:"United Kingdom",address:"Hartmann Road, London, United Kingdom",latitude:51.5053,longitude:0.0553)
        ,AirportInfo(code:"STN",name:"London Stansted Airport",city:"London",country:"United Kingdom",address:"Stansted, United Kingdom",latitude:51.8860,longitude:0.2389)
        ,AirportInfo(code:"SIN",name:"Singapore Changi Airport",city:"Singapore",country:"Singapore",address:"Airport Boulevard, Singapore",latitude:1.3644,longitude:103.9915)
        ,AirportInfo(code:"KUL",name:"Kuala Lumpur International Airport",city:"Kuala Lumpur",country:"Malaysia",address:"Sepang, Selangor, Malaysia",latitude:2.7456,longitude:101.7072)
        ,AirportInfo(code:"HKG",name:"Hong Kong International Airport",city:"Hong Kong",country:"Hong Kong",address:"Chek Lap Kok, Hong Kong",latitude:22.3080,longitude:113.9185)
        ,AirportInfo(code:"DXB",name:"Dubai International Airport",city:"Dubai",country:"United Arab Emirates",address:"Dubai, United Arab Emirates",latitude:25.2532,longitude:55.3657)
        ,AirportInfo(code:"DOH",name:"Hamad International Airport",city:"Doha",country:"Qatar",address:"Doha, Qatar",latitude:25.2731,longitude:51.6081)
    ]

    func airport(for code: String) -> AirportInfo? { airports.first { $0.code == code.uppercased() } }
    func suggestions(for query: String) -> [AirportInfo] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        let matches = airports.filter {
            $0.code.localizedCaseInsensitiveContains(value)
                || $0.name.localizedCaseInsensitiveContains(value)
                || $0.city.localizedCaseInsensitiveContains(value)
        }
#if DEBUG
        Self.logger.debug("Airport search query=\(value, privacy: .public) candidates=\(matches.count, privacy: .public)")
#endif
        return matches
    }
    func bestMatch(for query: String) -> AirportInfo? {
        let matches = suggestions(for: query)
        let chosen = matches.first(where: { $0.code.caseInsensitiveCompare(query) == .orderedSame })
            ?? (matches.count == 1 ? matches[0] : nil)
#if DEBUG
        Self.logger.debug("Airport chosen code=\(chosen?.code ?? "none", privacy: .public) name=\(chosen?.name ?? "none", privacy: .public)")
#endif
        return chosen
    }
    private static let logger = Logger(subsystem: "nl.martijnkooi.ThailandHolidayApp", category: "AirportSearch")
}

@MainActor protocol AirportSearchProviding {
    func suggestions(for query: String) async -> [AirportInfo]
}

@MainActor struct MapKitAirportSearchService: AirportSearchProviding {
    let lookup = AirportLookup()

    func suggestions(for query: String) async -> [AirportInfo] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        let offline = lookup.suggestions(for: value)
        if !offline.isEmpty { return offline }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(value) airport"
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        return items.prefix(8).map { item in
            let coordinate = item.location.coordinate
            let locality = item.placemark.locality ?? item.placemark.administrativeArea ?? ""
            let country = item.placemark.country ?? ""
            let known = lookup.bestMatch(for: item.name ?? "") ?? lookup.bestMatch(for: locality)
            return AirportInfo(code: known?.code ?? "", name: item.name ?? "Airport", city: locality,
                               country: country, address: item.address?.fullAddress ?? [locality, country].filter { !$0.isEmpty }.joined(separator: ", "),
                               latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}

struct DeterministicBookingExtractor: BookingExtracting {
    let airportLookup = AirportLookup()
    let rentalParser = BookingTextParser()

    func extract(text: RecognizedBookingText, trip: Trip) async throws -> BookingExtractionResult {
        let classification = classify(text.normalizedText)
        return extract(text: text, trip: trip, forcedType: classification.type, confidence: classification.confidence)
    }

    func extract(text: RecognizedBookingText, trip: Trip, forcedType: BookingDetectedType) -> BookingExtractionResult {
        extract(text: text, trip: trip, forcedType: forcedType, confidence: 1)
    }

    private func extract(text: RecognizedBookingText, trip: Trip, forcedType: BookingDetectedType, confidence: Double) -> BookingExtractionResult {
        let classification = (type: forcedType, confidence: confidence)
        var fields: [String: ExtractedBookingField] = commonFields(in: text.normalizedText, trip: trip)
        var warnings: [String] = []

        switch classification.type {
        case .flight:
            extractFlight(text.normalizedText, trip: trip, fields: &fields, warnings: &warnings)
        case .rentalVehicle:
            let draft = rentalParser.parseRentalVehicle(text.normalizedText)
            fields["vehicleType"] = .init(value: draft.vehicleType.rawValue, confidence: draft.vehicleType == .other ? 0.45 : 0.9)
            add(draft.company, as: "company", confidence: 0.75, to: &fields)
            add(draft.pickupLocation, as: "pickupLocation", confidence: 0.75, to: &fields)
            add(draft.dropoffLocation, as: "dropoffLocation", confidence: 0.75, to: &fields)
            add(draft.vehicleDescription, as: "vehicleDescription", confidence: 0.8, to: &fields)
            add(draft.bookingReference, as: "bookingReference", confidence: 0.8, to: &fields)
            add(draft.renterName, as: "renterName", confidence: 0.75, to: &fields)
            addDate(draft.pickupDate, as: "pickupDate", trip: trip, to: &fields)
            addDate(draft.dropoffDate, as: "dropoffDate", trip: trip, to: &fields)
            addTime(draft.pickupTime, as: "pickupTime", trip: trip, to: &fields)
            addTime(draft.dropoffTime, as: "dropoffTime", trip: trip, to: &fields)
            if fields["pickupDate"] == nil { extractDates(text.normalizedText, trip: trip, keys: ["pickupDate", "dropoffDate"], fields: &fields) }
            if draft.pickupLocation == nil { warnings.append("Controleer ophaallocatie") }
            if draft.vehicleType == .other { warnings.append("Controleer type vervoer") }
        case .accommodation:
            extractLabeled(text.normalizedText, labels: ["hotel", "property", "accommodation"], key: "name", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["check-in", "check in"], key: "checkIn", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["check-out", "check out"], key: "checkOut", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["room", "room type"], key: "roomType", fields: &fields)
            if fields["bookingReference"] == nil {
                extractLabeled(text.normalizedText, labels: ["booking reference", "confirmation number", "confirmation code", "confirmation"], key: "bookingReference", fields: &fields)
            }
            extractLabeled(text.normalizedText, labels: ["address", "adres"], key: "address", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["place", "plaats", "city", "destination"], key: "placeName", fields: &fields)
            if fields["placeName"] == nil,
               let destination = trip.destinations.first(where: { text.normalizedText.localizedCaseInsensitiveContains($0.name) }) {
                fields["placeName"] = .init(value: destination.name, confidence: 0.9)
            }
            inferUnlabeledName(text.normalizedText, excluding: ["check-in", "check-out"], key: "name", fields: &fields)
            extractDates(text.normalizedText, trip: trip, keys: ["checkIn", "checkOut"], fields: &fields)
            if fields["checkIn"] == nil || fields["checkOut"] == nil { warnings.append("Controleer verblijfsdatums") }
        case .ferry:
            extractRoute(text.normalizedText, fields: &fields)
            extractLabeled(text.normalizedText, labels: ["operator", "ferry"], key: "operator", fields: &fields)
            if fields["origin"] == nil || fields["destination"] == nil { warnings.append("Controleer vertrek- en aankomsthaven") }
        case .transfer:
            extractRoute(text.normalizedText, fields: &fields)
            extractLabeled(text.normalizedText, labels: ["provider", "driver"], key: "provider", fields: &fields)
        case .train:
            extractRoute(text.normalizedText, fields: &fields)
            extractLabeled(text.normalizedText, labels: ["operator", "railway"], key: "operator", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["train number", "train no", "treinnummer"], key: "trainNumber", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["carriage", "rijtuig"], key: "carriage", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["seat", "stoel"], key: "seat", fields: &fields)
        case .restaurant:
            extractLabeled(text.normalizedText, labels: ["restaurant", "venue"], key: "name", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["address", "adres"], key: "address", fields: &fields)
            extractLabeled(text.normalizedText, labels: ["reservation name", "name"], key: "reservationName", fields: &fields)
            inferUnlabeledName(text.normalizedText, excluding: ["reservation", "booking"], key: "name", fields: &fields)
        case .activity:
            inferUnlabeledName(text.normalizedText, excluding: ["booking", "date", "time"], key: "title", fields: &fields)
        default:
            break
        }
        extractDates(text.normalizedText, trip: trip, keys: ["date"], fields: &fields)
        extractTimes(text.normalizedText, keys: ["departureTime", "arrivalTime"], fields: &fields)
        validate(classification.type, fields: fields, warnings: &warnings)
        return BookingExtractionResult(detectedType: classification.type,
            classificationConfidence: classification.confidence, fields: fields, warnings: warnings,
            originalRecognizedText: text.originalText, normalizedText: text.normalizedText)
    }

    private func classify(_ text: String) -> (type: BookingDetectedType, confidence: Double) {
        let lower = text.lowercased()
        let rentalScore = score(["rental", "hire", "return vehicle", "vehicle model", "scooter rental", "bike rental", "atv"], in: lower)
        let transferScore = score(["private transfer", "airport transfer", "hotel pickup", "driver will meet", "meet you at arrivals"], in: lower)
        if transferScore > rentalScore && transferScore > 0 { return (.transfer, min(0.96, 0.65 + Double(transferScore) * 0.1)) }
        if rentalScore > 0 { return (.rentalVehicle, min(0.95, 0.60 + Double(rentalScore) * 0.1)) }
        if regex(#"\b[A-Z0-9]{2}\s?\d{2,4}\b"#, in: text) != nil || score(["flight", "departure airport"], in: lower) > 0 { return (.flight, 0.88) }
        if score(["check-in", "check-out", "room type", "hotel"], in: lower) >= 2 { return (.accommodation, 0.88) }
        if score(["ferry", "catamaran", "speedboat", "pier", "boarding"], in: lower) >= 2 { return (.ferry, 0.85) }
        if score(["train", "carriage", "railway", "station"], in: lower) >= 2 { return (.train, 0.82) }
        if score(["restaurant", "reservation", "table", "guests", "dinner"], in: lower) >= 2 { return (.restaurant, 0.82) }
        if score(["activity", "tour", "excursion", "admission", "ticket"], in: lower) >= 2 { return (.activity, 0.72) }
        return (.other, 0.35)
    }

    private func extractFlight(_ text: String, trip: Trip, fields: inout [String: ExtractedBookingField], warnings: inout [String]) {
        if let number = regex(#"\b([A-Z0-9]{2})\s?(\d{2,4})\b"#, in: text) {
            fields["flightNumber"] = .init(value: number.replacingOccurrences(of: " ", with: ""), confidence: 0.88)
        } else { warnings.append("Controleer vluchtnummer") }
        let codes = regexMatches(#"\b[A-Z]{3}\b"#, in: text).filter { airportLookup.airport(for: $0) != nil }
        if let origin = codes.first {
            fields["originAirportCode"] = .init(value: origin, confidence: 0.95)
            if let airport = airportLookup.airport(for: origin) {
                enrichAirport(airport, prefix: "originAirport", fields: &fields)
            }
        }
        if codes.count > 1 {
            let destination = codes[1]
            fields["destinationAirportCode"] = .init(value: destination, confidence: 0.95)
            if let airport = airportLookup.airport(for: destination) {
                enrichAirport(airport, prefix: "destinationAirport", fields: &fields)
            }
        }
        let times = regexMatches(#"\b(?:[01]?\d|2[0-3]):[0-5]\d\b"#, in: text)
        if let departure = times.first { fields["departureTime"] = .init(value: departure, confidence: 0.9) }
        if times.count > 1 { fields["arrivalTime"] = .init(value: times[1], confidence: 0.9) }
        else { warnings.append("Aankomsttijd niet gevonden") }
        let airlines = ["Thai AirAsia", "Bangkok Airways", "KLM"]
        if let airline = airlines.first(where: { text.localizedCaseInsensitiveContains($0) }) {
            fields["airline"] = .init(value: airline, confidence: 0.98)
        }
        extractLabeled(text, labels: ["booking reference", "booking ref", "confirmation"], key: "bookingReference", fields: &fields)
        extractLabeled(text, labels: ["cabin", "class"], key: "cabin", fields: &fields)
        extractLabeled(text, labels: ["aircraft"], key: "aircraft", fields: &fields)
        if fields["aircraft"] == nil, let aircraft = regex(#"\b(?:Airbus|Boeing)\s+[A-Z0-9-]+\b"#, in: text) {
            fields["aircraft"] = .init(value: aircraft, confidence: 0.92)
        }
        if fields["cabin"] == nil, let cabin = ["Economy", "Premium Economy", "Business", "First"].first(where: text.localizedCaseInsensitiveContains) {
            fields["cabin"] = .init(value: cabin, confidence: 0.92)
        }
        extractDates(text, trip: trip, keys: ["date"], fields: &fields)
    }

    private func extractRoute(_ text: String, fields: inout [String: ExtractedBookingField]) {
        if let route = regex(#"(?m)^(.{2,50})\s(?:→|->| to )\s(.{2,50})$"#, in: text) {
            let parts = route.components(separatedBy: route.contains("→") ? "→" : route.contains("->") ? "->" : " to ")
            if parts.count == 2 {
                fields["origin"] = .init(value: parts[0].trimmingCharacters(in: .whitespaces), confidence: 0.8)
                fields["destination"] = .init(value: parts[1].trimmingCharacters(in: .whitespaces), confidence: 0.8)
            }
        }
    }

    private func validate(_ type: BookingDetectedType, fields: [String: ExtractedBookingField], warnings: inout [String]) {
        if [.flight, .ferry, .train, .transfer].contains(type),
           let origin = fields["origin"]?.value ?? fields["originAirportCode"]?.value,
           let destination = fields["destination"]?.value ?? fields["destinationAirportCode"]?.value,
           origin.caseInsensitiveCompare(destination) == .orderedSame {
            warnings.append("Vertrek en bestemming zijn gelijk")
        }
        if type == .flight, let number = fields["flightNumber"]?.value,
           number.range(of: #"^[A-Z0-9]{2}\d{2,4}$"#, options: .regularExpression) == nil {
            warnings.append("Controleer vluchtnummer")
        }
    }

    private func extractLabeled(_ text: String, labels: [String], key: String, fields: inout [String: ExtractedBookingField]) {
        for line in text.components(separatedBy: .newlines) {
            for label in labels.sorted(by: { $0.count > $1.count }) where line.lowercased().hasPrefix(label) {
                let value = line.dropFirst(label.count).trimmingCharacters(in: CharacterSet(charactersIn: ": -"))
                if !value.isEmpty { fields[key] = .init(value: value, confidence: 0.78); return }
            }
        }
    }

    private func add(_ value: String?, as key: String, confidence: Double, to fields: inout [String: ExtractedBookingField]) {
        if let value, !value.isEmpty { fields[key] = .init(value: value, confidence: confidence) }
    }

    private func commonFields(in text: String, trip: Trip) -> [String: ExtractedBookingField] {
        var fields: [String: ExtractedBookingField] = [:]
        if let url = regex(#"https?://[^\s<>]+"#, in: text), URL(string: url) != nil {
            fields["url"] = .init(value: url, confidence: 0.98)
        }
        extractLabeled(text, labels: ["booking reference", "booking id", "booking number", "reservation number",
            "reservation id", "confirmation number", "confirmation code", "confirmation", "pnr", "reference", "ref."],
            key: "bookingReference", fields: &fields)
        return fields
    }

    private func enrichAirport(_ airport: AirportInfo, prefix: String, fields: inout [String: ExtractedBookingField]) {
        fields["\(prefix)Name"] = .init(value: airport.name, confidence: 1)
        fields["\(prefix)City"] = .init(value: airport.city, confidence: 1)
        fields["\(prefix)Address"] = .init(value: airport.address, confidence: 1)
        fields["\(prefix)Latitude"] = .init(value: String(airport.latitude), confidence: 1)
        fields["\(prefix)Longitude"] = .init(value: String(airport.longitude), confidence: 1)
    }

    private func extractDates(_ text: String, trip: Trip, keys: [String], fields: inout [String: ExtractedBookingField]) {
        let candidates = regexMatches(#"(?i)\b(?:Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)?\s*\d{1,2}(?:[./-]\d{1,2}(?:[./-]\d{2,4})?|\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)(?:\s+\d{4})?)\b|\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+\d{4}\b"#, in: text)
        for (key, value) in zip(keys, candidates) {
            if let date = BookingDateInterpreter().date(from: value, trip: trip) {
                fields[key] = .init(value: Self.iso8601.string(from: date), confidence: 0.9)
            }
        }
    }

    private func extractTimes(_ text: String, keys: [String], fields: inout [String: ExtractedBookingField]) {
        let times = regexMatches(#"(?i)\b(?:[01]?\d|2[0-3])[:.]\d{2}(?:\s*[AP]M)?\b"#, in: text)
        for (key, value) in zip(keys, times) where fields[key] == nil {
            fields[key] = .init(value: value.replacingOccurrences(of: ".", with: ":").uppercased(), confidence: 0.9)
        }
    }

    private func inferUnlabeledName(_ text: String, excluding terms: [String], key: String, fields: inout [String: ExtractedBookingField]) {
        guard fields[key] == nil else { return }
        if let line = text.components(separatedBy: .newlines).first(where: { line in
            let lower = line.lowercased()
            return line.count > 2 && terms.allSatisfy { !lower.contains($0) } && !line.contains(":")
        }) { fields[key] = .init(value: line, confidence: 0.62) }
    }

    private func addDate(_ date: Date?, as key: String, trip: Trip, to fields: inout [String: ExtractedBookingField]) {
        if let date { fields[key] = .init(value: Self.iso8601.string(from: date), confidence: 0.85) }
    }

    private func addTime(_ date: Date?, as key: String, trip: Trip, to fields: inout [String: ExtractedBookingField]) {
        if let date { fields[key] = .init(value: AppFormatters.time(in: trip.timeZone).string(from: date), confidence: 0.85) }
    }

    private func score(_ terms: [String], in text: String) -> Int { terms.filter(text.contains).count }

    private func regex(_ pattern: String, in text: String) -> String? { regexMatches(pattern, in: text).first }

    private func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static let iso8601 = ISO8601DateFormatter()
}

struct BookingDateInterpreter: Sendable {
    func date(from source: String, trip: Trip) -> Date? {
        var value = source.replacingOccurrences(of: #"(?i)^(Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)\s+"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: ".", with: "-")
        let hasYear = value.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil
        let tripYear = TripCalendar.calendar(in: trip.timeZone).component(.year, from: trip.startDate)
        if !hasYear { value += " \(tripYear)" }
        for format in ["d-M-yyyy", "d/M/yyyy", "d MMM yyyy", "d MMMM yyyy", "MMM d, yyyy", "MMMM d, yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = trip.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: value), trip.contains(date) { return date }
        }
        return nil
    }
}
