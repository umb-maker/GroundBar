import AppKit
import SwiftUI

/// Bitcoin price and history from the public CoinGecko API (no key needed), in euro.
@MainActor
final class CryptoTicker: ObservableObject {
    enum Range: Int, CaseIterable, Identifiable {
        case day = 1, week = 7, month = 30, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .day: "24 ore"
            case .week: "7 giorni"
            case .month: "30 giorni"
            case .year: "1 anno"
            }
        }
    }

    @Published private(set) var price: Double?
    @Published private(set) var change24h: Double?
    @Published private(set) var sparkline: [Double] = []
    @Published private(set) var updated: Date?
    @Published private(set) var failed = false
    @Published private(set) var history: [Range: [Double]] = [:]

    private var timer: Timer?
    private static let base = "https://api.coingecko.com/api/v3"

    /// Last good values, shown at launch and kept when CoinGecko rate-limits a request.
    private struct Cache: Codable {
        let price: Double
        let change: Double?
        let sparkline: [Double]
        let updated: Date
    }
    private static let cacheKey = "btcCache"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey), let c = try? JSONDecoder().decode(Cache.self, from: data) {
            price = c.price
            change24h = c.change
            sparkline = c.sparkline
            history[.day] = c.sparkline
            updated = c.updated
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        Task { @MainActor in
            async let summary = Self.json("\(Self.base)/simple/price?ids=bitcoin&vs_currencies=eur&include_24hr_change=true")
            async let chart = Self.prices(days: 1)
            let (s, c) = await (summary, chart)
            if let btc = (s as? [String: Any])?["bitcoin"] as? [String: Any], let eur = btc["eur"] as? Double {
                price = eur
                change24h = btc["eur_24h_change"] as? Double
                updated = Date()
                failed = false
            } else {
                failed = price == nil
                // Usually a rate limit (HTTP 429): try again soon instead of waiting for the next tick.
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.refresh() }
            }
            if !c.isEmpty {
                sparkline = c
                history[.day] = c
            }
            if let price, let updated {
                let cache = Cache(price: price, change: change24h, sparkline: sparkline, updated: updated)
                if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
            }
        }
    }

    /// Loads the chart for a range (cached for the session, refreshed on every open of the flyout).
    func load(_ range: Range) {
        Task { @MainActor in
            let points = await Self.prices(days: range.rawValue)
            if !points.isEmpty { history[range] = points }
        }
    }

    private static func prices(days: Int) async -> [Double] {
        let obj = await json("\(base)/coins/bitcoin/market_chart?vs_currency=eur&days=\(days)")
        let rows = (obj as? [String: Any])?["prices"] as? [[Double]] ?? []
        return rows.compactMap { $0.count == 2 ? $0[1] : nil }
    }

    private static func json(_ url: String) async -> Any? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func euro(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.currency(code: "EUR").precision(.fractionLength(decimals)))
    }

    static func percent(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + (value / 100).formatted(.percent.precision(.fractionLength(2)))
    }
}

