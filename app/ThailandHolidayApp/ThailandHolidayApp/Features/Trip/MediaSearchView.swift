import SwiftUI

struct SelectedMediaSearchImage {
    let data: Data
    let metadata: TripMedia
}

struct MediaSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let initialQuery: String
    let service: any MediaSearchService
    let selection: (SelectedMediaSearchImage) -> Void
    @State private var query: String
    @State private var results: [MediaSearchResult] = []
    @State private var selected: MediaSearchResult?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(initialQuery: String, service: any MediaSearchService = UnsplashMediaSearchService(),
         selection: @escaping (SelectedMediaSearchImage) -> Void) {
        self.initialQuery = initialQuery; self.service = service; self.selection = selection
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        TextField("Andere zoekopdracht", text: $query).textFieldStyle(.roundedBorder)
                        Button("Zoek") { Task { await search() } }.disabled(query.nilIfBlank == nil)
                    }
                    if isLoading { ProgressView("Afbeeldingen zoeken…") }
                    if let errorMessage { ContentUnavailableView("Geen resultaten", systemImage: "photo.badge.exclamationmark", description: Text(errorMessage)) }
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                        ForEach(results) { result in
                            Button { selected = result } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    AsyncImage(url: result.thumbnailURL) { image in image.resizable().scaledToFill() }
                                        placeholder: { Rectangle().fill(.quaternary).overlay { ProgressView() } }
                                        .frame(height: 120).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(result.attribution ?? result.sourceName).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding()
            }
            .navigationTitle("Kies afbeelding")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } } }
            .task { await search() }
            .sheet(item: $selected) { result in preview(result) }
        }
    }

    private func preview(_ result: MediaSearchResult) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                AsyncImage(url: result.imageURL) { image in image.resizable().scaledToFit() }
                    placeholder: { ProgressView() }
                Text(result.attribution ?? result.sourceName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Gebruik afbeelding") { Task { await use(result) } }.buttonStyle(.borderedProminent)
            }.padding().navigationTitle("Voorvertoning")
        }
    }

    @MainActor private func search() async {
        isLoading = true; errorMessage = nil; defer { isLoading = false }
        do { results = try await service.searchImages(query: query, limit: 16) }
        catch { results = []; errorMessage = error.localizedDescription }
    }

    @MainActor private func use(_ result: MediaSearchResult) async {
        do {
            let data = try await MediaDownloader().download(result.imageURL)
            selection(.init(data: data, metadata: TripMedia(remoteURL: result.imageURL,
                sourceURL: result.sourceURL, sourceName: result.sourceName,
                attribution: result.attribution, isCover: true)))
            selected = nil; dismiss()
        } catch { errorMessage = error.localizedDescription; selected = nil }
    }
}
