import SwiftUI
import Observation
import PhotosUI
import UIKit

struct ActivityDetailView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mapOpening) private var mapOpening

    let activityID: UUID

    @State private var isEditing = false
    @State private var draft: ActivityEditDraft?
    @State private var showsSaveError = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var enlargedImage: UIImage?

    private var activity: Activity? {
        tripStore.trip?.activities.first { $0.id == activityID }
    }

    private var timeZone: TimeZone {
        tripStore.trip?.timeZone ?? TripCalendar.thailandTimeZone
    }

    var body: some View {
        Group {
            if let activity {
                Form {
                    if isEditing, let draft {
                        editSections(draft)
                    } else {
                        detailSections(activity)
                    }
                }
                .environment(\.timeZone, timeZone)
            } else {
                ContentUnavailableView("Activiteit niet gevonden", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(activity?.title ?? "Activiteit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Wijzigingen niet opgeslagen", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Probeer het opnieuw.")
        }
        .fullScreenCover(isPresented: Binding(
            get: { enlargedImage != nil },
            set: { if !$0 { enlargedImage = nil } }
        )) {
            if let enlargedImage { AttachmentImageViewer(image: enlargedImage) }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    draft?.replacementImageData = try await item.loadTransferable(type: Data.self)
                    draft?.removesAttachment = false
                } catch {
                    showsSaveError = true
                }
            }
        }
    }

    @ViewBuilder
    private func detailSections(_ activity: Activity) -> some View {
        Section("Activiteit") {
            LabeledContent("Titel", value: activity.title)
            LabeledContent("Datum", value: AppFormatters.dutchDate(in: timeZone).string(from: activity.date).capitalized)
            LabeledContent("Tijd", value: timeRange(for: activity))
            LabeledContent("Categorie", value: category(for: activity).title)
        }

        if activity.description != nil || activity.notes != nil {
            Section("Details") {
                if let description = activity.description {
                    LabeledContent("Beschrijving") { Text(description).multilineTextAlignment(.trailing) }
                }
                if let notes = activity.notes {
                    LabeledContent("Notities") { Text(notes).multilineTextAlignment(.trailing) }
                }
            }
        }


        if let url = activity.url {
            Section("Link / website") {
                Link(destination: url) {
                    Label("Open link", systemImage: "arrow.up.right.square")
                        .foregroundStyle(Color.travelTeal)
                }
            }
        }

        if let image = attachmentImage(filename: activity.attachmentFilename) {
            Section("Boeking / bijlage") {
                Button { enlargedImage = image } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bekijk bijlage op volledig scherm")
            }
        }

        Section {
            let fallback = TripLocation(placeName: activity.title, address: nil,
                                        latitude: activity.latitude, longitude: activity.longitude)
            let location = activity.location ?? fallback
            Button { Task { _ = await mapOpening.navigate(to: location, name: activity.title) } } label: {
                Label("Navigeer", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            Toggle("Favoriet", isOn: favoriteBinding(for: activity))
            Toggle("Gedaan", isOn: completedBinding(for: activity))
        }
    }

    @ViewBuilder
    private func editSections(_ draft: ActivityEditDraft) -> some View {
        @Bindable var draft = draft

        Section("Activiteit") {
            TextField("Titel", text: $draft.title)
            DatePicker("Datum", selection: $draft.date, displayedComponents: .date)
            DatePicker("Starttijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            Toggle("Eindtijd", isOn: $draft.hasEndTime)
            if draft.hasEndTime {
                DatePicker("Eindtijd", selection: $draft.endTime, displayedComponents: .hourAndMinute)
            }
            Picker("Categorie", selection: $draft.category) {
                ForEach(ItineraryCategory.allCases, id: \.self) { category in
                    Text(category.title).tag(category)
                }
            }
        }

        Section("Beschrijving") {
            TextEditor(text: $draft.description)
                .frame(minHeight: 90)
        }

        Section("Notities") {
            TextEditor(text: $draft.notes)
                .frame(minHeight: 90)
        }


        Section("Link / website") {
            TextField("https://…", text: $draft.urlString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            if !draft.urlString.isEmpty, draft.validatedURL == nil {
                Text("Vul een geldige link in, bijvoorbeeld https://example.com.")
                    .font(.caption)
                    .foregroundStyle(Color.travelCoral)
            }
        }

        Section("Boeking / bijlage") {
            if let image = draftPreviewImage(draft) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(draftHasAttachment(draft) ? "Vervang afbeelding" : "Kies afbeelding", systemImage: "photo")
            }

            if draftHasAttachment(draft) {
                Button("Verwijder afbeelding", role: .destructive) {
                    draft.replacementImageData = nil
                    draft.removesAttachment = true
                    selectedPhotoItem = nil
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuleer") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Bewaar") { saveDraft() }
                    .disabled(!canSaveDraft)
            }
        } else if let activity {
            ToolbarItem(placement: .primaryAction) {
                Button("Bewerken") {
                    draft = ActivityEditDraft(activity: activity)
                    isEditing = true
                }
            }
        }
    }

    private func saveDraft() {
        guard let activity, let draft else { return }
        let updatedActivity = draft.activity(updating: activity, timeZone: timeZone)
        guard tripStore.updateActivity(updatedActivity, replacementImageData: draft.replacementImageData) else {
            showsSaveError = true
            return
        }
        isEditing = false
        self.draft = nil
    }

    private var canSaveDraft: Bool {
        guard let draft else { return false }
        return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (draft.urlString.nilIfBlank == nil || draft.validatedURL != nil)
    }

    private func attachmentImage(filename: String?) -> UIImage? {
        guard let filename, let url = tripStore.attachmentURL(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func draftPreviewImage(_ draft: ActivityEditDraft) -> UIImage? {
        if let data = draft.replacementImageData { return UIImage(data: data) }
        guard !draft.removesAttachment else { return nil }
        return attachmentImage(filename: activity?.attachmentFilename)
    }

    private func draftHasAttachment(_ draft: ActivityEditDraft) -> Bool {
        draftPreviewImage(draft) != nil
    }

    private func favoriteBinding(for activity: Activity) -> Binding<Bool> {
        Binding(
            get: { self.activity?.isFavorite ?? activity.isFavorite },
            set: { if !tripStore.setActivityFavorite(id: activity.id, isFavorite: $0) { showsSaveError = true } }
        )
    }

    private func completedBinding(for activity: Activity) -> Binding<Bool> {
        Binding(
            get: { self.activity?.isCompleted ?? activity.isCompleted },
            set: { if !tripStore.setActivityCompleted(id: activity.id, isCompleted: $0) { showsSaveError = true } }
        )
    }

    private func timeRange(for activity: Activity) -> String {
        let formatter = AppFormatters.time(in: timeZone)
        let start = formatter.string(from: activity.startTime)
        guard let end = activity.endTime else { return start }
        return "\(start) – \(formatter.string(from: end))"
    }

    private func category(for activity: Activity) -> ItineraryCategory {
        ItineraryCategory(rawValue: activity.category) ?? .other
    }
}

@MainActor
@Observable
final class ActivityEditDraft {
    var title: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var hasEndTime: Bool
    var category: ItineraryCategory
    var description: String
    var notes: String
    var urlString: String
    var replacementImageData: Data?
    var removesAttachment = false

    init(activity: Activity) {
        title = activity.title
        date = activity.date
        startTime = activity.startTime
        endTime = activity.endTime ?? activity.startTime
        hasEndTime = activity.endTime != nil
        category = ItineraryCategory(rawValue: activity.category) ?? .other
        description = activity.description ?? ""
        notes = activity.notes ?? ""
        urlString = activity.url?.absoluteString ?? ""
    }

    var validatedURL: URL? {
        guard let value = urlString.nilIfBlank,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return nil }
        return components.url
    }

    func activity(updating original: Activity, timeZone: TimeZone) -> Activity {
        let calendar = TripCalendar.calendar(in: timeZone)
        let newDate = calendar.startOfDay(for: date)
        return original.updating(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: newDate,
            startTime: calendar.combining(day: newDate, time: startTime),
            endTime: .some(hasEndTime ? calendar.combining(day: newDate, time: endTime) : nil),
            category: category.rawValue,
            description: .some(description.nilIfBlank),
            notes: .some(notes.nilIfBlank),
            url: .some(validatedURL),
            attachmentFilename: removesAttachment ? .some(nil) : nil
        )
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Calendar {
    func combining(day: Date, time: Date) -> Date {
        let clock = dateComponents([.hour, .minute, .second], from: time)
        return date(
            bySettingHour: clock.hour ?? 0,
            minute: clock.minute ?? 0,
            second: clock.second ?? 0,
            of: day
        ) ?? day
    }
}

private struct AttachmentImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sluit") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
