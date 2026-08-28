# Reizz

## Project Goal
Build a private native iPhone application for a Thailand holiday.

The app provides:
- Complete travel itinerary
- Hotels, flights and transfers
- Daily travel overview
- Restaurants and activities near the current location
- Filtering by distance, rating and number of reviews
- Maps and navigation
- Booking and travel links
- Favorites
- Offline access to essential travel information
- Weather information
- Option to add or change travel information

## Platform

Target:
- iPhone
- Native iOS application

Technology:
- Swift
- SwiftUI
- SwiftData
- MapKit
- CoreLocation

## Development Environment

The coding agent runs on Ubuntu.

The iOS build environment runs on macOS.

Mac build host:

    thailand-mac

The agent can access the Mac using:

    ssh thailand-mac

Xcode builds and iOS Simulator operations must run on the Mac.

Do not attempt to build the iOS application directly on Ubuntu.

## Architecture

Use a clean feature-based architecture.

Prefer the following structure:

    App/
    Features/
    Models/
    Services/
    Repositories/
    Resources/
    Utilities/

Keep UI, business logic and data access separated.

## Development Rules

- Prefer native Apple frameworks.
- Do not add third-party dependencies without approval.
- Use SwiftUI for UI.
- Use SwiftData for local persistence unless there is a technical reason not to.
- Essential travel information must work offline.
- Never commit API keys, passwords or secrets.
- Store secrets outside Git.
- Handle missing internet connections gracefully.
- Request location permission only when required.
- Keep the UI optimized for iPhone.

## External Data

Possible external services include:

- Apple MapKit
- Google Places
- Foursquare

Do not select or implement a paid external API without approval.

Restaurant and activity data should support where possible:

- Distance from current location
- Rating
- Number of reviews
- Category
- Opening hours
- Navigation
- Website

## Build

Builds must run on the Mac.

Use:

    ./scripts/build.sh

If the script is unavailable, use SSH:

    ssh thailand-mac

and run xcodebuild from the project directory.

## Testing

Run automated tests after significant changes.

Use:

    ./scripts/test.sh

Business logic should have unit tests.

Important examples include:

- Distance filtering
- Rating filtering
- Review-count filtering
- Date calculations
- Trip-day selection
- Offline data loading

## Agent Workflow

For each feature:

1. Read the relevant documentation.
2. Inspect existing code before modifying it.
3. Make the smallest reasonable implementation.
4. Add or update tests.
5. Build the application.
6. Run tests.
7. Fix build or test failures.
8. Summarize the changes.
9. Do not commit changes unless requested.

## Documentation

Project documentation lives in:

    docs/

Important architectural or data-model changes must also update the documentation.

## Safety

Never:
- Delete project data without approval.
- Change signing configuration without approval.
- Store credentials in the repository.
- Install system-wide software without approval.
- Introduce paid APIs or services without approval.
