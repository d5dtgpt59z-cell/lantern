# Sign and distribute Lantern

Lantern targets Apple Silicon Macs with macOS 15+ and 16 GB or more memory.
The repository includes `Lantern.xcodeproj`; XcodeGen is only needed when editing `project.yml`.

1. Open `Lantern.xcodeproj` in Xcode.
2. Select the **Lantern** target → **Signing & Capabilities**. Select your Apple Developer team. Keep Hardened Runtime enabled. This direct-download app is not configured for the Mac App Store sandbox.
3. Select **Any Mac (Apple Silicon)**, then **Product → Archive**.
4. In Organizer, distribute using **Developer ID**, with notarization. A paid Apple Developer membership and a Developer ID Application certificate are needed for normal outside-the-store distribution; a local development signature alone is not notarization.
5. Export the notarized `.app`. Run `./script/package_dmg.sh /path/to/exported/Lantern.app` to create a drag-to-Applications disk image.
6. Notarize the final DMG with your own configured notarytool keychain profile, then staple it before uploading to GitHub Releases. Keep credentials outside this repository.

The Xcode build phase embeds the pinned Ollama engine and native command helper, signing nested Mach-O binaries with the selected signing identity before Xcode signs the app. The initial source build downloads the engine from the official Ollama release and verifies its SHA-256. Model weights are downloaded by users inside Lantern; they are not bundled.

`./script/build_and_run.sh --build` and `./script/package_dmg.sh` produce a local ad-hoc-signed test build. That DMG is **not a notarized public release**.

Before publishing, test the signed build on a separate supported Mac without Ollama or developer tools: install, first model download, pause/resume, offline chat, photo attachment, approved/declined project actions, quit/relaunch, and replacing the app with an update. Existing local chats live outside the application bundle.

Update checking is user-triggered and opens GitHub Releases. This release does not silently download or install updates.
