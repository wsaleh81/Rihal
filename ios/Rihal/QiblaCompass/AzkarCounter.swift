import SwiftUI
import UIKit

// MARK: - Saved counts, restarted by prayer time (same rules as the Android app)

/// Azkar counts are kept on the phone. Morning azkar start again at Fajr, evening at Asr, after-prayer at every prayer,
/// sleep at Isha; travel, Friday and all "more azkar" every day at Fajr.
final class AzkarStore: ObservableObject {
    static let shared = AzkarStore()

    @Published private(set) var counts: [String: Int] = [:]
    private var stamps: [String: Double] = [:]
    /// Opens a list from a notification tap: "morning", "evening", "afterPrayer" or "m:<index>" for a more-azkar section.
    @Published var openRequest: String? = nil
    /// Set by the Surat al-Kahf button: close the azkar screens and open the Mushaf.
    @Published var kahfRequest = 0
    /// Called when a whole set is finished or started again, so today's reminders can be rebuilt.
    var onSetChange: (() -> Void)?

    private let countsKey = "azkarCounts", stampsKey = "azkarStamps"

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: countsKey), let c = try? JSONDecoder().decode([String: Int].self, from: data) { counts = c }
        if let data = d.data(forKey: stampsKey), let s = try? JSONDecoder().decode([String: Double].self, from: data) { stamps = s }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(counts), forKey: countsKey)
        d.set(try? JSONEncoder().encode(stamps), forKey: stampsKey)
    }

    func n(_ id: String) -> Int { counts[id] ?? 0 }

    /// Adds `step` (±1) without going below 0 or above `max`. Returns true when this step finished the dhikr.
    @discardableResult
    func add(_ id: String, max: Int, step: Int = 1) -> Bool {
        let c = n(id), v = Swift.max(0, Swift.min(max, c + step))
        guard v != c else { return false }
        counts[id] = v == 0 ? nil : v
        save()
        let finished = v >= max && c < max
        if finished || (c >= max && v < max) { onSetChange?() }
        return finished
    }

    func reset(_ ids: [String]) {
        var ch = false
        for id in ids where counts[id] != nil { counts[id] = nil; ch = true }
        if ch { save(); onSetChange?() }
    }

    func done(_ items: [(id: String, times: Int)]) -> Int { items.filter { n($0.id) >= $0.times }.count }

    // Groups and the prayers that start them again
    static let resetRules: [(key: String, prayers: [Prayer])] = [
        ("morning", [.fajr]), ("evening", [.asr]), ("afterPrayer", [.fajr, .dhuhr, .asr, .maghrib, .isha]), ("sleep", [.isha]), ("daily", [.fajr])
    ]
    static func ids(for key: String) -> [String] {
        if key == "daily" { return AzkharData.items("travel").map(\.id) + MoreAzkar.groups.flatMap { $0.items.map(\.id) } }
        return AzkharData.items(key).map(\.id)
    }

    /// Last time (now or earlier) one of these prayers began.
    static func lastPrayer(_ names: [Prayer], place: Place, method: CalcMethod, hanafi: Bool, now: Date = Date()) -> Date? {
        PrayerCalculator.events(around: now, lat: place.lat, lon: place.lon, timeZone: place.timeZone, method: method, hanafi: hanafi)
            .all.filter { names.contains($0.prayer) && $0.date <= now }.last?.date
    }

    /// Clears a group once its prayer has come again. A small GPS move shifts prayer times by seconds: that keeps the counts.
    func sync(place: Place, method: CalcMethod, hanafi: Bool) {
        var ch = false
        for r in Self.resetRules {
            guard let st = Self.lastPrayer(r.prayers, place: place, method: method, hanafi: hanafi)?.timeIntervalSince1970 else { continue }
            if let old = stamps[r.key], abs(old - st) < 1800 { continue }
            for id in Self.ids(for: r.key) where counts[id] != nil { counts[id] = nil }
            stamps[r.key] = st; ch = true
        }
        if ch { save() }
    }

    /// Is this set finished for the period that started at `start`? (used to skip reminders)
    func finished(_ key: String, periodStart: Date) -> Bool {
        guard let s = stamps[key], abs(s - periodStart.timeIntervalSince1970) < 1800 else { return false }
        return AzkharData.items(key).allSatisfy { n($0.id) >= $0.times }
    }
}

// MARK: - One list of azkar cards, shared by the main sets and the "more azkar" sections

struct AzkarRow: Identifiable {
    let id: String
    let heading: String?
    let arabic: String
    let translation: String?
    let note: String?
    let ref: String
    let times: Int
    var kahf = false
}

