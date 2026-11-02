import Foundation

/// Localized text for places that take a plain `String` (SwiftUI string literals are localized on their own).
/// The English text is the key; translations live in Resources/<lang>.lproj/Localizable.strings.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}
