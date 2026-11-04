import SwiftUI

// "More azkar": 24 more sections (provision duas + Hisn al-Muslim), opened from one card on the Azkar screen.
// Same data file as the Android app (azkar_more.json, bundled with the app).

struct MoreAzkarItem: Decodable, Identifiable {
    let id: String
    let ar: String
    let n: Int
    let ref: String
    let note: String?
    let h: String?
    let tr: [String: String]?
    let ht: [String: String]?
    /// Friday: shows a "Read Surat al-Kahf" button that opens the Mushaf
    let kahf: Bool?

    /// Translation for a non-Arabic app language (Arabic only when the app is in Arabic).
    func translation(_ lang: String) -> String? { lang == "ar" ? nil : (tr?[lang] ?? tr?["en"]) }
    func heading(_ lang: String) -> String? {
        guard let h else { return nil }
        return lang == "ar" ? h : (ht?[lang] ?? ht?["en"] ?? h)
    }
}

struct MoreAzkarGroup: Decodable, Identifiable {
    let id: String
    let icon: String
    let ar: String
    let en: String
    let t: [String: String]?
    let items: [MoreAzkarItem]

    func title(_ lang: String) -> String { lang == "ar" ? ar : (t?[lang] ?? en) }
}

enum MoreAzkar {
    static let groups: [MoreAzkarGroup] = {
        guard let url = Bundle.main.url(forResource: "azkar_more", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([MoreAzkarGroup].self, from: data) else { return [] }
        return list
    }()

    static func title(_ lang: String) -> String {
        let t = ["ar": "أذكار أخرى", "en": "More azkar", "tr": "Diğer zikirler", "fr": "Autres adhkar", "it": "Altri adhkar",
                 "de": "Weitere Adhkar", "nl": "Meer adhkar", "es": "Más adhkar", "ur": "مزید اذکار", "ta": "மேலும் திக்ர்கள்", "ru": "Другие азкары"]
        return t[lang] ?? t["en"]!
    }
}

/// Icon of a section: a one-colour line symbol in the app's colour (same look as the Android app).
struct MoreAzkarIcon: View {
    let icon: String
    let size: CGFloat
    static let symbols: [String: String] = [
        "📖": "book", "🌾": "leaf", "🛏️": "bed.double", "💧": "drop", "🏠": "house", "📢": "megaphone",
        "🧭": "safari", "🌌": "moon", "🫶": "heart.circle", "🍽️": "fork.knife", "🌙": "moon.stars", "👕": "tshirt",
        "🚪": "door.left.hand.open", "🌧️": "cloud.rain", "🩺": "stethoscope", "🤍": "heart", "🧳": "suitcase.rolling",
        "🕋": "cube", "🤲": "arrow.counterclockwise", "📿": "circle.dotted", "✨": "sparkles", "👶": "figure.and.child.holdinghands",
        "🛡️": "checkmark.shield", "📚": "books.vertical"
    ]
    var body: some View {
        if icon == "svg:rug" { PrayerRugIcon().frame(width: size * 1.1, height: size * 1.1).foregroundStyle(Theme.mintDeep) }
        else if icon == "🕌" { Image("MosqueIcon").renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size).foregroundStyle(Theme.mintDeep) }
        else if let sym = Self.symbols[icon] { Image(systemName: sym).font(.system(size: size * 0.85, weight: .regular)).foregroundStyle(Theme.mintDeep) }
        else { Text(icon).font(.system(size: size)) }
    }
}

/// Prayer rug with a mihrab arch, drawn as one-colour lines.
struct PrayerRugIcon: View {
    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width, g.size.height) / 24
            Path { p in
                p.move(to: CGPoint(x: 6 * k, y: 21 * k)); p.addLine(to: CGPoint(x: 6 * k, y: 9 * k))
                p.addArc(center: CGPoint(x: 12 * k, y: 9 * k), radius: 6 * k, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.addLine(to: CGPoint(x: 18 * k, y: 21 * k)); p.closeSubpath()
                p.move(to: CGPoint(x: 9.5 * k, y: 21 * k)); p.addLine(to: CGPoint(x: 9.5 * k, y: 12 * k))
                p.addArc(center: CGPoint(x: 12 * k, y: 12 * k), radius: 2.5 * k, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.addLine(to: CGPoint(x: 14.5 * k, y: 21 * k))
                p.move(to: CGPoint(x: 5 * k, y: 21 * k)); p.addLine(to: CGPoint(x: 19 * k, y: 21 * k))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Grid of the 24 sections; tapping one opens its azkar in the same screen.
struct MoreAzkarView: View {
    @AppStorage("langID") private var langID = "ar"
    /// Section to open straight away (from a reminder)
    var start: Int? = nil
    var onClose: () -> Void
    @State private var openGroup: MoreAzkarGroup? = nil

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        Group {
            if let g = openGroup {
                MoreAzkarListView(group: g, onClose: { withAnimation(.easeInOut(duration: 0.25)) { openGroup = nil } })
                    .transition(.move(edge: .trailing))
            } else {
                grid.transition(.move(edge: .leading))
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.sys(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink).frame(width: 40, height: 40)
                        .background(Theme.tile, in: Circle())
                }
                Text(MoreAzkar.title(langID)).font(.sys(size: 22, weight: .bold, design: Theme.design)).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(MoreAzkar.groups) { g in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.25)) { openGroup = g }
                        } label: { tile(g) }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
                Text(Loc.ar ? "الأذكار: حصن المسلم" : L("Quran: Tanzil · Adhkar: Hisn al-Muslim"))
                    .font(.sys(size: 11)).foregroundStyle(Theme.muted.opacity(0.8)).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width > 80 && abs(v.translation.width) > 1.6 * abs(v.translation.height) { onClose() }
        })
    }

    private func tile(_ g: MoreAzkarGroup) -> some View {
        VStack(spacing: 6) {
            HStack { Spacer(); AzkarProgressBadge(items: g.items.map { (id: $0.id, times: $0.n) }) }
            MoreAzkarIcon(icon: g.icon, size: 32).frame(height: 40)
            Text(g.title(langID)).font(.sys(size: 15, weight: .bold, design: Theme.design)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            if langID != "ar" { Text(g.ar).font(.sys(size: 13, weight: .semibold)).foregroundStyle(Theme.mintDeep).lineLimit(1).minimumScaleFactor(0.8) }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 140)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

/// Azkar of one section: the same counting list as the main collections.
struct MoreAzkarListView: View {
    @AppStorage("langID") private var langID = "ar"
    let group: MoreAzkarGroup
    var onClose: () -> Void

    var body: some View {
        AzkarListView(
            title: group.title(langID),
            rows: group.items.map {
                AzkarRow(id: $0.id, heading: $0.heading(langID), arabic: $0.ar, translation: $0.translation(langID),
                         note: $0.note, ref: $0.ref, times: $0.n, kahf: $0.kahf ?? false)
            },
            icon: { MoreAzkarIcon(icon: group.icon, size: 20) },
            onClose: onClose)
    }
}
