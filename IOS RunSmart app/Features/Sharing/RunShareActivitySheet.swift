import SwiftUI
import UIKit

struct RunShareActivityItem: Identifiable {
    let id = UUID()
    let fileURL: URL
    let caption: String
}

/// The file and its App Store discovery URL are separate share items. A printed footer isn't a link.
struct RunShareActivitySheet: UIViewControllerRepresentable {
    let item: RunShareActivityItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [item.fileURL, item.caption, ExternalURLs.appStore],
            applicationActivities: nil
        )
        controller.excludedActivityTypes = [.assignToContact, .addToReadingList, .print]
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
