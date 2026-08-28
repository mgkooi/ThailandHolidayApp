import SwiftUI

struct MoreView: View {
    @State private var showsTrips = false
    private let bundleInfo = AppBundleInfo.current
    private let releaseInfo = AppReleaseInfo.current

    var body: some View {
        NavigationStack {
            List {
                Button { showsTrips = true } label: { Label("Mijn reizen", systemImage: "suitcase.rolling") }

                Section("Over deze app") {
                    NavigationLink {
                        WhatsNewView(releaseInfo: releaseInfo)
                    } label: {
                        Label("Wat is nieuw", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("whatsNewRow")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(bundleInfo.appName)
                            .font(.subheadline.weight(.medium))
                        Text("Versie \(bundleInfo.version) · Build \(bundleInfo.buildNumber)")
                        Text(releaseInfo.releaseName)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("appVersionInfo")
                }
            }
                .navigationTitle("Meer")
                .toolbar { TripContextToolbar() }
                .sheet(isPresented: $showsTrips) { MyTripsView() }
        }
    }
}

struct WhatsNewView: View {
    let releaseInfo: AppReleaseInfo

    var body: some View {
        List {
            Section {
                ForEach(releaseInfo.releaseNotes, id: \.self) { note in
                    Label {
                        Text(note)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.travelTeal)
                    }
                }
            } header: {
                Text(releaseInfo.releaseName)
            }
        }
        .navigationTitle("Wat is nieuw")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("whatsNewView")
    }
}

#Preview {
    MoreView()
}
