import AppKit
import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark, halloween, christmas, santa
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: L("System")
        case .light: L("Light")
        case .dark: L("Dark")
        case .halloween: L("Halloween 🎃")
        case .christmas: L("Christmas 🎄")
        case .santa: L("Santa 🎅")
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark, .halloween, .christmas, .santa: NSAppearance(named: .darkAqua)
        }
    }
}

/// Fluent (Windows 11) palette: light, dark, and seasonal variants of dark (Halloween, Christmas).
struct Fluent {
    /// Set by the model to the active theme; the bar is rebuilt on every theme change.
    nonisolated(unsafe) static var theme: ThemeMode = .system

    /// Colours of a seasonal theme.
    private struct Seasonal {
        let bar: Color, flyout: Color, accent: Color, onAccent: Color, highlight: Color, text: Color
    }

    private static let halloween = Seasonal(
        bar: Color(red: 0.09, green: 0.03, blue: 0.13).opacity(0.90),
        flyout: Color(red: 0.12, green: 0.05, blue: 0.16).opacity(0.94),
        accent: Color(red: 1.0, green: 0.52, blue: 0.05), onAccent: .black,
        highlight: Color(red: 1.0, green: 0.52, blue: 0.05),
        text: Color(red: 1.0, green: 0.94, blue: 0.86))

    private static let christmas = Seasonal(
        bar: Color(red: 0.03, green: 0.11, blue: 0.07).opacity(0.92),
        flyout: Color(red: 0.05, green: 0.14, blue: 0.09).opacity(0.95),
        accent: Color(red: 0.86, green: 0.16, blue: 0.20), onAccent: .white,
        highlight: Color(red: 0.96, green: 0.78, blue: 0.32),
        text: Color(red: 0.97, green: 0.98, blue: 1.0))

    private static let santa = Seasonal(
        bar: Color(red: 0.04, green: 0.06, blue: 0.16).opacity(0.92),
        flyout: Color(red: 0.06, green: 0.08, blue: 0.20).opacity(0.95),
        accent: Color(red: 0.86, green: 0.16, blue: 0.20), onAccent: .white,
        highlight: Color(red: 0.96, green: 0.78, blue: 0.32),
        text: Color(red: 0.97, green: 0.98, blue: 1.0))

    let dark: Bool
    private let seasonal: Seasonal?
    init(_ scheme: ColorScheme) {
        dark = scheme == .dark
        switch Fluent.theme {
        case .halloween: seasonal = Self.halloween
        case .christmas: seasonal = Self.christmas
        case .santa: seasonal = Self.santa
        default: seasonal = nil
        }
    }

    var barTint: Color {
        if let s = seasonal { return s.bar }
        return dark ? Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.78) : Color(red: 0.93, green: 0.94, blue: 0.96).opacity(0.80)
    }
    var flyoutTint: Color {
        if let s = seasonal { return s.flyout }
        return dark ? Color(red: 0.16, green: 0.16, blue: 0.17).opacity(0.86) : Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.88)
    }
    var cardTint: Color { seasonal.map { $0.highlight.opacity(0.08) } ?? (dark ? Color.white.opacity(0.06) : Color.white.opacity(0.70)) }
    var hover: Color { seasonal.map { $0.highlight.opacity(0.14) } ?? (dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)) }
    var activeBg: Color { seasonal.map { $0.highlight.opacity(0.12) } ?? (dark ? Color.white.opacity(0.06) : Color.white.opacity(0.65)) }
    var stroke: Color { seasonal.map { $0.highlight.opacity(0.30) } ?? (dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)) }
    var accent: Color { seasonal?.accent ?? (dark ? Color(red: 0.30, green: 0.76, blue: 1.0) : Color(red: 0.0, green: 0.40, blue: 0.75)) }
    var onAccent: Color { seasonal?.onAccent ?? (dark ? .black : .white) }
    var text: Color { seasonal?.text ?? (dark ? .white : Color(white: 0.1)) }
    var secondary: Color { seasonal.map { $0.text.opacity(0.6) } ?? (dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56)) }
    var field: Color { seasonal != nil ? Color.white.opacity(0.06) : dark ? Color.white.opacity(0.07) : Color.white.opacity(0.9) }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Background, border and corners shared by every flyout (Start, calendar, quick settings, previews).
struct FlyoutChrome: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 8

    func body(content: Content) -> some View {
        let f = Fluent(scheme)
        content
            .background(ZStack { VisualEffect(material: .popover); f.flyoutTint })
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(f.stroke, lineWidth: 1))
    }
}

/// Plain button with Fluent hover/pressed fill.
struct FluentButtonStyle: ButtonStyle {
    var radius: CGFloat = 4
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        FluentButtonBody(configuration: configuration, radius: radius, selected: selected)
    }

    private struct FluentButtonBody: View {
        let configuration: Configuration
        let radius: CGFloat
        let selected: Bool
        @Local private var hovering = false
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let f = Fluent(scheme)
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(selected ? f.activeBg : (hovering ? f.hover : Color.clear))
                )
                .opacity(configuration.isPressed ? 0.75 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    func flyoutChrome(radius: CGFloat = 8) -> some View { modifier(FlyoutChrome(radius: radius)) }
}

/// Drop-in for `@State`. In the macOS 27 SDK `@State` is a macro whose plugin ships only with Xcode,
/// so a Command Line Tools build stores view-local state in a `@StateObject` box instead.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) { _box = StateObject(wrappedValue: Box(wrappedValue)) }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> { $box.value }
}
