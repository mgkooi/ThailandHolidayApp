# Discovery 2.0 architecture

## Flow

`DiscoverView` renders inspiration feeds, concrete categories, filters and list/map
modes. It depends on `DiscoverySession`, not a concrete network client. Context order
is authorized on-trip GPS, today's trip location/accommodation, the first selected-trip
destination, then a manually geocoded location.

`PreferredDiscoveryService` calls `GooglePlacesDiscoveryProvider` first and falls back
to MapKit when Google is unavailable or unconfigured. Requests are cancelled logically
through generation checks, cached for 15 minutes by coarse coordinate/category/radius,
and limited to 20 results. The Google field mask requests only ID, display name,
address, coordinates, primary type/types, rating, review count, price, open-now and
website, plus the first suitable photo's transient resource metadata. Logs contain
provider, query category, count and cache hit/miss; never keys or precise coordinates.

## Discovery photo previews

Text Search (New) requests the minimum photo metadata in the existing field mask:
resource name, dimensions, author attributions and the individual Google Maps source
URL. No Place Details request is needed. `DiscoveryPhotoView` requests the official
`places/{placeId}/photos/{photo}/media` endpoint only when a card, detail hero or map
preview becomes visible. List images request at most 720×405 pixels; detail images at
most 1440×960 pixels.

`GooglePlacesPhotoLoader` uses an ephemeral `URLSession`, disables `URLCache`, sends
the API key in the request header and retains bytes only in the requesting SwiftUI
view. Cancellation follows SwiftUI task lifetime. Photo resource names and bytes are
not written to Documents or Application Support, are not prefetched, and are not
exported. If loading fails or metadata is absent, the existing native category artwork
is shown.

`DiscoveryPhotoAttribution` owns the author and Google Maps source presentation. Cards
show compact attribution and open a detail view containing author profile links and
the individual Google Maps photo link. This keeps compliance behavior out of the
general discovery card implementation.

## Ranking and feeds

`RecommendationScorer.Weights.standard` configures rating 24, logarithmic review
evidence 10, distance 16, category relevance 8, verified editorial signals 12 and
availability 5. Review evidence uses capped `log10`, preventing a 5.0/4-review place
from automatically beating a 4.7/4,000-review place. Closed places receive a penalty.

Hidden gems require rating >= 4.5, 50...1,500 reviews and distance <= 15 km. Star
Worthy remains conservative and evidence-based. “Voor jou” combines categories and
`DiscoveryDiversifier` prevents more than two consecutive results of one category.

## Editorial sources

`EditorialSourceService` is the extension protocol. Matching requires normalized exact
name/city, compatible category, optional coordinate proximity and confidence >= 0.7.
No TripAdvisor, Lonely Planet, Reisjunk, Tips Thailand or other site is scraped. No
external editorial provider is active because no approved official API/feed was
selected. Brave remains active for image search only, not as an editorial fact source.

## Persistence and compliance

Google results and photo previews are transient. Favorites persist identity,
coordinates, category and small rating/review snapshots; trip items persist
user-visible itinerary fields and Place ID. Google Place Photos are never copied into
attachments, used as covers or exported. Cover selection after add-to-day uses the
existing local and exportable media workflow.

Duplicate detection prefers Place ID on the selected date and falls back to normalized
name plus coordinates. Successful addition immediately mutates `TripStore`, so Reis,
Vandaag and Kaart derive the new item without reloading.
