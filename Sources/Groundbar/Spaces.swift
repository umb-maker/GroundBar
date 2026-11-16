import AppKit

// Accessibility lists only the windows on the Space in view. An app whose windows are all on another
// desktop, or in full screen (a Space of its own), would look as if it had none. The window server knows
// which Space each window is on; AppKit has no public call for it, so these two are private
// CoreGraphics functions. If they ever stop answering, the result is empty and Groundbar behaves as
// before: it just misses windows on other Spaces.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray?
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray?

enum OtherSpaces {
    /// For each app, the frames (global, top-left origin) of its normal windows that sit on a Space not
    /// in view on any display. Closed windows an app keeps around belong to no Space and are left out.
    /// Safe on any thread.
    static func windows() -> [pid_t: [CGRect]] {
        let connection = CGSMainConnectionID()
        let displays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] ?? []
        let inView = Set(displays.compactMap { ($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int })
        // Without the list of Spaces in view nothing can be told apart: report nothing.
        guard !inView.isEmpty else { return [:] }

        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [pid_t: [CGRect]] = [:]
        for w in all {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowIsOnscreen as String] as? Bool) != true,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  // Real windows, not the small helper windows many apps keep off screen.
                  frame.width >= 200, frame.height >= 200 else { continue }
            let spaces = CGSCopySpacesForWindows(connection, 7, [id] as CFArray) as? [Int] ?? []
            if !spaces.isEmpty, inView.isDisjoint(with: spaces) { result[pid, default: []].append(frame) }
        }
        return result
    }
}