/// Line chart with a soft fill, scaled to the data's own min/max.
struct Sparkline: View {
    let points: [Double]
    let color: Color
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { g in
            if points.count > 1, let lo = points.min(), let hi = points.max() {
                let span = max(hi - lo, 0.0001)
                let step = g.size.width / CGFloat(points.count - 1)
                let pts = points.enumerated().map { i, v in
                    CGPoint(x: CGFloat(i) * step, y: g.size.height * (1 - CGFloat((v - lo) / span)))
                }
                let line = Path { p in p.addLines(pts) }
                let area = Path { p in
                    p.move(to: CGPoint(x: 0, y: g.size.height))
                    p.addLines(pts)
                    p.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
                    p.closeSubpath()
                }
                area.fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                line.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private func trendColor(_ change: Double?) -> Color {
    guard let change else { return .gray }
    return change >= 0 ? Color(red: 0.13, green: 0.70, blue: 0.36) : Color(red: 0.91, green: 0.26, blue: 0.24)
}

/// Bar widget: sparkline, price and 24h change.
struct CryptoWidget: View {
    @ObservedObject var ticker: CryptoTicker
    @Local private var frame: CGRect = .zero
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        let color = trendColor(ticker.change24h)
        Button {
            let r = TaskbarController.shared.screenRect(fromBar: frame)
            TaskbarController.shared.toggleFlyout("btc", anchor: .left(r.minX), size: CGSize(width: 380, height: 340)) {
                CryptoFlyout(ticker: ticker)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 20)).foregroundStyle(Color.orange)
                if !ticker.sparkline.isEmpty {
                    Sparkline(points: ticker.sparkline, color: color, lineWidth: 1.2).frame(width: 46, height: 22)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(ticker.price.map { CryptoTicker.euro($0) } ?? (ticker.failed ? "Non disponibile" : "BTC…"))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(f.text)
                    if let change = ticker.change24h {
                        Text(CryptoTicker.percent(change)).font(.system(size: 11)).foregroundStyle(color)
                    }
                }
                .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
        }
        .buttonStyle(FluentButtonStyle())
        .background(GeometryReader { g in
            Color.clear.onAppear { frame = g.frame(in: .global) }.onChange(of: g.frame(in: .global)) { _, n in frame = n }
        })
        .help("Bitcoin – andamento 24 ore (fonte: CoinGecko)")
    }
}

/// Flyout with a larger chart and selectable range.
struct CryptoFlyout: View {
    @ObservedObject var ticker: CryptoTicker
    @Local private var range: CryptoTicker.Range = .day
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        let points = ticker.history[range] ?? []
        let change = range == .day ? ticker.change24h : points.first.flatMap { first in points.last.map { ($0 - first) / first * 100 } }
        let color = trendColor(change)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 28)).foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bitcoin").font(.system(size: 13, weight: .semibold))
                    Text("BTC · EUR").font(.system(size: 11)).foregroundStyle(f.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(ticker.price.map { CryptoTicker.euro($0) } ?? "—").font(.system(size: 20, weight: .semibold))
                    if let change { Text(CryptoTicker.percent(change) + " · " + range.label).font(.system(size: 11)).foregroundStyle(color) }
                }
                .monospacedDigit()
            }

            HStack(spacing: 4) {
                ForEach(CryptoTicker.Range.allCases) { r in
                    Button { range = r; ticker.load(r) } label: {
                        Text(r.label).font(.system(size: 11)).padding(.horizontal, 10).frame(height: 24)
                            .foregroundStyle(range == r ? f.onAccent : f.text)
                            .background(RoundedRectangle(cornerRadius: 4).fill(range == r ? f.accent : f.cardTint))
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack {
                if points.count > 1 {
                    Sparkline(points: points, color: color, lineWidth: 2)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 150)

            HStack {
                if let lo = points.min(), let hi = points.max() {
                    Text("Min \(CryptoTicker.euro(lo))")
                    Spacer()
                    Text("Max \(CryptoTicker.euro(hi))")
                }
            }
            .font(.system(size: 11)).foregroundStyle(f.secondary).monospacedDigit()

            HStack {
                Text(ticker.updated.map { "Aggiornato alle \($0.formatted(date: .omitted, time: .shortened)) · CoinGecko" } ?? "CoinGecko")
                    .font(.system(size: 10)).foregroundStyle(f.secondary)
                Spacer()
                Button("Apri su CoinGecko") {
                    TaskbarController.shared.closeFlyout()
                    TaskbarController.openSettings("https://www.coingecko.com/it/monete/bitcoin")
                }
                .buttonStyle(.link).font(.system(size: 11))
            }
        }
        .foregroundStyle(f.text)
        .padding(16)
        .flyoutChrome()
        .onAppear { ticker.refresh(); ticker.load(range) }
    }
}
