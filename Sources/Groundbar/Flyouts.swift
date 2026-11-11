import AppKit
import SwiftUI

// MARK: - Quick settings (tray)

struct QuickSettingsView: View {
    @ObservedObject var status: SystemStatus
    @ObservedObject var model: TaskbarModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Tile(symbol: status.networkSymbol, label: status.network == .offline ? L("Offline") : L("Network"), on: status.network != .offline) {
                    TaskbarController.openSettings("x-apple.systempreferences:com.apple.wifi-settings-extension")
                }
                // Groundbar does not know the Bluetooth state: a neutral tile, not a lit one.
                Tile(symbol: "dot.radiowaves.left.and.right", label: "Bluetooth", on: false) {
                    TaskbarController.openSettings("x-apple.systempreferences:com.apple.BluetoothSettings")
                }
                Tile(symbol: model.theme == .santa ? "sparkles" : model.theme == .christmas ? "snowflake" : model.theme == .halloween ? "moon.stars.fill" : model.theme == .dark ? "moon.fill" : model.theme == .glass ? "drop.fill" : "sun.max.fill", label: L("Theme: \(model.theme.label)"), on: false) {
                    let all = ThemeMode.allCases
                    model.theme = all[(all.firstIndex(of: model.theme)! + 1) % all.count]
                }
            }
            .padding(16)

            HStack(spacing: 10) {
                Button { status.setMuted(!status.muted) } label: {
                    Image(systemName: status.volumeSymbol).frame(width: 28, height: 28)
                }
                .buttonStyle(FluentButtonStyle())
                Slider(value: Binding(get: { Double(status.volume) }, set: { status.setVolume(Float($0)) }), in: 0...1)
                    .tint(f.accent)
                Text("\(Int((status.volume * 100).rounded()))").font(.system(size: 12)).frame(width: 28)
            }
            .foregroundStyle(f.text)
            .padding(.horizontal, 16)

            Spacer(minLength: 8)
            Rectangle().fill(f.stroke).frame(height: 1)
            HStack {
                if let level = status.batteryLevel {
                    Image(systemName: status.batterySymbol)
                    Text(status.charging ? L("\(level)% · charging") : "\(level)%").font(.system(size: 12))
                }
                Spacer()
                Button { TaskbarController.openSettings("x-apple.systempreferences:") } label: {
                    Image(systemName: "gearshape").frame(width: 30, height: 30)
                }
                .buttonStyle(FluentButtonStyle())
                .help("System Settings")
            }
            .foregroundStyle(f.text)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(f.cardTint.opacity(0.5))
        }
        .flyoutChrome()
    }

    private struct Tile: View {
        let symbol: String
        let label: String
        let on: Bool
        let action: () -> Void
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let f = Fluent(scheme)
            VStack(spacing: 6) {
                Button(action: action) {
                    Image(systemName: symbol).font(.system(size: 15))
                        .foregroundStyle(on ? f.onAccent : f.text)
                        .frame(width: 96, height: 46)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? f.accent : f.cardTint))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(f.stroke))
                }
                .buttonStyle(.plain)
                Text(label).font(.system(size: 11)).foregroundStyle(f.text).lineLimit(1)
            }
        }
    }
}

// MARK: - Calendar (clock)

struct CalendarFlyout: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.date.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 30, weight: .light))
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).capitalized)
                        .font(.system(size: 13)).foregroundStyle(f.accent)
                }
            }
            .foregroundStyle(f.text)
            .padding(16)
            Rectangle().fill(f.stroke).frame(height: 1)
            MonthGrid().padding(.horizontal, 16).padding(.vertical, 12)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Open Calendar") { TaskbarController.openSettings("ical://") }
                    .buttonStyle(.link)
                    .padding(12)
            }
        }
        .flyoutChrome()
    }
}

/// Month view in the style of the Windows 11 clock flyout.
private struct MonthGrid: View {
    @Local private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @Environment(\.colorScheme) private var scheme

    private let cal = Calendar.current

    private var days: [Date] {
        let weekday = cal.component(.weekday, from: month)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: month)!
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    private var weekdaySymbols: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        let i = cal.firstWeekday - 1
        return Array(s[i...] + s[..<i])
    }

    var body: some View {
        let f = Fluent(scheme)
        VStack(spacing: 8) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.up").frame(width: 30, height: 28) }
                    .buttonStyle(FluentButtonStyle())
                Button { shift(1) } label: { Image(systemName: "chevron.down").frame(width: 30, height: 28) }
                    .buttonStyle(FluentButtonStyle())
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(weekdaySymbols.indices, id: \.self) { i in
                    Text(weekdaySymbols[i].uppercased()).font(.system(size: 12, weight: .semibold)).frame(height: 30)
                }
                ForEach(days, id: \.self) { day in
                    let today = cal.isDateInToday(day)
                    let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 13))
                        .foregroundStyle(today ? f.onAccent : inMonth ? f.text : f.secondary.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(today ? f.accent : Color.clear))
                }
            }
        }
        .foregroundStyle(f.text)
    }

    private func shift(_ months: Int) {
        month = cal.date(byAdding: .month, value: months, to: month)!
    }
}
