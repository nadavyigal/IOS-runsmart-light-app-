import SwiftUI
import Observation

struct RedesignView: View {
    @Environment(AppState.self) private var appState
    let optimizationId: String
    let snapshot: ResumeSnapshot
    @State private var viewModel = RedesignViewModel()
    @State private var navigateToPreview = false

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView().tint(Theme.accent)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        livePreview
                        styleTabs
                        templateScroll
                        designControls
                        applyButton
                        Spacer().frame(height: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .navigationTitle("Redesign Resume")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await viewModel.load(token: appState.session?.accessToken) }
        .navigationDestination(isPresented: $navigateToPreview) {
            ResumePreviewView(
                optimizationId: optimizationId,
                snapshot: snapshot,
                accentColor: viewModel.selectedAccentColor,
                fontDesign: viewModel.selectedFontDesign
            )
        }
    }

    // MARK: - Live Preview

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)

            DesignLivePreviewCard(
                snapshot: snapshot,
                accentColor: viewModel.selectedAccentColor,
                fontDesign: viewModel.selectedFontDesign,
                spacing: viewModel.spacingValue
            )
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Style Tabs

    private var styleTabs: some View {
        HStack(spacing: 0) {
            ForEach(RedesignViewModel.StyleCategory.allCases) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedCategory = category
                    }
                } label: {
                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .foregroundStyle(
                            category == viewModel.selectedCategory ? Theme.textPrimary : Theme.textSecondary
                        )
                        .background(
                            category == viewModel.selectedCategory ? Theme.accent.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    // MARK: - Template Thumbnails

    private var templateScroll: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Templates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)

            if viewModel.filteredTemplates.isEmpty {
                Text("No templates in this category yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.filteredTemplates) { template in
                            templateCard(template)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func templateCard(_ template: DesignTemplate) -> some View {
        let isSelected = viewModel.selectedTemplate?.id == template.id

        Button { viewModel.selectedTemplate = template } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? viewModel.selectedAccentColor.opacity(0.15) : Theme.bgCard)
                        .frame(width: 80, height: 104)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected ? viewModel.selectedAccentColor : Color.white.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )

                    VStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == 0
                                      ? viewModel.selectedAccentColor.opacity(isSelected ? 0.8 : 0.4)
                                      : Color.white.opacity(0.15))
                                .frame(width: i == 0 ? 50 : CGFloat.random(in: 30...56), height: i == 0 ? 6 : 3)
                        }
                    }
                }

                Text(template.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    // MARK: - Design Controls

    private var designControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Customize")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 0) {
                HStack {
                    Text("Spacing")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(viewModel.spacingLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Slider(value: $viewModel.spacingValue, in: 0.6...1.4, step: 0.2)
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                Divider().padding(.horizontal, 16)

                HStack {
                    Text("Accent Color")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    HStack(spacing: 10) {
                        ForEach(RedesignViewModel.accentOptions, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().stroke(
                                        color == viewModel.selectedAccentColor ? Color.white : Color.clear,
                                        lineWidth: 2
                                    )
                                )
                                .scaleEffect(color == viewModel.selectedAccentColor ? 1.2 : 1.0)
                                .animation(.spring(duration: 0.2), value: viewModel.selectedAccentColor)
                                .onTapGesture { viewModel.selectedAccentColor = color }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 16)

                HStack {
                    Text("Font Style")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("Font", selection: $viewModel.selectedFont) {
                        ForEach(RedesignViewModel.FontOption.allCases) { font in
                            Text(font.rawValue).tag(font)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 4)
            }
            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        }
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await applyDesign() }
            } label: {
                Group {
                    if viewModel.isApplying {
                        ProgressView().tint(.white)
                    } else {
                        Label("Apply Design", systemImage: "paintbrush.fill")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(.white)
                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous))
            }
            .disabled(viewModel.isApplying || viewModel.selectedTemplate == nil)

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    private func applyDesign() async {
        await viewModel.applyDesign(optimizationId: optimizationId, token: appState.session?.accessToken)
        if viewModel.statusMessage?.contains("error") == false {
            navigateToPreview = true
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class RedesignViewModel {
    var templates: [DesignTemplate] = []
    var selectedTemplate: DesignTemplate?
    var selectedCategory: StyleCategory = .modern
    var spacingValue: Double = 1.0
    var selectedAccentColor: Color = Theme.accent
    var selectedFont: FontOption = .inter
    var isLoading = false
    var isApplying = false
    var statusMessage: String?

    private let apiClient = APIClient()

    enum StyleCategory: String, CaseIterable, Identifiable {
        case atsSafe = "ATS Safe"
        case modern = "Modern"
        case creative = "Creative"
        var id: String { rawValue }
    }

    enum FontOption: String, CaseIterable, Identifiable {
        case inter = "Inter"
        case serif = "Serif"
        case mono = "Mono"
        var id: String { rawValue }
        var design: Font.Design {
            switch self {
            case .inter:  return .default
            case .serif:  return .serif
            case .mono:   return .monospaced
            }
        }
    }

    static let accentOptions: [Color] = [
        Theme.accent,
        Theme.accentBlue,
        Theme.accentCyan,
        Color(red: 0.95, green: 0.35, blue: 0.35),
        Color(red: 0.2,  green: 0.7,  blue: 0.4),
    ]

    var selectedFontDesign: Font.Design { selectedFont.design }

    var spacingLabel: String {
        switch spacingValue {
        case ..<0.8:  return "Compact"
        case ..<1.1:  return "Normal"
        case ..<1.3:  return "Relaxed"
        default:      return "Comfortable"
        }
    }

    var filteredTemplates: [DesignTemplate] {
        switch selectedCategory {
        case .atsSafe:  return templates.filter { ($0.atsScore ?? 0) >= 90 }
        case .modern:   return templates.filter { $0.category == "modern" || $0.category == "minimal" }
        case .creative: return templates.filter { $0.category == "creative" }
        }
    }

    func load(token: String?) async {
        guard let token else { statusMessage = "Please sign in to load templates."; return }
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let response: DesignTemplatesResponse = try await apiClient.get(
                endpoint: .designTemplates(category: "all"),
                token: token
            )
            templates = response.templates
            selectedTemplate = response.templates.first
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func applyDesign(optimizationId: String, token: String?) async {
        guard let token else { statusMessage = "Please sign in to apply design."; return }
        guard let template = selectedTemplate else { statusMessage = "Select a template first."; return }

        isApplying = true
        statusMessage = nil
        defer { isApplying = false }

        do {
            let body: [String: Any] = ["templateId": template.id]
            let _: APIStatusResponse = try await apiClient.postJSON(
                endpoint: .designCustomize(optimizationId: optimizationId),
                body: body,
                token: token
            )
            statusMessage = "Design applied!"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

// MARK: - Supporting response type

private struct DesignTemplatesResponse: Decodable {
    let templates: [DesignTemplate]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templates = (try? container.decode([DesignTemplate].self, forKey: .templates))
            ?? (try? container.decode([DesignTemplate].self, forKey: .data))
            ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case templates, data
    }
}
