import Foundation

enum DeepLinkRouter {
    static func parseSharedJobURL(from url: URL) -> URL? {
        guard url.scheme == "resumebuilder" || url.host == "share" else { return nil }

        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = queryItems.first(where: { $0.name == "url" })?.value,
           let extractedURL = URL(string: value) {
            return extractedURL
        }

        return nil
    }
}
