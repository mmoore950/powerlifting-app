import SwiftUI
import UIKit

/// Prototype of the documented URL-copy export route. Provider/directory save
/// behavior still needs actual native verification; no movie Data is constructed.
@MainActor
struct AnnotationExportPicker: UIViewControllerRepresentable {
    let package: PreparedAnnotationExport
    let requestDismissal: (Bool, String?) -> Void
    let dismantled: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(requestDismissal: requestDismissal, dismantled: dismantled) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [package.directory], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIDocumentPickerViewController, coordinator: Coordinator) {
        controller.delegate = nil
        coordinator.finishDismantling()
    }
    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let requestDismissal: (Bool, String?) -> Void
        private let dismantled: () -> Void
        private var resultDelivered = false, teardownDelivered = false
        init(requestDismissal: @escaping (Bool, String?) -> Void, dismantled: @escaping () -> Void) {
            self.requestDismissal = requestDismissal; self.dismantled = dismantled
            super.init()
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(saved: !urls.isEmpty, message: urls.isEmpty ? "Files did not return a saved destination. The prepared package is retained." : nil)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(saved: false, message: nil) }
        func finishDismantling() {
            guard !teardownDelivered else { return }
            teardownDelivered = true
            dismantled()
        }
        private func finish(saved: Bool, message: String?) {
            guard !resultDelivered, !teardownDelivered else { return }
            resultDelivered = true
            // The provider result closes the dialog; its package lease remains
            // active until SwiftUI dismantles this exact presentation.
            requestDismissal(saved, message)
        }
    }
}
