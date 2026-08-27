import Observation

@MainActor @Observable
final class AppFeedbackState {
    private(set) var message: String?

    func reportSave(kind: TripItemKind, isNew: Bool, succeeded: Bool) {
        guard succeeded else { return }
        message = isNew ? "\(kind.title) toegevoegd" : "Wijzigingen opgeslagen"
    }

    func reportSave(kind: TripItemKind, isNew: Bool, succeeded: Bool, tripName: String?) {
        guard succeeded else { return }
        if isNew, let tripName { message = "\(kind.title) toegevoegd aan \(tripName)" }
        else { reportSave(kind: kind, isNew: isNew, succeeded: succeeded) }
    }

    func clear() { message = nil }

    func show(_ value: String) { message = value }
}