enum AzkarText {
    static var done: String {
        switch Loc.langID {
        case "ar": "تم"; case "tr": "Tamam"; case "fr": "Terminé"; case "it": "Fatto"
        case "de": "Fertig"; case "nl": "Klaar"; case "es": "Hecho"; default: LocX.done[Loc.langID] ?? "Done"
        }
    }
    static var resetAll: String { Loc.ar ? "إعادة الكل؟" : L("Reset all?") }
    static var tapAnywhere: String { Loc.ar ? "اضغط في أي مكان للعدّ" : L("Tap anywhere to count") }
    static var longPress: String { Loc.ar ? "اضغط مطوّلًا على البطاقة لتصفيرها." : L("Long-press a card to reset it.") }
    static var readKahf: String { Loc.ar ? "اقرأ سورة الكهف" : L("Read Surat al-Kahf") }
    static func resetQuestion(_ name: String) -> String {
        Loc.ar ? "هل تريد تصفير عدّاد «\(name)»؟" : Loc.f("Do you want to reset the counter for “{0}”?", name)
    }
    /// First words of a dhikr, for the folded card.
    static func short(_ t: String) -> String {
        let w = t.replacingOccurrences(of: "[﴿﴾()\\[\\]«»]", with: "", options: .regularExpression)
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
        return w.prefix(6).joined(separator: " ") + (w.count > 6 ? " …" : "")
    }
}

struct AzkarListView<Icon: View>: View {
    let title: String
    let rows: [AzkarRow]
    var footer: String? = nil
    @ViewBuilder var icon: () -> Icon
    var onClose: () -> Void

