import SwiftUI

/// Native SwiftUI live preview of a resume with the selected template's design applied.
/// No WebView needed — renders resume content using template colors and fonts.
struct DesignLivePreviewCard: View {
    let snapshot: ResumeSnapshot
    let accentColor: Color
    let fontDesign: Font.Design
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header band
            HStack(alignment: .top, spacing: 12) {
                initialsAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 16, weight: .bold, design: fontDesign))
                        .foregroundStyle(.black)
                    Text(snapshot.subtitle)
                        .font(.system(size: 11, design: fontDesign))
                        .foregroundStyle(.gray)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(accentColor.opacity(0.08))

            // Sections preview
            VStack(alignment: .leading, spacing: spacing * 6) {
                ForEach(snapshot.sections.prefix(3)) { section in
                    previewSection(section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private var initialsAvatar: some View {
        let initials = snapshot.title
            .components(separatedBy: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0) }
            .joined()

        return ZStack {
            Circle()
                .fill(accentColor)
                .frame(width: 36, height: 36)
            Text(initials.isEmpty ? "R" : initials)
                .font(.system(size: 14, weight: .bold, design: fontDesign))
                .foregroundStyle(.white)
        }
    }

    private func previewSection(_ section: ResumeSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section title
            HStack {
                Text(section.title.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: fontDesign))
                    .foregroundStyle(accentColor)
                    .tracking(1)
                Rectangle()
                    .fill(accentColor.opacity(0.3))
                    .frame(height: 0.5)
            }

            // Lines
            ForEach(section.lines.prefix(3), id: \.self) { line in
                Text("• \(line)")
                    .font(.system(size: 9, design: fontDesign))
                    .foregroundStyle(Color(white: 0.2))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Template Thumbnail Card

struct TemplateThumbnailCard: View {
    let template: DesignTemplate
    let accentColor: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 80, height: 110)
                        .shadow(color: .black.opacity(isSelected ? 0 : 0.1), radius: 4)

                    // Mini resume layout
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentColor)
                            .frame(height: 18)
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.gray.opacity(0.25))
                                .frame(height: 5)
                        }
                        Spacer().frame(height: 4)
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)
                        }
                    }
                    .padding(8)

                    if template.isPremium == true {
                        VStack {
                            HStack {
                                Spacer()
                                Text("Pro")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.15), in: Capsule())
                                    .padding(4)
                            }
                            Spacer()
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? accentColor : Color.clear, lineWidth: 2)
                )
                .scaleEffect(isSelected ? 1.04 : 1.0)
                .animation(.spring(duration: 0.25), value: isSelected)

                Text(template.name)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
