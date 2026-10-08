import SwiftUI
import UIKit

/// Prototype of the documented URL-copy export route. Provider/directory save
/// behavior still needs actual native verification; no movie Data is constructed.
@MainActor
struct AnnotationExportPicker: UIViewControllerRepresentable {
    let package: PreparedAnnotationExport
    let completion: (Bool, String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [package.directory], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIDocumentPickerViewController, coordinator: Coordinator) {
        controller.delegate = nil
        coordinator.cancelIfUnfinished()
    }
    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Bool, String?) -> Void
        private var finished = false
        init(completion: @escaping (Bool, String?) -> Void) {
            self.completion = completion
            super.init()
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(saved: !urls.isEmpty, message: urls.isEmpty ? "Files did not return a saved destination. The prepared package is retained." : nil)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(saved: false, message: nil) }
        func cancelIfUnfinished() { finish(saved: false, message: nil) }
        private func finish(saved: Bool, message: String?) {
            guard !finished else { return }
            finished = true; completion(saved, message)
        }
    }
}
