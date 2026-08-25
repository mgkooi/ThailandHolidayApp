# Multi-trip persistence

The app has one shared `TripStore`. Its persisted root is `TravelLibrary`:

- `schemaVersion` is currently `2`.
- `trips` contains self-contained `Trip` values and their nested itinerary items.
- `selectedTripId` identifies the trip exposed to existing features through `TripStore.trip`.
- `nearbySuggestions` and `favorites` preserve existing package data.

The live file is `Documents/travel-library.json`. On first launch, if that file is absent and
`Documents/thailand-trip.json` exists, the old `TripDataPackage` is decoded and wrapped in a
one-trip library. The new file is written atomically and decoded again for verification. The
legacy file is retained as a migration backup.

All feature mutations retain the copy → mutate → assign-back pattern. The compatibility property
`TripStore.trip` reads and replaces only the selected trip, so Today, Trip, Map, OCR saves and
activity additions remain isolated by trip without introducing a second store.

## Activity discovery

MapKit results are transient and never persisted. `ActivityDiscoveryProviding` allows a future
richer places provider. The current MapKit provider supplies real name, address, coordinate,
distance, phone and website fields. Rating, review count and price remain `nil` because MapKit
does not reliably expose them. Filters requiring missing metadata exclude those results rather
than inventing values. Star Worthy is derived only when a real rating of at least 4.5 and at least
100 real reviews are available.
