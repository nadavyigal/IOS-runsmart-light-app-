import Foundation
import UIKit

@MainActor
struct PDFExporter {
    static func presentShareSheet(fileURL: URL, from controller: UIViewController) {
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        controller.present(activityVC, animated: true)
    }
}
