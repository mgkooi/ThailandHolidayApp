import Foundation
import OSLog
import SwiftUI
import UIKit

protocol DiscoveryPhotoLoading: Sendable {
    func data(for photo: DiscoveryPhotoMetadata, maxWidth: Int, maxHeight: Int) async throws -> Data
}

enum DiscoveryPhotoLoadError: Error, Equatable {
    case keyMissing
    case invalidRequest
    case authorization(statusCode: Int)
    case quota(statusCode: Int)
    case http(statusCode: Int)
    case emptyResponse
    case networking

    var category: String {
        switch self {
        case .keyMissing: "key_missing"
        case .invalidRequest: "invalid_request"
        case .authorization: "authorization"
        case .quota: "quota"
        case .http: "http"
        case .emptyResponse: "download"
        case .networking: "networking"
        }
    }
}

/// Fetches Google photo media on demand. The ephemeral session has no URL cache and
/// the returned bytes live only in the requesting view's state.
final class GooglePlacesPhotoLoader: DiscoveryPhotoLoading, @unchecked Sendable {
    static let shared = GooglePlacesPhotoLoader()

    private let apiKey: String?
    private let session: URLSession
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThailandHolidayApp",
                                       category: "DiscoveryPhoto")

    init(configuration: MediaSearchConfiguration = .app, session: URLSession? = nil) {
        apiKey = configuration.googlePlacesAPIKey
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        Self.logger.info("provider=google configured=\(self.apiKey != nil, privacy: .public)")
    }

    func data(for photo: DiscoveryPhotoMetadata, maxWidth: Int, maxHeight: Int) async throws -> Data {
        guard let apiKey else {
            Self.logger.error("provider=google request=not_started configured=false error=key_missing")
            throw DiscoveryPhotoLoadError.keyMissing
        }
        guard photo.resourceName.hasPrefix("places/"),
              var components = URLComponents(string: "https://places.googleapis.com/v1/\(photo.resourceName)/media")
        else {
            Self.logger.error("provider=google request=not_started configured=true error=invalid_request")
            throw DiscoveryPhotoLoadError.invalidRequest
        }
        components.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: String(min(max(maxWidth, 1), 4_800))),
            URLQueryItem(name: "maxHeightPx", value: String(min(max(maxHeight, 1), 4_800)))
        ]
        guard let url = components.url else { throw DiscoveryPhotoLoadError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        Self.logger.info("provider=google request=started configured=true")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("provider=google request=failed configured=true error=networking")
            throw DiscoveryPhotoLoadError.networking
        }
        guard let response = response as? HTTPURLResponse else {
            Self.logger.error("provider=google request=failed configured=true error=invalid_response")
            throw DiscoveryPhotoLoadError.invalidRequest
        }
        Self.logger.info("provider=google request=finished status=\(response.statusCode, privacy: .public)")
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw DiscoveryPhotoLoadError.authorization(statusCode: response.statusCode)
        case 429: throw DiscoveryPhotoLoadError.quota(statusCode: response.statusCode)
        default: throw DiscoveryPhotoLoadError.http(statusCode: response.statusCode)
        }
        guard !data.isEmpty else { throw DiscoveryPhotoLoadError.emptyResponse }
        return data
    }
}

private struct DiscoveryPhotoLoaderKey: EnvironmentKey {
    static let defaultValue: any DiscoveryPhotoLoading = GooglePlacesPhotoLoader.shared
}

extension EnvironmentValues {
    var discoveryPhotoLoader: any DiscoveryPhotoLoading {
        get { self[DiscoveryPhotoLoaderKey.self] }
        set { self[DiscoveryPhotoLoaderKey.self] = newValue }
    }
}

struct DiscoveryPhotoView: View {
    @Environment(\.discoveryPhotoLoader) private var loader
    let photo: DiscoveryPhotoMetadata?
    let category: DiscoveryCategory
    let maxPixelWidth: Int
    let maxPixelHeight: Int
    var accessibilityIdentifier: String

    @State private var image: UIImage?
    @State private var failed = false
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThailandHolidayApp",
                                       category: "DiscoveryPhotoUI")

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if photo != nil && !failed {
                Rectangle().fill(.quaternary)
                    .overlay { ProgressView().controlSize(.small) }
            } else {
                LinearGradient(colors: [Color.travelTeal.opacity(0.85), Color.travelPurple.opacity(0.65)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: category.symbolName)
                    .font(.largeTitle).foregroundStyle(.white.opacity(0.9))
            }
        }
        .clipped()
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(image == nil ? "Geen previewfoto beschikbaar" : "Previewfoto")
        .task(id: photo?.resourceName) { await load() }
    }

    @MainActor
    private func load() async {
        image = nil
        failed = false
        guard let photo else { failed = true; return }
        if UITestConfiguration.isEnabled, photo.resourceName == "ui-test-photo" {
            image = UIImage(systemName: "photo.fill")
            return
        }
        do {
            let data = try await loader.data(for: photo, maxWidth: maxPixelWidth, maxHeight: maxPixelHeight)
            guard !Task.isCancelled else { return }
            guard let decoded = UIImage(data: data) else {
                failed = true
                Self.logger.error("provider=google presentation=fallback error=decoding")
                return
            }
            image = decoded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            let category = (error as? DiscoveryPhotoLoadError)?.category ?? "download"
            Self.logger.error("provider=google presentation=fallback error=\(category, privacy: .public)")
        }
    }
}

struct DiscoveryPhotoAttribution: View {
    let photo: DiscoveryPhotoMetadata
    var compact = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 5) {
                    Text(authorText)
                    googleMapsAttribution
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fotobron").fontWeight(.semibold)
                    if photo.authors.isEmpty {
                        Text("Auteur niet vermeld")
                    } else {
                        ForEach(photo.authors) { author in
                            HStack(spacing: 7) {
                                if let avatarURL = author.profilePhotoURL {
                                    DiscoveryAuthorAvatar(url: avatarURL)
                                }
                                if let url = author.profileURL {
                                    Link(author.displayName, destination: url)
                                } else {
                                    Text(author.displayName)
                                }
                            }
                        }
                    }
                    googleMapsAttribution
                }
            }
        }
        .font(compact ? .caption2 : .caption)
        .foregroundStyle(.secondary)
        .lineLimit(compact ? 1 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discoveryPhotoAttribution")
    }

    @ViewBuilder private var googleMapsAttribution: some View {
        if let source = photo.googleMapsURL {
            Link("Google Maps", destination: source)
                .accessibilityIdentifier("discoveryPhotoSource")
        } else {
            Text("Google Maps")
        }
    }

    private var authorText: String {
        let names = photo.authors.map(\.displayName)
        return names.isEmpty ? "Foto ·" : "Foto: \(names.joined(separator: ",")) ·"
    }
}

private struct DiscoveryAuthorAvatar: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.tertiary)
            }
        }
        .frame(width: 24, height: 24).clipShape(Circle())
        .task(id: url) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await URLSession(configuration: configuration).data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                  !Task.isCancelled else { return }
            image = UIImage(data: data)
        }
        .accessibilityHidden(true)
    }
}
