import SwiftUI
import AppKit

/// All layout uses an 8-point grid. Drag coordinates stay fixed while the pet moves, avoiding feedback jitter.
struct PetCompanion: View {
    @ObservedObject var store: ChatStore
    @Binding var visible: Bool
    var pointer: CGPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pipPositionX") private var savedX = -1.0
    @AppStorage("pipPositionY") private var savedY = -1.0
    @State private var position: CGPoint?
    @State private var dragOrigin: CGPoint?
    @State private var delightedUntil = Date.distantPast
    private var mood: String {
        if store.approval != nil { return "Your call!" }
        if store.downloading != nil { return "Getting things ready" }
        if store.error != nil { return "A little help needed" }
        if store.generating { return "On it!" }
        if store.error != nil { return "We’ll figure it out" }
        return "Keeping watch"
    }
    var body: some View {
        GeometryReader { geometry in
            let home = CGPoint(x: geometry.size.width - 88, y: geometry.size.height - 224)
            let saved = savedX >= 0 && savedY >= 0 ? CGPoint(x: savedX * geometry.size.width, y: savedY * geometry.size.height) : home
            let point = bounded(position ?? saved, in: geometry.size)
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion || scenePhase != .active)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let happy = timeline.date < delightedUntil
                let working = (store.generating || store.downloading != nil) && store.approval == nil
                let bounce = reduceMotion ? 0 : sin(time * (happy ? 9 : working ? 5 : 2)) * (happy ? 9 : working ? 4 : 2)
                VStack(spacing: -20) {
                    PlushPip(time: time, working: working, happy: happy, waiting: store.approval != nil, gaze: CGSize(width: max(-2, min(2, (pointer.x - point.x) / 90)), height: max(-1.5, min(1.5, (pointer.y - point.y) / 100))))
                        .frame(width: 144, height: 144).offset(y: bounce)
                    Text("Pip · " + (happy ? "Hi, friend!" : mood)).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).background(.regularMaterial, in: Capsule())
                }.frame(width: 168, height: 144)
            }
            .scaleEffect(dragOrigin == nil ? 1 : 1.06)
            .shadow(color: .black.opacity(dragOrigin == nil ? 0 : 0.22), radius: 10, y: 7)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dragOrigin != nil)
            .contentShape(RoundedRectangle(cornerRadius: 32))
            .onHover { inside in if inside { (dragOrigin == nil ? NSCursor.openHand : NSCursor.closedHand).set() } else { NSCursor.arrow.set() } }
            .onTapGesture { delightedUntil = Date().addingTimeInterval(2) }
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("PipPlayground")).onChanged { value in
                if dragOrigin == nil { dragOrigin = point; NSCursor.closedHand.set() }
                let origin = dragOrigin ?? point
                position = bounded(CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height), in: geometry.size)
            }.onEnded { _ in
                let p = position ?? point
                let snapped = bounded(CGPoint(x: (p.x / 8).rounded() * 8, y: (p.y / 8).rounded() * 8), in: geometry.size)
                withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                    position = snapped; dragOrigin = nil
                }
                savedX = snapped.x / max(1, geometry.size.width)
                savedY = snapped.y / max(1, geometry.size.height)
                NSCursor.openHand.set()
            })
            .contextMenu {
                Button("Hide Pip") { NSCursor.arrow.set(); visible = false }
                Button("Back to perch") {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { position = nil; savedX = -1; savedY = -1 }
                }
            }
            .help("Pip the moth. Click to say hello, drag to move, or right-click to hide.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pip the moth: " + mood)
            .accessibilityAddTraits(.isButton)
            .position(point)
            .onChange(of: geometry.size) { _, _ in if dragOrigin == nil { position = nil } }
        }.coordinateSpace(name: "PipPlayground")
        .onDisappear { NSCursor.arrow.set() }
    }
    private func bounded(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(88, p.x), max(88, size.width - 88)), y: min(max(88, p.y), max(88, size.height - 88)))
    }
}

