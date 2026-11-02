import Foundation

/// Minimal diagnostics in ~/Library/Logs/OmniBar.log: start-up, permission state and errors only.
/// Never log window titles, file names or other user content. The file is capped at 1 MB and rotated
/// to OmniBar.old.log, so it never grows without limit.
enum Log {
    private static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
    private static let url = dir.appendingPathComponent("OmniBar.log")
    private static let old = dir.appendingPathComponent("OmniBar.old.log")
    private static let maxBytes = 1_000_000

    static func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
