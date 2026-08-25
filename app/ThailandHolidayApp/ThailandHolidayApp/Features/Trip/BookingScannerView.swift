import PhotosUI
import SwiftUI

struct BookingScannerView: View {
    @Environment(TripStore.self) private var tripStore
    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var result: BookingExtractionResult?
    @State private var statusText: String?
    @State private var errorMessage: String?
    @State private var showEditor = false
    @State private var forcedType: BookingDetectedType?
    @State private var selectedType: BookingDetectedType = .other
    @State private var keepAttachment = true
    @State private var showsCamera = false

    var body: some View {
        Group {
            if let statusText {
                VStack(spacing: 16) { ProgressView(); Text(statusText).foregroundStyle(.secondary) }
            } else if let result, result.detectedType == .other, forcedType == nil {
                typeQuestion(result)
            } else if let result {
                BookingScanReviewView(result: result, selectedType: $selectedType) { showEditor = true }
                    .safeAreaInset(edge: .bottom) {
                        Toggle("Bewaar afbeelding als boekingsbewijs", isOn: $keepAttachment)
                            .padding().background(.bar)
                    }
            } else {
                ContentUnavailableView {
                    Label("Scan boeking", systemImage: "doc.viewfinder")
                } description: {
                    Text("Maak een foto of kies een boekingsbevestiging uit Foto’s.")
                } actions: {
                    VStack(spacing: 12) {
                        if CameraImagePicker.isAvailable {
                            Button { showsCamera = true } label: {
                                Label("Maak foto", systemImage: "camera")
                            }.buttonStyle(.borderedProminent)
                        }
                        PhotosPicker(selection: $selection, matching: .images) {
                            Label("Kies afbeelding", systemImage: "photo")
                        }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("Scan boeking")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selection) { _, item in if let item { Task { await scan(item) } } }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraImagePicker { data in Task { await scan(imageData: data) } }
                .ignoresSafeArea()
        }
        .onChange(of: selectedType) { _, type in
            guard let current = result, current.detectedType != type, let trip = tripStore.trip else { return }
            result = BookingReclassificationService().reparse(current, as: type, trip: trip)
            forcedType = type
        }
        .navigationDestination(isPresented: $showEditor) {
            if let result {
                TripItemEditorView(kind: result.detectedType.tripItemKind, extraction: result,
                    scannedImageData: keepAttachment ? imageData : nil)
            }
        }
        .alert("Boeking niet herkend", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage=nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Probeer een duidelijkere afbeelding.") }
    }

    private func typeQuestion(_ current: BookingExtractionResult) -> some View {
        List {
            Section("Wat voor boeking is dit?") {
                ForEach(BookingDetectedType.allCasesForPicker, id: \.self) { type in
                    Button(type.dutchTitle) {
                        forcedType = type
                        guard let trip=tripStore.trip else { return }
                        result = DeterministicBookingExtractor().extract(
                            text: RecognizedBookingText(originalText: current.originalRecognizedText), trip: trip, forcedType: type)
                        selectedType = type
                    }
                }
            }
        }
    }

    private func scan(_ item: PhotosPickerItem) async {
        do {
            statusText="Boeking wordt gelezen…"
            let data=try await item.loadTransferable(type: Data.self)
            guard let data else { throw BookingOCRError.invalidImage }
            await scan(imageData: data)
        } catch {
            statusText=nil; errorMessage="De boeking kon niet worden gelezen."
        }
    }

    /// Shared entry point for camera and photo-library data.
    private func scan(imageData data: Data) async {
        guard let trip=tripStore.trip else { return }
        do {
            statusText="Boeking wordt gelezen…"
            imageData=data
            let recognized=try await BookingOCRService().recognize(imageData:data)
            statusText="Gegevens worden herkend…"
            result=try await DeterministicBookingExtractor().extract(text:recognized,trip:trip)
            selectedType=result?.detectedType ?? .other
            statusText=nil
        } catch {
            statusText=nil; errorMessage="De boeking kon niet worden gelezen."
        }
    }
}

extension BookingDetectedType {
    static let allCasesForPicker: [Self] = [.flight,.accommodation,.transfer,.rentalVehicle,.ferry,.train,.restaurant,.activity,.other]
    var tripItemKind: TripItemKind {
        switch self {
        case .flight: .flight; case .accommodation: .accommodation; case .transfer: .transfer
        case .rentalVehicle: .rentalVehicle; case .ferry: .ferry; case .train: .train
        case .restaurant: .restaurant; case .activity: .activity; case .other: .other
        }
    }
}