    @ObservedObject private var store = AzkarStore.shared
    @State private var open: Set<String> = []           // finished cards shown in full again
    @State private var tasbih: AzkarRow? = nil
    @State private var confirmReset = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left").font(.sys(size: 17, weight: .bold))
                            .foregroundStyle(Theme.ink).frame(width: 40, height: 40)
                            .background(Theme.tile, in: Circle())
                    }
                    icon()
                    Text(title).font(.sys(size: 21, weight: .bold, design: Theme.design)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    resetAllButton
                }
                .padding(.horizontal, 20).padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(rows) { d in
                            if let h = d.heading {
                                    let rtl = Loc.langID == "ar" || Loc.langID == "ur"
                                Text(h).font(.sys(size: 15, weight: .heavy)).foregroundStyle(Theme.mintDeep)
                                    .multilineTextAlignment(rtl ? .trailing : .leading)
                                    .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
                                    .environment(\.layoutDirection, .leftToRight).padding(.top, 6)
                            }
                            card(d, proxy: proxy).id(d.id)
                        }
                        Text(AzkarText.longPress).font(.sys(size: 12)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center).padding(.top, 4)
                        if let footer {
                            Text(footer).font(.sys(size: 11)).foregroundStyle(Theme.muted.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .fullScreenCover(item: $tasbih) { d in
                TasbihView(row: d, onClose: {
                    let finished = store.n(d.id) >= d.times
                    tasbih = nil
                    if finished { advance(after: d, proxy: proxy) }
                })
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width > 80 && abs(v.translation.width) > 1.6 * abs(v.translation.height) { onClose() }
        })
    }

    /// ↺ — the first tap asks "Reset all?", a second tap within 3 seconds resets every card in this list.
    private var resetAllButton: some View {
        Button {
            if confirmReset {
                store.reset(rows.map(\.id)); confirmReset = false; open = []
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            } else {
                confirmReset = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmReset = false }
            }
        } label: {
            Group {
                if confirmReset { Text(AzkarText.resetAll).font(.sys(size: 14, weight: .bold)).padding(.horizontal, 12) }
                else { Image(systemName: "arrow.counterclockwise").font(.sys(size: 16, weight: .bold)).frame(width: 40) }
            }
            .frame(height: 40)
            .foregroundStyle(confirmReset ? .white : Theme.ink)
            .background(confirmReset ? Color.red.opacity(0.85) : Theme.tile, in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: confirmReset)
    }

    private func advance(after d: AzkarRow, proxy: ScrollViewProxy) {
        guard let i = rows.firstIndex(where: { $0.id == d.id }),
              let next = rows[(i + 1)...].first(where: { store.n($0.id) < $0.times }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(next.id, anchor: .center) }
        }
    }

    private func tap(_ d: AzkarRow, proxy: ScrollViewProxy) {
        let n = store.n(d.id)
        if n >= d.times {                                    // finished: tap shows or folds the text
            withAnimation(.easeInOut(duration: 0.2)) { if open.contains(d.id) { open.remove(d.id) } else { open.insert(d.id) } }
            return
        }
        if d.times >= 33 { tasbih = d; return }              // long counts: full-screen counter
        let finished = store.add(d.id, max: d.times)
        if finished {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            open.remove(d.id)
            advance(after: d, proxy: proxy)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @ViewBuilder
    private func card(_ d: AzkarRow, proxy: ScrollViewProxy) -> some View {
        let n = store.n(d.id)
        let done = n >= d.times
        let folded = done && !open.contains(d.id)
        Group {
            if folded {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.sys(size: 13, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(Theme.mint, in: Circle())
                    Text(AzkarText.short(d.arabic)).font(.sys(size: 16)).foregroundStyle(Theme.muted)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .leftToRight)
                    if d.times > 1 { Text("×\(d.times)").font(.sys(size: 13, weight: .bold)).foregroundStyle(Theme.mintDeep) }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    JustifiedText(text: d.arabic, size: 19 * Theme.azkarScale, color: UIColor(Theme.ink), lineSpacing: 9, markColor: UIColor(Theme.mintDeep))
                    if let note = d.note {
                        Text(note).font(.sys(size: 13 * Theme.azkarScale)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    if d.kahf {
                        Button {
                            UserDefaults.standard.set(293, forKey: "moshafPage")   // Surat al-Kahf starts on page 293
                            store.kahfRequest += 1
                        } label: {
                            Label(AzkarText.readKahf, systemImage: "book.fill").font(.sys(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(Theme.onAccent)
                                .background(Theme.mintDeep, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if let t = d.translation {
                        Divider().overlay(Theme.line)
                        Text(t).font(.sys(size: 18 * Theme.azkarScale)).lineSpacing(4).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(d.ref).font(.sys(size: 12, weight: .medium)).foregroundStyle(Theme.mintDeep)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        if n > 0 {
                            Button { store.add(d.id, max: d.times, step: -1); UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
                                Text("−1").font(.sys(size: 14, weight: .heavy)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 10).frame(height: 30)
                                    .background(Theme.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.tile)
                            GeometryReader { g in Capsule().fill(Theme.mint).frame(width: g.size.width * CGFloat(min(n, d.times)) / CGFloat(max(d.times, 1))) }
                        }
                        .frame(height: 6)
                        Text(done ? AzkarText.done : "\(n) / \(d.times)")
                            .font(.sys(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(done ? Theme.mintDeep : Theme.ink).monospacedDigit()
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(done ? Theme.rowNow : Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(done ? Theme.mint.opacity(0.5) : Theme.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { tap(d, proxy: proxy) }
        .onLongPressGesture(minimumDuration: 0.6) {          // one dhikr: reset straight away
            guard n > 0 else { return }
            store.reset([d.id]); open.remove(d.id)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Big counter for long counts (33, 100…)

struct TasbihView: View {
    let row: AzkarRow
    var onClose: () -> Void
    @ObservedObject private var store = AzkarStore.shared

    var body: some View {
        let v = store.n(row.id)
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.sys(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40).background(Theme.tile, in: Circle())
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                Text(row.arabic).font(.sys(size: 22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).environment(\.layoutDirection, .rightToLeft)
            }
            .frame(maxHeight: 200)
            ZStack {
                Circle().stroke(Theme.tile, lineWidth: 16)
                Circle().trim(from: 0, to: CGFloat(min(v, row.times)) / CGFloat(max(row.times, 1)))
                    .stroke(Theme.mint, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.15), value: v)
                VStack(spacing: 2) {
                    Text("\(v)").font(.system(size: 64, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink)
                    Text("/ \(row.times)").font(.sys(size: 18, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 250, height: 250)
            Text(AzkarText.tapAnywhere).font(.sys(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button { store.add(row.id, max: row.times, step: -1); UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
                Text("−1").font(.sys(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 26).frame(height: 48)
                    .background(Theme.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {
            guard store.n(row.id) < row.times else { return }
            if store.add(row.id, max: row.times) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onClose() }
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

// MARK: - Progress on a category tile: "8/25", the number of azkar, or ✓ when all are done

struct AzkarProgressBadge: View {
    let items: [(id: String, times: Int)]
    @ObservedObject private var store = AzkarStore.shared
    var body: some View {
        let d = store.done(items), t = items.count
        if t > 0 && d == t {
            Image(systemName: "checkmark").font(.sys(size: 11, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Theme.mint, in: Circle())
        } else {
            Text(d > 0 ? "\(d)/\(t)" : "\(t)").font(.sys(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.muted)
        }
    }
}
