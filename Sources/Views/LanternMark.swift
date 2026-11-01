import SwiftUI
import AppKit
struct LanternMark: View {
    var size: CGFloat = 88
    private static let artwork = Bundle.main.url(forResource: "PAIGE-mark", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        Group {
            if let artwork = Self.artwork { Image(nsImage: artwork).resizable().scaledToFit() }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct PaigeBrand: View {
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: compact ? 10 : 16) {
                LanternMark(size: compact ? 36 : 52)
                Text("PAIGE").font(.system(size: compact ? 22 : 28, weight: .medium)).tracking(compact ? 3 : 5)
            }
            Text("Personal Autonomous Intelligence\n& Generative Engine")
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .tracking(compact ? 0.35 : 0.7).lineSpacing(3)
                .foregroundStyle(Color(red: 0.77, green: 0.71, blue: 0.72))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Personal Autonomous Intelligence & Generative Engine")
        }
    }
}
struct SparkCard: View {
    var title: String
    var subtitle: String
    var symbol: String
    var color: Color
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 19,weight: .medium)).foregroundStyle(color).frame(width: 42,height: 42).background(color.opacity(0.14),in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading,spacing: 5) { Text(title).font(.system(size: 14,weight: .semibold)); Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10,weight: .bold)).foregroundStyle(color.opacity(0.8))
            }.padding(16).frame(maxWidth: .infinity,alignment: .leading).background(color.opacity(hovering ? 0.12 : 0.045),in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius:16).stroke(color.opacity(hovering ? 0.45 : 0.17),lineWidth:1))
        }.buttonStyle(.plain).onHover { hovering = $0 }.scaleEffect(hovering ? 1.015 : 1).animation(.easeOut(duration: 0.16),value: hovering)
    }
}
