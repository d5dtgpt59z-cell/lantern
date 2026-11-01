import Foundation
import AppKit
import CryptoKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let source = NSBitmapImageRep(data: try Data(contentsOf: root.appendingPathComponent("Pip-cutout.png")))!
let w=source.pixelsWide,h=source.pixelsHigh
func boundary(_ y:Double)->Double {
    if y < 0.15 { return 0.20 }
    if y < 0.30 { return 0.22 + (y-0.15)*1.20 }
    if y < 0.45 { return 0.40 - (y-0.30)*0.50 }
    if y < 0.62 { return 0.325 + (y-0.45)*0.09 }
    if y < 0.78 { return 0.34 + (y-0.62)*0.32 }
    return 0.40
}
func layer(_ region:Int)->NSImage {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:w*4,bitsPerPixel:32)!
    let src=source.bitmapData!,dst=rep.bitmapData!
    for y in 0..<h { for x in 0..<w {
        let nx=Double(x)/Double(w),ny=Double(y)/Double(h),b=boundary(ny)
        let keep = region==0 ? nx >= b-0.012 && nx <= 1-b+0.012 : (region==1 ? nx < b+0.006 : nx > 1-b-0.006)
        let a=y*source.bytesPerRow+x*4,d=y*rep.bytesPerRow+x*4
        if keep { for c in 0..<4 {dst[d+c]=src[a+c]} }
    }}
    let image=NSImage(size:NSSize(width:w,height:h));image.addRepresentation(rep);return image
}
let body=layer(0),left=layer(1),right=layer(2)
let states=["idle","working","happy","waiting"]
let directory=root.appendingPathComponent("Pip-frames")
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
let cell=256.0
let atlas=NSImage(size:NSSize(width:cell*8,height:cell*4))
var rendered:[[NSImage]]=[]
func draw(_ image:NSImage, pivot:NSPoint, angle:Double, scaleX:Double=1, scaleY:Double=1, shift:Double=0) {
    NSGraphicsContext.saveGraphicsState()
    let t=NSAffineTransform();t.translateX(by:pivot.x,yBy:pivot.y+shift);t.rotate(byDegrees:angle);t.scaleX(by:scaleX,yBy:scaleY);t.translateX(by:-pivot.x,yBy:-pivot.y);t.concat()
    image.draw(in:NSRect(x:16,y:16,width:224,height:224))
    NSGraphicsContext.restoreGraphicsState()
}
for state in states {
    var frames:[NSImage]=[];var hashes=Set<String>()
    for i in 0..<8 {
        let phase=Double(i)*2*Double.pi/8
        let working=state=="working",happy=state=="happy",waiting=state=="waiting"
        let wingAngle=sin(phase)*(working ? 15 : happy ? 11 : 3) + cos(phase)*0.6
        let fold=working ? 0.80+0.18*cos(phase) : 1.0
        let lift=happy ? (1-cos(phase))*4 : working ? sin(phase)*2 : sin(phase)*0.8
        let frame=NSImage(size:NSSize(width:cell,height:cell));frame.lockFocus()
        NSColor.clear.setFill();NSRect(x:0,y:0,width:cell,height:cell).fill(using:.copy)
        draw(left,pivot:NSPoint(x:105,y:128),angle:wingAngle,scaleX:fold,shift:lift)
        draw(right,pivot:NSPoint(x:151,y:128),angle:-wingAngle,scaleX:fold,shift:lift)
        draw(body,pivot:NSPoint(x:128,y:128),angle:waiting ? sin(phase)*3 : cos(phase)*0.5,scaleX:1+sin(phase)*0.006,scaleY:1-sin(phase)*0.006,shift:lift)
        frame.unlockFocus()
        let rep=NSBitmapImageRep(data:frame.tiffRepresentation!)!
        let data=rep.representation(using:.png,properties:[:])!
        let name=String(format:"%@-%02d.png",state,i)
        try data.write(to:directory.appendingPathComponent(name))
        hashes.insert(SHA256.hash(data:data).description)
        frames.append(frame)
    }
    guard hashes.count==8 else { fatalError("Duplicate poses in \(state)") }
    print("\(state): 8 unique transparent frames")
    rendered.append(frames)
}
atlas.lockFocus()
NSColor.clear.setFill();NSRect(x:0,y:0,width:cell*8,height:cell*4).fill(using:.copy)
for row in 0..<4 {for column in 0..<8 {rendered[row][column].draw(in:NSRect(x:Double(column)*cell,y:Double(3-row)*cell,width:cell,height:cell))}}
atlas.unlockFocus()
try NSBitmapImageRep(data:atlas.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("Pip-atlas.png"))
let manifest:[String:Any] = ["name":"Pip","frameWidth":256,"frameHeight":256,"columns":8,"rows":4,"anchor":[128,128],"alpha":true,"states":states,"fps":["idle":6,"working":14,"happy":10,"waiting":6],"provenance":"Deterministic layered poses from the approved Pip cutout; shared canvas, scale and anchor."]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("Pip-animation.json"))
