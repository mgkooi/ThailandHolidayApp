import Foundation

struct AppBundleInfo: Equatable {
    let appName: String
    let version: String
    let buildNumber: String

    static var current: AppBundleInfo {
        AppBundleInfo(bundle: .main)
    }

    init(bundle: Bundle) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        appName = (infoDictionary["CFBundleDisplayName"] as? String)
            ?? (infoDictionary["CFBundleName"] as? String)
            ?? "ThailandHolidayApp"
        version = (infoDictionary["CFBundleShortVersionString"] as? String) ?? "Onbekend"
        buildNumber = (infoDictionary["CFBundleVersion"] as? String) ?? "Onbekend"
    }
}

struct AppReleaseInfo: Equatable {
    let releaseName: String
    let releaseNotes: [String]

    static let current = AppReleaseInfo(
        releaseName: "Ontdekken 2.1",
        releaseNotes: [
            "Echte previewfoto's bij Ontdekken-resultaten",
            "Visueel verbeterde discovery cards",
            "Previewfoto's in discovery details",
            "Previewfoto's bij kaartresultaten waar beschikbaar",
            "Native fallback wanneer geen foto beschikbaar is",
            "Diverse stabiliteits- en interfaceverbeteringen"
        ]
    )
}
