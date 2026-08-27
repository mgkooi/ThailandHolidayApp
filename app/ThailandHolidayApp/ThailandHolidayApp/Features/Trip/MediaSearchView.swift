import SwiftUI

struct SelectedMediaSearchImage {
    let data: Data
    let metadata: TripMedia
}

struct MediaSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let initialQuery: String
    let service: any MediaSearchService
    let placeResolver: any GooglePlacesResolving
    let subject: MediaSearchSubject
    let initialGooglePlaceID: String?
    let selection: (SelectedMediaSearchImage) -> Void
    @State private var query: String
    @State private var results: [MediaSearchResult] = []
    @State private var selected: MediaSearchResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var placeCandidates: [GooglePlaceCandidate] = []
    @State private var selectedGooglePlaceID: String?

    init(initialQuery: String, subject: MediaSearchSubject = .generic, googlePlaceID: String? = nil,
         service: any MediaSearchService = PreferredMediaSearchService(),
         placeResolver: any GooglePlacesResolving = GooglePlacesEntityResolver(),
         selection: @escaping (SelectedMediaSearchImage) -> Void) {
        self.initialQuery = initialQuery; self.subject = subject; initialGooglePlaceID = googlePlaceID
        self.service = service; self.placeResolver = placeResolver; self.selection = selection
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
                    if !placeCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kies de juiste locatie").font(.headline)
                            ForEach(placeCandidates) { candidate in
                                Button { Task { await choose(candidate) } } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(candidate.displayName).font(.body.weight(.semibold))
                                        if let address = candidate.formattedAddress { Text(address).font(.caption).foregroundStyle(.secondary) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
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
            .navigationTitle("Kies omslag")
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
        placeCandidates = []
        do {
            if subject == .place, placeResolver.isConfigured {
                let existingID = query == initialQuery ? initialGooglePlaceID : nil
                let candidates = try await placeResolver.resolve(query: query, existingPlaceID: existingID)
                if candidates.count == 1 { await choose(candidates[0]) }
                else { results = []; placeCandidates = candidates }
            } else { results = try await service.searchImages(request: .init(query: query, limit: 16, subject: subject)) }
        } catch {
            do { results = try await service.searchImages(request: .init(query: query, limit: 16, subject: subject)) }
            catch { results = []; errorMessage = error.localizedDescription }
        }
    }

    @MainActor private func choose(_ candidate: GooglePlaceCandidate) async {
        isLoading = true; errorMessage = nil; placeCandidates = []
        selectedGooglePlaceID = candidate.id
        do { results = try await service.searchImages(request: .init(query: candidate.imageQuery, limit: 16, subject: .place,
                                                                      googlePlaceID: candidate.id)) }
        catch { results = []; errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func use(_ result: MediaSearchResult) async {
        do {
            let data = try await MediaDownloader().download(result.imageURL)
            selection(.init(data: data, metadata: TripMedia(remoteURL: result.imageURL,
                sourceURL: result.sourceURL, sourceName: result.sourceName,
                attribution: result.attribution, googlePlaceID: selectedGooglePlaceID)))
            selected = nil; dismiss()
        } catch { errorMessage = error.localizedDescription; selected = nil }
    }
}
