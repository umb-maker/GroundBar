import AppKit

enum Assets {
    /// Start button image: from the app bundle, or from the repository's Resources folder for `swift run` / debug builds.
    static let startIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "StartIcon", withExtension: "png"), let image = NSImage(contentsOf: url) {
            return image
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: repo.appendingPathComponent("Resources/StartIcon.png"))
    }()
}
