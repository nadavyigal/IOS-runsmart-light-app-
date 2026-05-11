import SwiftUI

/// Native SwiftUI live-preview of a resume with the selected template's design applied.
/// Renders resume content using template colors and fonts — no WebView needed.
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
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var initialsAvatar: some View {
        let parts = snapshot.title.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }.joined()

        return ZStack {
            Circle()
                .fill(accentColor.opacity(0.15))
                .frame(width: 40, height: 40)
            Text(letters.isEmpty ? "R" : letters)
                .font(.system(size: 14, weight: .bold, design: fontDesign))
                .foregroundStyle(accentColor)
        }
    }

    @ViewBuilder
    private func previewSection(_ section: ResumeSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title.uppercased())
                .font(.system(size: 8, weight: .bold, design: fontDesign))
                .foregroundStyle(accentColor)
                .kerning(0.8)

            Rectangle()
                .fill(accentColor.opacity(0.3))
                .frame(height: 1)

            ForEach(section.lines.prefix(2), id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, design: fontDesign))
                    .foregroundStyle(.black.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }
}
