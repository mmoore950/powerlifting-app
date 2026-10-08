import Foundation

struct AnnotationExportPresentation: Identifiable, Sendable {
    let id = UUID()
    let package: PreparedAnnotationExport
}
struct AnnotationExportPickerCompletion: Sendable {
    let packageID: UUID
    let saved: Bool
    let message: String?
}

/// Delegate results request dismissal, but only dismantling the matching
/// presentation permits lease release/retry. Old dismissal callbacks are inert.
struct AnnotationExportPickerState {
    private(set) var active: AnnotationExportPresentation?
    private var result: AnnotationExportPickerCompletion?

    mutating func begin(_ package: PreparedAnnotationExport) throws -> AnnotationExportPresentation {
        guard active == nil else { throw AnnotationExportError.busy }
        let presentation = AnnotationExportPresentation(package: package)
        active = presentation; result = nil
        return presentation
    }
    mutating func requestDismissal(_ id: UUID, saved: Bool, message: String?) -> Bool {
        guard let active, active.id == id, result == nil else { return false }
        result = AnnotationExportPickerCompletion(packageID: active.package.id, saved: saved, message: message)
        return true
    }
    mutating func dismantle(_ id: UUID) -> AnnotationExportPickerCompletion? {
        guard let active, active.id == id else { return nil }
        let completion = result ?? AnnotationExportPickerCompletion(packageID: active.package.id, saved: false, message: nil)
        self.active = nil; result = nil
        return completion
    }
}
