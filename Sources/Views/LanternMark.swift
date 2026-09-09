import SwiftUI
struct LanternMark: View {
    var size: CGFloat = 88
    var body: some View {
        ZStack {
            Circle().fill(Color.orange.opacity(0.10)).frame(width: 104, height: 104)
            RoundedRectangle(cornerRadius: 12).stroke(Color.orange, lineWidth: 4).frame(width: 27, height: 23).offset(y: -38)
            RoundedRectangle(cornerRadius: 6).fill(Color.orange).frame(width: 63, height: 10).offset(y: -23)
            RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color(red: 1, green: 0.83, blue: 0.46), Color(red: 1, green: 0.55, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 56, height: 55).shadow(color: .orange.opacity(0.28), radius: 18)
            HStack(spacing: 14) { Capsule().frame(width: 4,height: 7); Capsule().frame(width: 4,height: 7) }.foregroundStyle(Color(red: 0.24, green: 0.15, blue: 0.16)).offset(y: -3)
            Text("⌣").font(.system(size: 21,weight: .bold)).foregroundStyle(Color(red: 0.38,green: 0.20,blue: 0.16)).offset(y: 9)
            RoundedRectangle(cornerRadius: 4).fill(Color.orange).frame(width: 64,height: 8).offset(y: 31)
        }.frame(width: 110,height: 110).scaleEffect(size / 110).frame(width: size,height: size).accessibilityHidden(true)
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
