import Foundation

enum APIClientError: Error, LocalizedError {
    case unauthorized
    case serverError(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized"
        case .serverError(let status, let message):
            return "Server error (\(status)): \(message)"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}

struct APIClient {
    var baseURL: URL = BackendConfig.apiBaseURL

    func postJSON<T: Decodable>(
        endpoint: Endpoint,
        body: [String: Any],
        token: String?
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await send(request)
    }

    func get<T: Decodable>(endpoint: Endpoint, token: String?) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = "GET"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request)
    }

    func uploadResume(fileURL: URL, token: String?) async throws -> ResumeUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent(Endpoint.uploadResume.path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"resume\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"jobDescription\"\r\n\r\n".data(using: .utf8)!)
        body.append("Imported resume baseline for mobile profile.\r\n".data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIClientError.unauthorized
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIClientError.serverError(status: httpResponse.statusCode, message: message)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
