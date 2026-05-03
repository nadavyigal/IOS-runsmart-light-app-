import Foundation

struct StreamingClient {
    func streamLines(
        endpoint: Endpoint,
        token: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: BackendConfig.apiBaseURL.appendingPathComponent(endpoint.path))
                    request.httpMethod = "POST"
                    if let token {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw APIClientError.invalidResponse
                    }

                    for try await line in bytes.lines where !line.isEmpty {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
