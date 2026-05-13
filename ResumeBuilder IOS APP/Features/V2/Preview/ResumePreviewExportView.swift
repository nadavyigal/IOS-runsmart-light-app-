import SwiftUI
import UIKit

struct ResumePreviewExportView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ResumePreviewViewModel

    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                GreetingHeader(name: "there", screenTitle: "Export")
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.xl)

                // Mode toggle
                modePicker

                // Paper preview
                pdfPreviewCard

                // PDF status row
                pdfStatusRow

                // Export action cards
                VStack(spacing: AppSpacing.md) {
                    ExportActionCard(
                        icon: "arrow.down.circle.fill",
                        title: "Download PDF",
                        subtitle: "Save to Files app",
                        accentColor: AppColors.accentTeal,
                        isLoading: viewModel.isDownloading
                    ) {
                        Task { await viewModel.downloadPDF(token: appState.session?.accessToken) }
                    }

                    if let fileURL = viewModel.exportedFileURL {
                        ShareLink(
                            item: fileURL,
                            subject: Text("My resume"),
                            message: Text(viewModel.shareScoreMessage),
                            preview: SharePreview("Resume PDF", icon: Image(systemName: "doc.richtext"))
                        ) {
                            shareExportRow(
                                icon: "square.and.arrow.up",
                                title: "Share PDF",
                                subtitle: "AirDrop, Mail, Messages…",
                                accentColor: AppColors.accentSky
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isDownloading)
                    } else {
                        ExportActionCard(
                            icon: "square.and.arrow.up",
                            title: "Share",
                            subtitle: "Generate a PDF first",
                            accentColor: AppColors.accentSky
                        ) {
                            showShareSheet = true
                        }
                    }

                    if let line = viewModel.shareScoreLine {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Share score")
                                .font(.appSubheadline)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(line)
                                .font(.appCaption)
                                .foregroundStyle(AppColors.textSecondary)
                            Button("Copy share text") {
                                UIPasteboard.general.string = line
                            }
                            .font(.appCaption)
                            .foregroundStyle(AppColors.gradientMid)
                        }
                        .padding(AppSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: AppRadii.lg)
                    }

                    ExportActionCard(
                        icon: "bookmark.fill",
                        title: "Save Version",
                        subtitle: "Keep a copy in your history",
                        accentColor: AppColors.accentViolet
                    ) {}
                }
                .padding(.horizontal, AppSpacing.lg)

                // Privacy footer
                Label("Your resume data is encrypted end-to-end.", systemImage: "lock.shield.fill")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.lg)

                Spacer(minLength: 100)
            }
        }
        .scrollIndicators(.hidden)
        .screenBackground(showRadialGlow: false)
        .navigationTitle("Preview & Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .onChange(of: viewModel.exportedFileURL) { _, newURL in
            if newURL != nil { showShareSheet = false }
        }
        .if(viewModel.errorMessage != nil) { view in
            view.overlay(alignment: .top) {
                Text(viewModel.errorMessage!)
                    .font(.appCaption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.lg)
            }
        }
    }

    // MARK: - Subviews

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach([("Optimized", PreviewMode.optimized), ("Designed", PreviewMode.designed)], id: \.0) { label, mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.mode = mode
                    }
                } label: {
                    Text(label)
                        .font(.appSubheadline)
                        .foregroundStyle(viewModel.mode == mode ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            viewModel.mode == mode
                                ? AnyShapeStyle(AppGradients.primary)
                                : AnyShapeStyle(Color.clear)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(GradientButtonStyle())
            }
        }
        .padding(4)
        .glassCard(cornerRadius: AppRadii.full)
        .padding(.horizontal, AppSpacing.lg)
    }

    private var pdfPreviewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadii.glass, style: .continuous)
                .fill(Color.white)
                .frame(height: 280)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)

            if viewModel.isDownloading {
                ProgressView()
                    .tint(AppColors.gradientMid)
            } else if viewModel.pdfData != nil {
                VStack {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.gradientMid)
                    Text("PDF Ready")
                        .font(.appSubheadline)
                        .foregroundStyle(AppColors.backgroundBottom)
                }
            } else {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.gray.opacity(0.4))
                    Text("Tap Download to generate PDF")
                        .font(.appCaption)
                        .foregroundStyle(Color.gray)
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private var pdfStatusRow: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: viewModel.pdfData != nil ? "checkmark.circle.fill" : "clock.fill")
                .foregroundStyle(viewModel.pdfData != nil ? AppColors.accentTeal : AppColors.textSecondary)
            Text(viewModel.pdfData != nil ? "PDF generated and ready" : "Not yet exported")
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private func shareExportRow(icon: String, title: String, subtitle: String, accentColor: Color) -> some View {
        HStack(spacing: AppSpacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadii.sm, style: .continuous)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSubheadline)
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.lg)
        .glassCard(cornerRadius: AppRadii.lg)
    }
}

// MARK: - Helpers

extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}

#Preview {
    NavigationStack {
        ResumePreviewExportView(
            viewModel: ResumePreviewViewModel(
                optimizationId: "mock-opt-001",
                atsScorePercent: 82,
                exportService: MockResumeExportService()
            )
        )
    }
    .environment(AppState())
}
