# Data model

## Overview

`Trip` is the aggregate root for booked, offline travel data. It owns destinations,
accommodations, transport, trip days, and general booking links. `TripDay` uses UUID
references to a destination and optional accommodation rather than duplicating those
objects. Its itinerary items are owned by that day.

```text
Trip
├── Destination[]
├── Accommodation[] ── destinationID? ──> Destination
├── Flight[]
├── Transfer[]
├── Ferry[]
├── TrainTrip[]
├── RestaurantReservation[]
├── RentalVehicleBooking[]
├── Activity[] ── destinationID? ──> Destination
├── TripEvent[]
├── TransportItem[]
├── TripDay[]
│   ├── destinationID ────────────────> Destination
│   ├── accommodationID? ─────────────> Accommodation
│   └── ItineraryItem[]
└── BookingLink[]
```

`NearbySuggestion` and `Favorite` live beside the trip in `TripDataPackage`.
Suggestions are transient external/search results and are not booked itinerary data.
A favorite stores normalized name, category, coordinates, and links so it remains
useful offline even if its original suggestion or external provider disappears.

## Persistence and ownership

The complete initial package is bundled at
`Resources/Data/thailand-trip.json`. On first launch it is copied to
`Documents/thailand-trip.json`; later launches always use that writable copy.
`LocalTripRepository` owns file access and JSON decoding, while `TripStore` owns
mutations and atomic saves. SwiftUI never decodes files. Dates use Swift `Date` at
runtime and the JSON encoder/decoder uses ISO-8601.

Persisted `Trip.startDate` and `Trip.endDate` are metadata, not editor constraints.
`effectiveStartDate` and `effectiveEndDate` expand that range using all itinerary
start/end/check-out/drop-off dates. Reis groups every item chronologically in the
trip timezone, including items outside the persisted metadata range, and Vandaag can
navigate without date boundaries.

Editors submit value drafts through `TripStore` mutation methods. Each method updates
a copied `Trip`, assigns that complete value back to the observable store, and then
persists it. `dataRevision` increments after a successful mutation so derived screens
can explicitly observe aggregate changes without reloading JSON.

Phase-two collections (`transfers`, `ferries`, `trains`, `restaurants`, and
`otherItems`) decode to empty arrays when their keys are absent. This allows existing
Documents files to migrate without reinstalling the app. Every item has a stable UUID.
Optional booking images are stored separately in `Documents/Attachments`; JSON stores
only the relative filename.

## Media and portable trip archives

`Flight`, `Accommodation`, and `Activity` optionally own `[TripMedia]`. The optional
storage is intentional for backwards compatibility: older `thailand-trip.json` and
`travel-library.json` files decode it as an empty `mediaItems` collection. A media
record keeps a stable UUID, local relative filename, optional remote/source URLs,
attribution and caption. These arrays are travel documents (screenshots, vouchers,
boarding passes and photos) and are never selected automatically for presentation.
Each supported item has an independent optional `presentationMedia: TripMedia?`. It
uses the same attachment storage but is rendered only as cover/hero image. The shape is generic and can be adopted by
restaurants, viewpoints and other item types without changing the media services.

Chosen remote images and user photos are normalized to JPEG (maximum long edge 2400
pixels) by `AttachmentStore` and live in `Documents/Attachments`. Search thumbnails
remain remote and full-resolution data is fetched only after the user confirms a
result. Views prefer the local cover and fall back to the remote URL or a native
placeholder.

`TripArchiveService` exports a directory-backed package named `<trip name>.triparchive`:

```text
<trip name>.triparchive/
├── trip.json       # schemaVersion, exportedAt, complete Trip aggregate
└── media/          # local attachments, never Base64
```

The archive is exposed to iOS as one `<trip name>.triparchive` package document. Its
UTI conforms to `com.apple.package`, so Share Sheet, Files, and iCloud Drive treat the
directory-backed structure as a single file. Imports are first copied through
security-scoped, coordinated access into app-controlled temporary storage. The importer
also accepts the earlier unregistered directory format and a standalone manifest JSON.

Schema version 2 adds presentation media; version 1 and older JSON without covers remain
accepted. Export/import preserves all aggregate UUIDs. Import first decodes a read-only
preview. Local filenames are collision-safe when copied into the receiving app. A
duplicate Trip UUID can either replace the aggregate or create a copy with a new root
Trip UUID; nested UUIDs and their relationships stay intact.

All managed itinerary types can carry two independent media collections. `media` and
the legacy `attachmentFilename` represent documents such as tickets and vouchers;
`presentationMedia` is the optional visual cover. A cover can explicitly use `photo`
(full-bleed crop) or `logo` (contained) presentation. These new fields are optional so
older trip JSON remains decodable. Archive filename remapping covers both document and
presentation media for flights, stays, transfers, ferries, trains, rental vehicles,
restaurants, activities, and other events.

