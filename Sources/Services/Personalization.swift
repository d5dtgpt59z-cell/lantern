import AppKit
import SwiftUI

enum Personalization {
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lantern") }
    static var persona: String { (try? String(contentsOf: directory.appendingPathComponent("persona.md"), encoding: .utf8)) ?? "" }
    static let background: NSImage? = {
        let custom = directory.appendingPathComponent("background.jpg")
        if let image = NSImage(contentsOf: custom) { return image }
        return Bundle.main.url(forResource: "PAIGE-background", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }()
}
struct PaigeBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let photo = Personalization.background {
                    Image(nsImage: photo).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing).clipped()
                    Color.black.opacity(0.30)
                    LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.45), .black.opacity(0.12)], startPoint: .leading, endPoint: .trailing)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
