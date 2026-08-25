# Thailand Holiday App

Private native iPhone travel application for Thailand.

## Purpose

The application provides a single overview of:

- Travel itinerary
- Hotels
- Flights
- Transfers
- Activities
- Restaurants
- Current location
- Maps and navigation
- Booking links
- Favorites

Essential travel information should remain available offline.

## Technology

- Swift
- SwiftUI
- SwiftData
- MapKit
- CoreLocation

## Development

Coding agent: Ubuntu VM

Build environment: MacBook M4 / Xcode

iOS builds must be executed on macOS.

## Project structure

```text
app/ThailandHolidayApp/
├── ThailandHolidayApp.xcodeproj/
├── ThailandHolidayApp/
│   ├── App/                 # Application entry point and root navigation
│   ├── Features/            # Feature-specific SwiftUI screens
│   │   ├── Discover/
│   │   ├── Map/
│   │   ├── More/
│   │   ├── Today/
│   │   └── Trip/
│   └── Assets.xcassets/
├── ThailandHolidayAppTests/
└── ThailandHolidayAppUITests/
scripts/
├── build.sh
└── test.sh
```

Add shared domain models, services, repositories, resources, and utilities as
those responsibilities are introduced. Keep feature-specific UI and logic in
the corresponding folder under `Features`.

## Build and test

The scripts run Xcode on `thailand-mac` through the SSH configuration in
`~/.ssh/config`. The project is built against the latest installed iOS runtime
using the iPhone 17 Pro simulator.

From the repository root, run:

```bash
./scripts/build.sh
./scripts/test.sh
```
