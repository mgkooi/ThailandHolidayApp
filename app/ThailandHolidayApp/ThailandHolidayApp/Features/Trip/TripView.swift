import SwiftUI

struct TripView: View {
    @Environment(TripStore.self) private var tripStore

    var body: some View {
        NavigationStack {
            Group {
                if tripStore.isLoading && tripStore.trip == nil {
                    ProgressView("Reisplanning laden…")
                } else if let trip = tripStore.trip {
                    timelineContent(trip: trip, sections: tripStore.timelineSections())
                } else if tripStore.errorMessage != nil {
                    ContentUnavailableView(
                        "Reisplanning niet beschikbaar",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Probeer het later opnieuw.")
                    )
                } else {
                    emptyState
                }
            }
            .navigationTitle("Reis")
            .toolbar {
                TripContextToolbar()
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { BookingScannerView() } label: { Image(systemName: "doc.viewfinder") }
                        .accessibilityLabel("Scan boeking")
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        TripItemTypePicker()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nieuw reisitem")
                }
            }
        }
    }

    private func timelineContent(trip: Trip, sections: [TimelineDaySection]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                TripTimelineHeader(trip: trip)

                if sections.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(sections) { section in
                        TimelineDayView(section: section, timeZone: trip.timeZone)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.travelBackground)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nog geen reisplanning beschikbaar",
            systemImage: "calendar",
            description: Text("Je volledige reis verschijnt hier.")
        )
    }
}

private struct TripTimelineHeader: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(trip.name)
                .font(.largeTitle.bold())
            Text(dateRange)
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label("\(dayCount) dagen", systemImage: "calendar")
                Label("\(trip.destinations.count) bestemmingen", systemImage: "mappin.and.ellipse")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.travelTeal)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private var dayCount: Int {
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        return (calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: trip.effectiveStartDate),
            to: calendar.startOfDay(for: trip.effectiveEndDate)
        ).day ?? 0) + 1
    }

    private var dateRange: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.timeZone = trip.timeZone
        formatter.dateFormat = "d MMMM"
        let endFormatter = DateFormatter()
        endFormatter.locale = formatter.locale
        endFormatter.timeZone = trip.timeZone
        endFormatter.dateFormat = "d MMMM yyyy"
        return "\(formatter.string(from: trip.effectiveStartDate)) – \(endFormatter.string(from: trip.effectiveEndDate))"
    }
}

private struct TimelineDayView: View {
    let section: TimelineDaySection
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppFormatters.dutchDate(in: timeZone).string(from: section.day).capitalized)
                .font(.title3.bold())

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    if case let .activity(activityID) = item.source {
                        NavigationLink {
                            ActivityDetailView(activityID: activityID)
                        } label: {
                            TimelineRow(item: item, timeZone: timeZone, isLast: index == section.items.count - 1)
                        }
                        .buttonStyle(.plain)
                    } else if let destination = editorDestination(for: item.source) {
                        NavigationLink {
                            TripItemEditorView(kind: destination.kind, itemID: destination.id)
                        } label: {
                            TimelineRow(item: item, timeZone: timeZone, isLast: index == section.items.count - 1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        TimelineRow(item: item, timeZone: timeZone, isLast: index == section.items.count - 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .travelCardShadow()
        }
    }

    private func editorDestination(for source: TimelineSource) -> (kind: TripItemKind, id: UUID)? {
        switch source {
        case .flight(let id): (.flight, id)
        case .accommodation(let id, _): (.accommodation, id)
        case .transfer(let id): (.transfer, id)
        case .ferry(let id): (.ferry, id)
        case .train(let id): (.train, id)
        case .rentalVehicle(let id, _): (.rentalVehicle, id)
        case .restaurant(let id): (.restaurant, id)
        case .other(let id): (.other, id)
        case .activity, .transport: nil
        }
    }
}

private struct TripItemTypePicker: View {
    var body: some View {
        List(TripItemKind.allCases) { kind in
            NavigationLink {
                TripItemEditorView(kind: kind)
            } label: {
                Label(kind.title, systemImage: kind.symbolName)
                    .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Nieuw reisitem")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TimelineRow: View {
    let item: TimelineItem
    let timeZone: TimeZone
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeText)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
                .padding(.top, 19)

            VStack(spacing: 4) {
                Image(systemName: item.type.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(itemColor)
                    .frame(width: 34, height: 34)
                    .background(itemColor.opacity(0.14), in: Circle())
                    .accessibilityLabel(item.type.title)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2)
                        .frame(minHeight: 62)
                }
            }
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 4)
                    if item.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Gedaan")
                    }
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.travelCoral)
                            .accessibilityLabel("Favoriet")
                    }
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let range = timeRange {
                    Label(range, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 15)
        }
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        guard let startDate = item.startDate else { return "—" }
        return AppFormatters.time(in: timeZone).string(from: startDate)
    }

    private var timeRange: String? {
        guard let startDate = item.startDate, let endDate = item.endDate else { return nil }
        let formatter = AppFormatters.time(in: timeZone)
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    private var itemColor: Color {
        switch item.type {
        case .flight, .transfer, .ferry, .train, .rentalVehicle: .travelTeal
        case .accommodation: .travelGreen
        case .activity: .travelOrange
        case .restaurant: .travelCoral
        case .other: .travelPurple
        }
    }
}

#Preview("Reis") {
    TripTimelinePreview()
}

private struct TripTimelinePreview: View {
    @State private var tripStore = TripStore()

    var body: some View {
        TripView()
            .environment(tripStore)
            .task { tripStore.loadIfNeeded() }
    }
}
