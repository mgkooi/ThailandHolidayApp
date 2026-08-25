# Editorial discovery

Editorial recommendations enrich MapKit place candidates; they never create itinerary places by themselves.
Matching requires a normalized place name and locality, optionally checks coordinates, and checks category when
the provider supplies it. Only lightweight signals (source, URL, confidence and scenic classification) are retained.

Production currently uses `DisabledEditorialRecommendationProvider`. TripAdvisor, Tips Thailand, Reisjunk and
Lonely Planet are represented by `EditorialSource` and can be connected through
`EditorialRecommendationProviding`, `CompositeEditorialRecommendationProvider`, and the expiring per-source,
location and category cache. No HTML scraping, article content, reviews, photographs, ratings, or paid guide
content is copied. Until a legitimate API or maintained curated dataset is configured, all four integrations are
architecture-only and MapKit discovery remains fully functional when editorial enrichment is unavailable.
