import SwiftUI
import AppKit

struct PlushPip: View {
    let time: Double
    let working: Bool
    let happy: Bool
    let waiting: Bool
    let gaze: CGSize
    private static let frames: [String: [NSImage]] = {
        var result: [String: [NSImage]] = [:]
        for state in ["idle", "working", "happy", "waiting"] {
            result[state] = (0..<8).compactMap { index in
                Bundle.main.url(forResource: String(format: "%@-%02d", state, index), withExtension: "png", subdirectory: "Pip-frames").flatMap { NSImage(contentsOf: $0) }
            }
        }
        return result
    }()
    var body: some View {
        let state = happy ? "happy" : waiting ? "waiting" : working ? "working" : "idle"
        let fps = happy ? 10.0 : working && !waiting ? 14.0 : 6.0
        if let frames = Self.frames[state], frames.count == 8 {
            let index = Int(floor(time * fps)) % frames.count
            ZStack {
                Image(nsImage: frames[index]).resizable().interpolation(.high).scaledToFit()
                    .rotationEffect(.degrees(Double(gaze.width)*0.6))
                if happy { Text("♥").font(.system(size:19)).foregroundStyle(.pink).offset(x:48,y:-52) }
                if waiting { Text("?").font(.system(size:20,weight:.bold,design:.rounded)).foregroundStyle(.orange).offset(x:48,y:-52) }
            }
        } else {
            MothDrawing(time:time,working:working,happy:happy,waiting:waiting,gaze:gaze)
        }
    }
}
