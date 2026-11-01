import SwiftUI
import AppKit
struct AttachmentStrip: View {
    let attachments: [Attachment]
    var remove: ((UUID) -> Void)? = nil
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 8) {
                        if let data = attachment.imageData, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 48, height: 48)
                        } else { Image(systemName: "doc.text").frame(width: 32, height: 48).foregroundStyle(.orange) }
                        Text(attachment.name).font(.caption).lineLimit(1).frame(maxWidth: 160)
                        if let remove {
                            Button { remove(attachment.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).accessibilityLabel("Remove " + attachment.name)
                        }
                    }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