Image search is isolated behind `MediaSearchService`. `PreferredMediaSearchService`
uses Brave Image Search for targeted web results and falls back to Unsplash when Brave
is unavailable and Unsplash is configured. Keys are supplied through the
`BRAVE_SEARCH_API_KEY` and `UNSPLASH_ACCESS_KEY` Xcode build settings, substituted into
Info.plist; `Config/Secrets.xcconfig.example` documents local setup and the real
`Secrets.xcconfig` is ignored by Git. With no key, offline,
provider failure, or missing images, the UI remains functional and shows a controlled
fallback.

For physical items, `GooglePlacesEntityResolver` first resolves the exact name, city,
and country with Places API (New). A persisted `googlePlaceID` skips Text Search and
goes directly to Place Details. Ambiguous searches return up to five candidates for an
explicit user choice. Only the resolved display name, formatted address, coordinates,
and cacheable Place ID enrich the item/search query. Google Place Photos are not stored
or exported; the actual offline cover still comes from Brave, Unsplash, or the user.
`GOOGLE_PLACES_API_KEY` is injected through the same external build configuration.

Rented transport is normalized as `RentalVehicleBooking` in `rentalVehicles`, with a
`RentalVehicleType` for car, scooter, motorcycle, bicycle, e-bike, quad, or other.
Pickup and drop-off are two derived timeline events that retain the same booking UUID.
The decoder accepts the development-era `rentalCars` key and migrates legacy
`TransportItem.rentalVehicle` or “Auto ophalen” events without requiring reinstall.

Booked data is expected to be durable and available offline. Nearby results may be
refreshed from a provider. Favorites are user-owned durable data and should eventually
be persisted separately from the read-only bundled seed.

## Timezone strategy

Each trip declares an IANA timezone identifier. Thailand data uses `Asia/Bangkok`.
`TripCalendar` creates Gregorian calendars with that explicit timezone, and
`TripResolver` uses it for trip-day matching. Date resolution never uses the device's
current timezone. JSON timestamps include an explicit offset and are decoded as
absolute instants.

An accommodation is active on `checkInDate <= selectedDay < checkOutDate`: it appears
on check-in day and each stay night, but not as the current stay on checkout day.

## Repository and resolution

`TripRepository` exposes the current trip and common queries. `LocalTripRepository`
loads the bundle and delegates date-sensitive operations to `TripResolver`, which
resolves today's day, destination, accommodation, and next transport outside the UI.
`TodayDashboardData` and `TimelineItem` are resolved presentation projections, not
persisted models. `TripTimelineBuilder` combines each domain collection for display,
while `TimelineSource` retains the item kind and stable source UUID for editing.

## External API boundary

Core models contain only normalized Swift values. `NearbySuggestion.externalProvider`
and `externalID` retain provider identity without importing Google Places, Foursquare,
or another SDK type. A future API adapter should translate provider responses into
`NearbySuggestion`; provider DTOs must remain in the service/integration layer.

## Future SwiftData mapping

The Codable structs deliberately use stable UUID relationships, which can map to
SwiftData entities without changing feature APIs. A future persistence layer can:

- create `@Model` records for the `Trip` aggregate and user-owned favorites;
- map UUID references to SwiftData relationships during import;
- keep transport-specific optional fields on one transport entity;
- import the bundled JSON once as seed data;
- expose value-model snapshots from the repository so views remain persistence-agnostic.

SwiftData annotations are intentionally not added yet. The repository and `TripStore`
boundary allows the current editable JSON persistence to be replaced incrementally
without changing the feature views.

## Booking extraction boundary

Booking recognition keeps `RecognizedBookingText.originalText` beside normalized text.
`BookingTextNormalizer` only applies context-safe OCR cleanup before the offline
`DeterministicBookingExtractor`. The `BookingExtracting` protocol permits a future
optional smarter implementation without making cloud access or API secrets mandatory.
`BookingExtractionResult` contains transient type/field confidences and Dutch review
warnings; these are never written to the trip JSON. Airport enrichment is normalized
through `AirportLookup`, preserving both IATA code and friendly airport name.

Vision OCR is invoked lazily from Reis and remains on-device. Its recognized text is
normalized, classified, parsed, validated and enriched into a transient
`BookingExtractionResult`. Low-confidence results require an explicit type choice.
Every result opens the regular `TripItemEditorView`; neither OCR nor extraction writes
to `TripStore`. The selected image becomes an attachment draft only and is committed
by the existing atomic save path. Logs contain status and field counts only, never OCR
text, passenger details or booking references.

