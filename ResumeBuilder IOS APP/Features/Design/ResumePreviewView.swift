import SwiftUI

struct ResumePreviewView: View {
    @Environment(AppState.self) private var appState
    let optimizationId: String
    let snapshot: ResumeSnapshot
    let accentColor: Color
    let fontDesign: Font.Design

    @State private var showOptimized = false
    @State private var scale: CGFloat = 1.0
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var shareItem: URL?
    @State private var showShareSheet = false
    @State private var isSaving = false
    @State private var showSaveSuccess = false

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    viewToggle
                    resumeSheet
                    fileRow
                    exportButtons
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Resume Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareItem {
                ShareSheet(activityItems: [url])
            }
        }
        .overlay {
            if showSaveSuccess {
                savedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: showSaveSuccess)
    }

    // MARK: - View Toggle

    private var viewToggle: some View {
        HStack(spacing: 0) {
            toggleTab(label: "Optimized", isSelected: !showOptimized) {
                withAnimation(.easeInOut(duration: 0.2)) { showOptimized = false }
            }
            toggleTab(label: "Designed", isSelected: showOptimized) {
                withAnimation(.easeInOut(duration: 0.2)) { showOptimized = true }
            }
        }
        .padding(3)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    private func toggleTab(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .background(
                    isSelected ? Theme.accent.opacity(0.2) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Resume Sheet

    private var resumeSheet: some View {
        ZStack {
            // White paper background
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)

            ScrollView {
                if showOptimized {
                    designedResumeContent
                } else {
                    plainResumeContent
                }
            }
            .frame(height: 480)
        }
        .scaleEffect(scale)
        .gesture(
            MagnificationGesture()
                .onChanged { val in
                    scale = max(0.8, min(1.6, val))
                }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.3)) { scale = 1.0 }
                }
        )
    }

    private var designedResumeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header band
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 44, height: 44)
                    Text(initials)
                        .font(.system(size: 18, weight: .bold, design: fontDesign))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 18, weight: .bold, design: fontDesign))
                        .foregroundStyle(.black)
                    Text(snapshot.subtitle)
                        .font(.system(size: 12, design: fontDesign))
                        .foregroundStyle(Color.gray)
                }
                Spacer()
            }
            .padding(16)
            .background(accentColor.opacity(0.1))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(snapshot.sections) { section in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(section.title.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: fontDesign))
                                .foregroundStyle(accentColor)
                                .tracking(1.2)
                            Rectangle().fill(accentColor.opacity(0.4)).frame(height: 0.5)
                        }
                        ForEach(section.lines, id: \.self) { line in
                            Text("• \(line)")
                                .font(.system(size: 11, design: fontDesign))
                                .foregroundStyle(Color(white: 0.15))
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var plainResumeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snapshot.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
            Text(snapshot.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.gray)

            ForEach(snapshot.sections) { section in
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .tracking(1)
                    Rectangle().fill(Color.black.opacity(0.4)).frame(height: 0.5)
                    ForEach(section.lines, id: \.self) { line in
                        Text("• \(line)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.2))
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - File Row

    private var fileRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(showOptimized ? "Designed_Resume.pdf" : "Optimized_Resume.pdf")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Circle().fill(Theme.accentCyan).frame(width: 6, height: 6)
                    Text("PDF ready")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    // MARK: - Export Buttons

    private var exportButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 10) {
                exportButton(
                    icon: "arrow.down.circle.fill",
                    label: "Download PDF",
                    isLoading: isDownloading
                ) {
                    Task { await downloadPDF() }
                }

                exportButton(icon: "square.and.arrow.up.fill", label: "Share") {
                    Task { await downloadAndShare() }
                }

                exportButton(icon: "bookmark.fill", label: "Save Version", isLoading: isSaving) {
                    Task { await saveVersion() }
                }
            }

            if let error = downloadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Your files are secure and never shared without permission.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func exportButton(
        icon: String,
        label: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if isLoading {
                        ProgressView().tint(Theme.accent).scaleEffect(0.8)
                    } else {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 24, height: 24)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isSaving)
    }

    // MARK: - Save Toast

    private var savedToast: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentCyan)
                Text("Saved to your applications!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.bgCard, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.top, 60)
            Spacer()
        }
    }

    // MARK: - Actions

    private var initials: String {
        snapshot.title
            .components(separatedBy: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0) }
            .joined()
    }

    private func downloadPDF() async {
        guard let token = appState.session?.accessToken else { downloadError = "Sign in first."; return }
        isDownloading = true
        downloadError = nil
        defer { isDownloading = false }
        do {
            let url = try await fetchPDF(optimizationId: optimizationId, token: token)
            shareItem = url
            showShareSheet = true
        } catch {
            downloadError = error.localizedDescription
        }
    }

    private func downloadAndShare() async {
        await downloadPDF()
    }

    private func saveVersion() async {
        guard let token = appState.session?.accessToken else { return }
        isSaving = true
        defer { isSaving = false }

        struct SaveRequest: Encodable {
            let optimizationId: String
        }

        let apiClient = APIClient()
        _ = try? await apiClient.postCodable(
            endpoint: .applications,
            body: SaveRequest(optimizationId: optimizationId),
            token: token
        ) as APIStatusResponse

        withAnimation { showSaveSuccess = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { showSaveSuccess = false }
    }

    private func fetchPDF(optimizationId: String, token: String) async throws -> URL {
        let baseURL = BackendConfig.apiBaseURL
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/download/\(optimizationId)"
        components.queryItems = [URLQueryItem(name: "fmt", value: "pdf")]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("Resume_\(optimizationId).pdf")
        try data.write(to: fileURL)
        return fileURL
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
