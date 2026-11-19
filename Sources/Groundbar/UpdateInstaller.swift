import AppKit
import CryptoKit

/// Installs a release in place: downloads `Groundbar.zip`, checks it against the SHA-256 that GitHub
/// computed for the asset, unpacks it, checks the app inside, swaps it for the running copy and
/// relaunches. Any failure leaves the installed app untouched.
enum UpdateInstaller {
    enum Failure: Error { case download, checksum, archive, bundle, signature }

    /// False when the running copy cannot be replaced: a folder the user can't write to, or a copy macOS
    /// runs from a randomised read-only location (an app opened from Downloads without moving it).
    static var canReplace: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app" && !app.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Downloads and checks the release, off the main thread. Returns the unpacked app.
    nonisolated static func prepare(asset: URL, sha256: String, version: String, bundleID: String) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: asset)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("GroundbarUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("Groundbar.zip")
        try fm.moveItem(at: file, to: zip)

        let digest = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256.lowercased() else { throw Failure.checksum }
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]) else { throw Failure.archive }

        let app = dir.appendingPathComponent("Groundbar.app")
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == bundleID,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else { throw Failure.bundle }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else { throw Failure.signature }
        return app
    }

    /// Puts `app` where the running copy is, then quits; a small shell waits for the exit and reopens it.
    @MainActor
    static func replaceAndRelaunch(with app: URL) throws {
        let current = Bundle.main.bundleURL
        _ = try FileManager.default.replaceItemAt(current, withItemAt: app)
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Paths and the pid go in as arguments, never into the script text.
        relaunch.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                              "sh", String(getpid()), current.path]
        try relaunch.run()
        NSApp.terminate(nil)
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
