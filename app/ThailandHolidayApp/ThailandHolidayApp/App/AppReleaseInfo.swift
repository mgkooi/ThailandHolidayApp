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
            ?? "Reizz"
        version = (infoDictionary["CFBundleShortVersionString"] as? String) ?? "Onbekend"
        buildNumber = (infoDictionary["CFBundleVersion"] as? String) ?? "Onbekend"
    }
}

struct AppReleaseInfo: Equatable {
    let releaseName: String
    let releaseNotes: [String]

    static let current = AppReleaseInfo(
        releaseName: "Reizz 1.2",
        releaseNotes: [
            "Uurverwachting toegevoegd aan Vandaag",
            "WeatherKit-diagnostiek verwijderd uit gebruikersinterface",
            "Locatieweergave visueel verbeterd",
            "Licht/donker/systeem thema instelbaar",
            "Kleine interfaceverbeteringen"
        ]
    )
}
