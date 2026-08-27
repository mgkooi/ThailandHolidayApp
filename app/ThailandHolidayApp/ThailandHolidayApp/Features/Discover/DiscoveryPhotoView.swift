import Foundation
import SwiftUI
import UIKit

protocol DiscoveryPhotoLoading: Sendable {
    func data(for photo: DiscoveryPhotoMetadata, maxWidth: Int, maxHeight: Int) async throws -> Data
}

/// Fetches Google photo media on demand. The ephemeral session has no URL cache and
/// the returned bytes live only in the requesting view's state.
final class GooglePlacesPhotoLoader: DiscoveryPhotoLoading, @unchecked Sendable {
    static let shared = GooglePlacesPhotoLoader()

    private let apiKey: String?
    private let session: URLSession

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
    }

    func data(for photo: DiscoveryPhotoMetadata, maxWidth: Int, maxHeight: Int) async throws -> Data {
        guard let apiKey else { throw MediaSearchError.notConfigured }
        guard photo.resourceName.hasPrefix("places/"),
              var components = URLComponents(string: "https://places.googleapis.com/v1/\(photo.resourceName)/media")
        else { throw MediaSearchError.invalidResponse }
        components.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: String(min(max(maxWidth, 1), 4_800))),
            URLQueryItem(name: "maxHeightPx", value: String(min(max(maxHeight, 1), 4_800)))
        ]
        guard let url = components.url else { throw MediaSearchError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode), !data.isEmpty else {
            throw MediaSearchError.invalidResponse
        }
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
            guard !Task.isCancelled, let decoded = UIImage(data: data) else { return }
            image = decoded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
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
