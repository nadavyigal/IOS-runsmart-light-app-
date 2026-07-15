import SafariServices
import SwiftUI

/// In-app browser for external documents (Terms, Privacy). WP-44 S6: links on
/// the sign-in screen previously ejected the user to external Safari before
/// they had even created an account (audit §10 B14).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