struct MothDrawing: View {
    let time: Double
    let working: Bool
    let happy: Bool
    let waiting: Bool
    let gaze: CGSize
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 88
            context.scaleBy(x: scale, y: scale)
            let flap = sin(time * (working || happy ? 16 : 3)) * (working || happy ? 0.25 : 0.07)
            for side in [-1.0, 1.0] {
                var wing = context
                wing.translateBy(x: 44, y: 44)
                wing.rotate(by: .radians(side * flap))
                let upper = CGRect(x: side < 0 ? -37 : 3, y: -27, width: 34, height: 43)
                wing.fill(Path(ellipseIn: upper), with: .linearGradient(Gradient(colors: [Color(red: 0.85, green: 0.78, blue: 1), Color(red: 0.62, green: 0.54, blue: 0.84)]), startPoint: CGPoint(x: 0,y: -30), endPoint: CGPoint(x: 0,y: 18)))
                wing.fill(Path(ellipseIn: CGRect(x: side < 0 ? -29 : 3,y: 0,width: 26,height: 29)),with: .color(Color(red: 0.74,green: 0.63,blue: 0.93)))
                wing.fill(Path(ellipseIn: CGRect(x: side < 0 ? -28 : 13,y: -14,width: 13,height: 16)),with: .color(Color(red: 1,green: 0.84,blue: 0.53)))
                wing.fill(Path(ellipseIn: CGRect(x: side < 0 ? -23 : 17,y: -9,width: 5,height: 6)),with: .color(Color(red: 0.46,green: 0.34,blue: 0.64)))
                wing.fill(Path(ellipseIn: CGRect(x: side < 0 ? -22 : 12,y: 12,width: 8,height: 6)),with: .color(Color.white.opacity(0.5)))
            }
            context.fill(Path(ellipseIn: CGRect(x: 33,y: 31,width: 22,height: 39)),with: .linearGradient(Gradient(colors: [Color(red: 1,green: 0.90,blue: 0.65),Color(red: 1,green: 0.70,blue: 0.33)]),startPoint: CGPoint(x:44,y:31),endPoint:CGPoint(x:44,y:70)))
            context.fill(Path(ellipseIn: CGRect(x: 28,y: 23,width: 32,height: 29)),with: .color(Color(red: 1,green: 0.92,blue: 0.74)))
            for side in [-1.0,1.0] {
                var antenna = Path();antenna.move(to:CGPoint(x:44+side*7,y:28));antenna.addQuadCurve(to:CGPoint(x:44+side*15,y:12),control:CGPoint(x:44+side*8,y:10))
                context.stroke(antenna,with:.color(Color(red:0.84,green:0.65,blue:0.36)),style:StrokeStyle(lineWidth:2,lineCap:.round))
                context.fill(Path(ellipseIn:CGRect(x:42+side*15,y:9,width:4,height:4)),with:.color(.orange))
            }
            let blink = time.truncatingRemainder(dividingBy: 5) < 0.15
            let eyeHeight: CGFloat = happy || blink ? 1.5 : 5
            for x in [37.0, 48.0] {
                context.fill(Path(roundedRect:CGRect(x:x+gaze.width,y:35+gaze.height,width:3.5,height:eyeHeight),cornerRadius:2),with:.color(Color(red:0.23,green:0.18,blue:0.28)))
            }
            context.fill(Path(ellipseIn:CGRect(x:31,y:40,width:6,height:3)),with:.color(.pink.opacity(0.35)))
            context.fill(Path(ellipseIn:CGRect(x:51,y:40,width:6,height:3)),with:.color(.pink.opacity(0.35)))
            var smile=Path();smile.move(to:CGPoint(x:41,y:42));smile.addQuadCurve(to:CGPoint(x:47,y:42),control:CGPoint(x:44,y:46))
            context.stroke(smile,with:.color(Color(red:0.37,green:0.23,blue:0.28)),style:StrokeStyle(lineWidth:1.5,lineCap:.round))
            if waiting { context.draw(Text("?").font(.system(size:17,weight:.bold,design:.rounded)).foregroundColor(.orange),at:CGPoint(x:74,y:14)) }
            if happy { context.draw(Text("♥").font(.system(size:13)).foregroundColor(.pink),at:CGPoint(x:72,y:9)) }
        }
    }
}
