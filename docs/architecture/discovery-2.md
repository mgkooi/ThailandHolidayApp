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
website. Logs contain provider, query category, count and cache hit/miss; never keys or
precise coordinates.

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

Google results are transient. Favorites persist identity, coordinates, category and
small rating/review snapshots; trip items persist user-visible itinerary fields and
Place ID. Google Place Photos are not requested, copied into attachments, used as
covers or exported. Cover selection after add-to-day uses the existing local and
exportable media workflow.

Duplicate detection prefers Place ID on the selected date and falls back to normalized
name plus coordinates. Successful addition immediately mutates `TripStore`, so Reis,
Vandaag and Kaart derive the new item without reloading.
