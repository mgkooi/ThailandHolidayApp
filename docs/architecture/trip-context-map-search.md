# Trip context and map selection

The app-wide active trip remains `TripStore.selectedTripId`. Main tabs expose it through a native
principal toolbar menu (`TripContextToolbar`); there is no app-level overlay or safe-area inset.

Creation editors own a transient `targetTripID`, initialized from `selectedTripId`. Saving calls
`TripStore.saveManagedItem(..., targetTripID:)`, which mutates the matching nested Trip without
changing the active trip. Existing edits omit this selector and remain in their current trip.

`MapPlace` is the transient common representation for MapKit search results and editor location
prefill. `MapSearchProviding` isolates `MKLocalSearch` from SwiftUI and permits deterministic UI
tests. Search is biased to the visible map region but the query itself remains unrestricted.

Kaart has two modes:

- Browse mode shows selected-trip annotations plus transient search results and offers Discover,
  Navigate and Add to trip.
- Picker mode returns a selected `MapPlace` to an existing editor without persisting it.

Accommodation, Restaurant and Activity receive structured names, place/address and internal
coordinates. Route models ask whether the place is the origin/pickup or destination/arrival.
Duplicate detection compares normalized names/addresses and coordinates within 75 metres, and
always lets the user inspect the existing item or explicitly add anyway.