## Address geocoding and navigation

`TripLocation` is the lightweight location value (`placeName`, `address`, optional
coordinates). It is introduced incrementally: Accommodation keeps its existing JSON
address/coordinate keys and adds optional `placeName`, exposing those values as a
computed `TripLocation`. This preserves existing Documents JSON and coordinates.
Destination remains optional organizational metadata; date-based visibility never
depends on a destination relationship.

Accommodation and restaurant addresses remain durable model fields. Accommodation
geocoding prefers `address, placeName`, then place name alone when no address exists.
Optional coordinates are resolved at save time through the native `LocationGeocoding`
service; the editors never request the device's current location. Unchanged queries
retain existing coordinates, and an unresolved changed query is still saved with nil
coordinates. Forward-geocoding failure never blocks an offline itinerary edit.

Apple Maps navigation is isolated in `AppleMapsNavigator`. `MapLocationResolver`
selects coordinates first, then address, then place name; only usable locations show
the navigation action. Address/place fallbacks are geocoded with MapKit before opening
an `MKMapItem`, so tests verify resolution without launching Maps.

## Flight arrival dates

`Flight.date` remains the departure/timeline day and `departureTime` remains the full
departure instant. `arrivalDate` is persisted separately so the editor can combine an
independent arrival day with `arrivalTime`. Legacy JSON without `arrivalDate` decodes
it from `date` while preserving the existing arrival-time value. Timeline grouping
always uses departure, while displayed duration/end information uses the combined
arrival date and time.

## Local discovery

`SearchLocation` is transient coordinate context shared by Vandaag and Ontdekken; it
is never persisted in the trip JSON. `TripSearchLocationResolver` selects active
accommodation coordinates (or geocoded accommodation text), Destination coordinates,
then a dated Activity location. It never requests device GPS permission.

`LocalDiscoverySearching` isolates local-search providers from SwiftUI. The MapKit
implementation searches a bounded region, maps `MKMapItem` values into app-owned
`DiscoveryResult` values, calculates straight-line distance, sorts nearest first and
caches coordinate-bucket/category requests. `DiscoverySession` owns only transient UI
state for restaurant, ATM, 7-Eleven and activity searches, including manually
geocoded place queries.

## Daily date and map context

Vandaag initializes from an injected/current `Date` and never clamps it to trip
metadata. Previous/next navigation uses the trip calendar, while a graphical picker
can select any date. The active accommodation (`checkIn <= day < checkOut`) supplies
the friendly daily location before Destination/activity fallbacks. Tapping it writes
only transient `AppNavigationState.mapFocus` and selects the Kaart tab.

`TripMapAnnotationBuilder` derives map pins directly from TripStore models. It includes
coordinate-bearing accommodations, structured flight airports, booked restaurants
and activities, and can be extended for route locations as those models gain
coordinates. `TripMapRegionBuilder` creates an approximately 10 km radius focus using
meter-based MapKit regions. Pins retain type, source ID, date and `TripLocation` for
selected-day emphasis, detail cards and Apple Maps navigation.

## Structured airports and booking references

`AirportLookup` owns extensible `AirportInfo` records containing IATA code, name, city,
country, address and coordinates. Exact code or unique text matches can preselect an
airport; ambiguous city matches such as Bangkok remain explicit suggestions. Flight
keeps legacy origin/destination text and adds optional structured departure/arrival
airport values, so old Documents JSON remains decodable and unknown text is preserved.

Optional booking references are persisted on Flight and existing relevant booking
models; Train and Activity gained optional fields. OCR recognizes common booking,
reservation, confirmation, PNR and reference labels. Recognized IATA codes are
enriched through AirportLookup before the normal review editor, while accommodation
place/address data continues through the existing save-time geocoder.

OCR classification remains a suggestion. `BookingReclassificationService` re-runs the
deterministic extractor against the original recognized text whenever the user changes
`Type boeking`; this creates fresh target-type fields while common URL/date/reference
values are re-extracted normally. The existing editor remains the only save path.

`AppFeedbackState` is transient app UI state. Editors report success only after the
TripStore mutation and atomic JSON persistence return true; failed saves never publish
a confirmation and no feedback value is persisted.

Vandaag passes its already resolved accommodation-first `SearchLocation`, restaurant
category and optional tapped result ID through `AppNavigationState`. Ontdekken reuses
that context and may highlight the selected result. Discovery Maps actions are split
behind `MapOpening`: `openPlace` opens an Apple Maps place card, while `navigate`
supplies driving-directions launch options. Discovery results remain transient.
