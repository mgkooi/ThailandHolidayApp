import SwiftUI

struct BookingScanReviewView: View {
    let result: BookingExtractionResult
    @Binding var selectedType: BookingDetectedType
    let continueReview: () -> Void

    var body: some View {
        List {
            Section("Boeking herkend") {
                Picker("Type boeking", selection: $selectedType) {
                    ForEach(BookingDetectedType.allCasesForPicker, id: \.self) { type in
                        Text(type.dutchTitle).tag(type)
                    }
                }
                LabeledContent("Herkenning", value: result.recognitionLabel)
            }
            if !result.warnings.isEmpty {
                Section("Controleer") {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section {
                Button("Controleer gegevens", action: continueReview)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Scanresultaat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension BookingDetectedType {
    var dutchTitle: String {
        switch self {
        case .flight: "Vlucht"
        case .accommodation: "Accommodatie"
        case .transfer: "Transfer / taxi"
        case .rentalVehicle: "Huur vervoer"
        case .ferry: "Boot / ferry"
        case .train: "Trein"
        case .restaurant: "Restaurant"
        case .activity: "Activiteit"
        case .other: "Overig"
        }
    }
}
