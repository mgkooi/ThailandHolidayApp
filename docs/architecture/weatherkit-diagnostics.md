# WeatherKit diagnostics

`TripWeatherService` uses the native WeatherKit provider in Debug and Release. It classifies failures as
`notConfigured`, `entitlementMissing`, `authorizationFailed`, `locationUnavailable`, `dateOutOfRange`,
`noForecastData`, `network`, `weatherKitServiceError`, or `unknown`.

Weather logs contain the provider, location source, coordinates rounded to two decimals, forecast date,
request result, category, and safe error domain/code. Exact coordinates and error descriptions are not logged.

The daily forecast horizon is treated as ten days including today. A date outside today through day +9 is
reported as “Nog geen weersverwachting beschikbaar voor deze datum” and does not issue a WeatherKit request.
An in-range request with no matching data is classified as `noForecastData`.

`WeatherDiagnosticsEnabled` in the app Info.plist temporarily enables a subtle `Diagnose: <category>` line in
distribution builds. Remove or disable this flag after TestFlight validation; Debug builds always show it.

## Release verification

The repository establishes that:

- `com.apple.developer.weatherkit` is `true` in `ThailandHolidayApp.entitlements`;
- both app configurations use that entitlement file;
- both app configurations define `WEATHERKIT_ENABLED`, so Release constructs `AppleTripWeatherProvider`.

For every distributed archive, verify the signed product with:

```sh
codesign -d --entitlements :- ThailandHolidayApp.xcarchive/Products/Applications/ThailandHolidayApp.app
security cms -D -i ThailandHolidayApp.xcarchive/Products/Applications/ThailandHolidayApp.app/embedded.mobileprovision
```

Both outputs must contain `com.apple.developer.weatherkit = true`. Xcode Cloud must use the same app target and
bundle identifier. In Certificates, Identifiers & Profiles, verify that App ID
`nl.martijnkooi.ThailandHolidayApp` has WeatherKit enabled, then regenerate/refresh the App Store provisioning
profile if the capability was enabled after the profile was created. In App Store Connect/Xcode Cloud, verify
the distribution signing assets were refreshed after that change.
