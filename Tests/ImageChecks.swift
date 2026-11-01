import Foundation
import AppKit

/// Routing, persistence, and send-state checks. Does not start an engine or render an image.
@main struct ImageChecks {
    @MainActor static func main() throws {
        var failures: [String] = []
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures.append(label); print("FAIL: " + label) }
        }

        let directRequests = [
            "Draw me a red fox in a snowy forest",
            "Please draw a tiny robot watering flowers",
            "PAIGE, make an image of a mountain at sunrise",
            "Can you make a picture of a cat wearing a yellow raincoat?",
            "Could you please create a photorealistic portrait of an astronaut?",
            "Generate an uncensored image of a neon city at night",
            "Paint a watercolor of an old lighthouse",
            "A picture of a blue bicycle beside a lake",
            "Generate a watercolor image of a fox",
            "Make a black-and-white photograph of a city",
            "Make pictures of paper boats floating in a pond",
            "Create some luminous, intricate, otherworldly illustrations of a garden",
            "Generate a 1970s screen-printed poster of a lighthouse",
            "Make a hand-drawn, sepia-toned portrait of an explorer",
            "Please generate two playful editorial images of a coffee shop",
            "I want an image of a fox",
            "I'd like an image of a fox",
            "I’d like some surreal watercolor pictures of a floating library",
            "I would like a black-and-white photograph of a city",
            "An elaborate watercolor illustration of a fox"
        ]
        for text in directRequests {
            check(ImageRequest.parse(text)?.prompt == text, "image request preserves prompt: " + text)
        }
        check(ImageRequest.parse("  /image   a red fox  ")?.prompt == "a red fox", "explicit image command strips only command and surrounding whitespace")
        check(ImageRequest.parse("/IMAGE a red fox")?.prompt == "a red fox", "explicit image command accepts case variants")
        check(ImageRequest.parse("/image") == nil, "empty explicit image command has no prompt")
        check(ImageRequest.parse("/images a red fox") == nil, "other slash commands do not become image requests")
        check(ImageRequest.parse("\n \t ", imageMode: true) == nil, "image mode still requires a description")
        check(ImageRequest.parse("  a red fox  ", imageMode: true)?.prompt == "a red fox", "image toggle sends an ordinary description directly")
        check(ImageRequest.parse("a red fox") == nil, "ordinary description requires explicit image mode")

        let textRequests = [
            "Can you generate images?",
            "Can you draw images?",
            "Can you make an image?",
            "Do you support image generation?",
            "How do I generate an image locally?",
            "Write a prompt for an image of a fox",
            "Generate an image prompt for a mountain landscape",
            "Create an image generator app",
            "Create an image gallery in React",
            "Make a logo component in SwiftUI",
            "Render this Markdown as HTML",
            "Render this HTML page",
            "Draw up a project plan",
            "Draw a conclusion from these sales results",
            "Explain this picture",
            "Summarize my document",
            "Create a function that generates images of cats",
            "Generate a Python script to make a picture of a fox",
            "Make a reusable image component in SwiftUI",
            "Create a responsive photo gallery for my website",
            "Make an image-processing pipeline",
            "Generate a watercolor image prompt for a fox",
            "I want an image generator app",
            "I'd like an explanation of image generation",
            "I want instructions for generating an image of a fox",
            "Can you create watercolor images?",
            "Explain how image generation works",
            "Draw a line chart using SVG"
        ]
        for text in textRequests {
            check(ImageRequest.parse(text) == nil, "capability, code, or ordinary request stays in chat: " + text)
        }

        let legacyID = UUID()
        let legacyJSON = """
        {"id":"\(legacyID.uuidString)","role":"assistant","content":"An earlier answer"}
        """
        let legacy = try JSONDecoder().decode(Message.self, from: Data(legacyJSON.utf8))
        check(legacy.id == legacyID && legacy.content == "An earlier answer" && legacy.generatedImage == nil, "legacy messages decode without generated-image metadata")

        let record = GeneratedImage(fileName: "PAIGE-safe.png", prompt: "A red fox", model: "Local test model", width: 768, height: 768)
        let message = Message(role: "assistant", content: "Made on your Mac.", modelName: record.model, generatedImage: record)
        let encoded = try JSONEncoder().encode(message)
        let restored = try JSONDecoder().decode(Message.self, from: encoded)
        check(restored.generatedImage?.fileName == record.fileName && restored.generatedImage?.prompt == record.prompt && restored.generatedImage?.model == record.model && restored.generatedImage?.width == 768 && restored.generatedImage?.height == 768, "generated image metadata round-trips")
        check(restored.attachments == nil, "generated image does not become a chat attachment")
        let expectedDirectory = Personalization.directory.appendingPathComponent("Images", isDirectory: true).standardizedFileURL
        check(record.url?.deletingLastPathComponent().standardizedFileURL == expectedDirectory, "generated files resolve inside PAIGE Images directory")
        check(record.url?.lastPathComponent == "PAIGE-safe.png", "generated image preserves the file name")
        for fileName in ["", ".", "..", "../outside.png", "nested/image.png", "/tmp/outside.png", "image.png/", "Images/../outside.png", "file:///tmp/outside.png"] {
            let invalid = GeneratedImage(fileName: fileName, prompt: "", model: "", width: 1, height: 1)
            check(invalid.url == nil, "invalid generated path is rejected: " + fileName)
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paige-image-check-" + UUID().uuidString, isDirectory: true)
        let savedChatModel = UserDefaults.standard.object(forKey: "chatModel")
        defer {
            try? FileManager.default.removeItem(at: directory)
            if let savedChatModel { UserDefaults.standard.set(savedChatModel, forKey: "chatModel") }
            else { UserDefaults.standard.removeObject(forKey: "chatModel") }
        }
        let store = ChatStore(storageDirectory: directory)
        store.ready = false
        store.draft = "Draw a red fox"
        check(store.canSend, "direct image request sends while chat model is not ready")
        store.draft = "Explain a red fox's habitat"
        check(!store.canSend, "ordinary chat waits for chat-model readiness")
        store.imageMode = true
        store.draft = "A red fox beside a lake"
        check(store.canSend, "image toggle sends descriptions while chat model is not ready")
        store.draft = " \n "
        check(!store.canSend, "empty image description cannot send")
        store.draft = "A red fox beside a lake"
        store.generating = true
        check(!store.canSend, "busy generation prevents overlapping image request")
        store.generating = false
        store.switchingModel = true
        check(!store.canSend, "model switching prevents overlapping image request")
        store.switchingModel = false
        store.imageMode = false
        store.attachments = [Attachment(name: "note.txt", text: "Test attachment")]
        store.draft = "Draw a red fox"
        check(!store.canSend, "attachments do not bypass chat-model readiness")
        store.ready = true
        store.draft = "Summarize this note"
        check(store.canSend, "ready chat still accepts ordinary attachments")

        // A text-only model must reject photo input synchronously, before a send clears
        // the draft, consumes attachments, or adds messages to the saved conversation.
        let photoURL = directory.appendingPathComponent("photo.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
        try bitmap.representation(using: .png, properties: [:])!.write(to: photoURL)
        check(try Attachment.read(photoURL).imageData != nil, "photo fixture is recognized as an image attachment")
        let documentURL = directory.appendingPathComponent("document.txt")
        try "A document the text model can read.".write(to: documentURL, atomically: true, encoding: .utf8)
        let existingAttachmentIDs = store.attachments.map(\.id)
        let originalDraft = store.draft
        let originalMessageCount = store.current!.messages.count
        store.addAttachments([photoURL])
        check(store.error == ChatStore.unsupportedPhotoMessage, "adding a photo explains text-only limitation and drawing capability")
        check(store.attachments.map(\.id) == existingAttachmentIDs && store.draft == originalDraft && store.current!.messages.count == originalMessageCount, "rejected photo selection preserves attachments, draft, and messages")
        store.error = nil
        store.addAttachments([documentURL, photoURL])
        check(store.error == ChatStore.unsupportedPhotoMessage && store.attachments.map(\.id) == existingAttachmentIDs, "mixed document and photo selection rejects atomically")
        let injectedPhoto = try Attachment.read(photoURL)
        store.attachments.append(injectedPhoto)
        let pendingAttachmentIDs = store.attachments.map(\.id)
        store.error = nil
        store.send()
        check(store.error == ChatStore.unsupportedPhotoMessage, "send rejects an existing photo attachment before inference")
        check(!store.generating && store.draft == originalDraft && store.attachments.map(\.id) == pendingAttachmentIDs && store.current!.messages.count == originalMessageCount, "rejected send leaves draft, attachments, and conversation untouched")
        store.attachments = []
        store.error = nil
        store.addAttachments([documentURL])
        check(store.error == nil && store.attachments.count == 1 && store.attachments[0].text == "A document the text model can read." && store.canSend, "text-only model still accepts and can send document attachments")
        store.attachments = []
        store.draft = "Hello"
        check(store.canSend, "ready chat still accepts text")
        store.draft = ""
        check(!store.canSend, "empty ordinary chat cannot send")

        store.conversations[0].messages.append(message)
        store.save()
        let reopened = ChatStore(storageDirectory: directory)
        check(reopened.current?.messages.last?.generatedImage?.fileName == record.fileName, "generated metadata survives conversation save and reopen")

        if !failures.isEmpty {
            throw NSError(domain: "PAIGEImageChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(failures.count) of \(checks) image integration checks failed."])
        }
        print("PASS: \(checks) image routing, legacy decoding, metadata, path, readiness, and persistence checks; no model loaded")
    }
}
