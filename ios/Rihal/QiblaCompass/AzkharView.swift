import SwiftUI

enum AzkharCategory: String, CaseIterable, Identifiable {
    case morning, evening, afterPrayer, sleep, travel
    var id: String { rawValue }

    func title(_ lang: String) -> String {
        let t: [String: [String]] = [
            // morning, evening, after prayer, sleep, travel
            "ar": ["الصباح", "المساء", "بعد الصلاة", "النوم", "السفر"],
            "en": ["Morning", "Evening", "After prayer", "Sleep", "Travel"],
            "tr": ["Sabah", "Akşam", "Namaz sonrası", "Uyku", "Yolculuk"],
            "fr": ["Matin", "Soir", "Après la prière", "Sommeil", "Voyage"],
            "it": ["Mattina", "Sera", "Dopo la preghiera", "Sonno", "Viaggio"],
            "de": ["Morgen", "Abend", "Nach dem Gebet", "Schlaf", "Reise"],
            "nl": ["Ochtend", "Avond", "Na het gebed", "Slaap", "Reis"],
            "es": ["Mañana", "Tarde", "Tras la oración", "Dormir", "Viaje"]
        ]
        let list = LocX.cats[lang] ?? t[lang] ?? t["en"]!
        return list[Self.allCases.firstIndex(of: self)!]
    }
    var arabicTitle: String { title("ar") }
    var icon: String {
        switch self {
        case .morning: "sunrise"
        case .evening: "sunset"
        case .afterPrayer: "hands.sparkles.fill"
        case .sleep: "moon.stars"
        case .travel: "airplane"
        }
    }
}

struct CatIcon: View {
    let cat: AzkharCategory
    let size: CGFloat
    var body: some View {
        if cat == .afterPrayer {
            Image("DuaSolid").renderingMode(.template).resizable().scaledToFit().frame(width: size * 1.1, height: size * 1.1)
        } else {
            Image(systemName: cat.icon).font(.sys(size: size, weight: .regular))
        }
    }
}

struct AzkharDetailView: View {
    @AppStorage("langID") private var langID = "ar"
    let cat: AzkharCategory
    var onClose: () -> Void

    var body: some View {
        AzkarListView(
            title: cat.title(langID),
            rows: AzkharData.items(cat.rawValue).map { d in
                // Arabic app language: Arabic only. Other languages: their own translation.
                let t: String? = langID == "ar" ? nil : (d.translations[langID] ?? LocX.azkar[d.id]?[langID] ?? d.translations["en"])
                return AzkarRow(id: d.id, heading: nil, arabic: d.arabic, translation: t, note: nil, ref: d.ref, times: d.times)
            },
            footer: Loc.ar ? "القرآن: تنزيل · الأذكار: حصن المسلم" : L("Quran: Tanzil · Adhkar: Hisn al-Muslim"),
            icon: { CatIcon(cat: cat, size: 18).foregroundStyle(Theme.mintDeep) },
            onClose: onClose)
    }
}

/// All Azkar collections, opened from the Azkar card.
struct AzkharCollectionsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("langID") private var langID = "ar"
    var onClose: (() -> Void)? = nil
    @ObservedObject private var store = AzkarStore.shared
    @State private var askReset: (title: String, ids: [String])? = nil
    @State private var moreStart: Int? = nil
    @State private var flipped: AzkharCategory? = nil
    @State private var opened: AzkharCategory? = nil
    @State private var showMore = false

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var subtitle: String {
        switch langID {
        case "ar": "اختر مجموعة أذكار"
        case "tr": "Bir zikir grubu seçin"
        case "fr": "Choisissez une série d’invocations"
        case "it": "Scegli una raccolta di adhkar"
        case "de": "Wähle eine Gruppe von Adhkar"
        case "nl": "Kies een groep adhkar"
        case "es": "Elige un grupo de adhkar"
        default: "Choose a collection"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left").font(.sys(size: 17, weight: .bold))
                            .foregroundStyle(Theme.ink).frame(width: 40, height: 40)
                            .background(Theme.tile, in: Circle())
                    }
                }
                PageTitle(en: "Azkhar", ar: "الأذكار")
            }
            .padding(.horizontal, 20).padding(.top, 8)
            Text(subtitle).font(.sys(size: 14)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 2)

            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(AzkharCategory.allCases) { c in tile(c) }
                    moreTile
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg.ignoresSafeArea())
        .fullScreenCover(item: $opened, onDismiss: { withAnimation(.easeInOut(duration: 0.35)) { flipped = nil } }) { c in
            AzkharDetailView(cat: c, onClose: { opened = nil })
        }
        .fullScreenCover(isPresented: $showMore, onDismiss: { moreStart = nil }) {
            MoreAzkarView(start: moreStart, onClose: { showMore = false })
        }
        // Long-press on a category: ask before clearing its counter
        .alert(askReset.map { AzkarText.resetQuestion($0.title) } ?? "", isPresented: Binding(get: { askReset != nil }, set: { if !$0 { askReset = nil } })) {
            Button(Loc.ar ? "نعم" : L("Yes"), role: .destructive) {
                if let r = askReset { store.reset(r.ids); UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                askReset = nil
            }
            Button(Loc.ar ? "لا" : L("No"), role: .cancel) { askReset = nil }
        }
        .onAppear {
            store.sync(place: model.place, method: model.method, hanafi: model.hanafi)   // counts start again after Fajr, Asr…
            handleOpen(store.openRequest)
        }
        .onChange(of: store.openRequest) { _, r in handleOpen(r) }
        .onChange(of: store.kahfRequest) { _, _ in opened = nil; showMore = false; flipped = nil }
    }

    /// A tapped reminder: "morning", "evening", "afterPrayer" or "m:<section>"
    private func handleOpen(_ r: String?) {
        guard let r else { return }
        store.openRequest = nil
        opened = nil; showMore = false; flipped = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if r.hasPrefix("m:") { moreStart = Int(r.dropFirst(2)); showMore = true }
            else if let c = AzkharCategory(rawValue: r) { opened = c }
        }
    }

    /// Sixth card: opens the 24 more sections (provision duas and the rest of Hisn al-Muslim)
    private var moreTile: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showMore = true
        } label: {
            centredTile(items: MoreAzkar.groups.flatMap { $0.items.map { (id: $0.id, times: $0.n) } }) {
                Image(systemName: "books.vertical").font(.sys(size: 26, weight: .regular)).foregroundStyle(Theme.mintDeep)
                    .frame(width: 52, height: 52)
                    .background(Theme.mintDeep.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } title: {
                Text(MoreAzkar.title(langID)).font(.sys(size: 19, weight: .bold, design: Theme.design)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 168)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ c: AzkharCategory) -> some View {
        let isFlipped = flipped == c
        let n = AzkharData.items(c.rawValue).map { (id: $0.id, times: $0.times) }
        return ZStack {
            front(c, n).opacity(isFlipped ? 0 : 1)
            back(c).opacity(isFlipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
        }
        .frame(height: 168)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            guard flipped == nil else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.45)) { flipped = c }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { opened = c }
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            // Long-press: ask "reset the counter for …?" (only when something was counted)
            guard n.contains(where: { store.n($0.id) > 0 }) else { return }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            askReset = (c.title(langID), n.map(\.id))
        }
        .accessibilityAddTraits(.isButton)
    }

    private func front(_ c: AzkharCategory, _ n: [(id: String, times: Int)]) -> some View {
        centredTile(items: n) {
            CatIcon(cat: c, size: 26).foregroundStyle(Theme.mintDeep)
                .frame(width: 52, height: 52)
                .background(Theme.mintDeep.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } title: {
            Text(c.title(langID)).font(.sys(size: 19, weight: .bold, design: Theme.design)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    /// Icon and title in the middle of the card, the number of azkar in the top corner.
    private func centredTile<I: View, T: View>(items: [(id: String, times: Int)], @ViewBuilder icon: () -> I, @ViewBuilder title: () -> T) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                icon()
                title().multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            AzkarProgressBadge(items: items)
        }
        .padding(16)
    }

    private func back(_ c: AzkharCategory) -> some View {
        VStack(spacing: 10) {
            CatIcon(cat: c, size: 34)
            Text(c.title(langID)).font(.sys(size: 22, weight: .bold))
        }
        .foregroundStyle(Theme.onAccent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Azkar tab: one card for all Azkar collections and one for the Moshaf.
struct AzkharView: View {
    @AppStorage("langID") private var langID = "ar"
    @AppStorage("moshafPage") private var moshafPage = 1
    @State private var showAzkar = false
    @State private var showMoshaf = false

    /// The Azkar tab opens the collections directly; the Mushaf has its own tab.
    var body: some View {
        AzkharCollectionsView()
    }

    private func open(_ flag: Binding<Bool>) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flag.wrappedValue = true
    }

    private var azkarCard: some View {
        Button { open($showAzkar) } label: {
            HStack(spacing: 14) {
                Image("DuaSolid").renderingMode(.template).resizable().scaledToFit().frame(width: 30, height: 30)
                    .foregroundStyle(Theme.mintDeep)
                    .frame(width: 60, height: 60)
                    .background(Theme.mintDeep.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Azkhar")).font(.sys(size: 21, weight: .bold, design: Theme.design)).foregroundStyle(Theme.ink)
                    Text(AzkharCategory.allCases.map { $0.title(langID) }.joined(separator: " · "))
                        .font(.sys(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.forward").font(.sys(size: 15, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var moshafCard: some View {
        let q = Quran.shared
        let page = min(max(moshafPage, 1), 604)
        let sura = q.isLoaded ? "سورة " + q.suras[q.sura(ofPage: page) - 1].ar : ""
        return Button { open($showMoshaf) } label: {
            HStack(spacing: 14) {
                Image(systemName: "book.closed.fill").font(.sys(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.mintDeep)
                    .frame(width: 60, height: 60)
                    .background(Theme.mintDeep.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Loc.ar ? "المصحف" : L("Mushaf")).font(.sys(size: 21, weight: .bold, design: Theme.design)).foregroundStyle(Theme.ink)
                        if !Loc.ar { Spacer(); Text("المصحف").font(.sys(size: 18, weight: .bold)).foregroundStyle(Theme.mintDeep) }
                    }
                    Text(page > 1
                         ? (Loc.ar ? "تابع القراءة: صفحة \(Moshaf.arabicDigits(page)) · \(sura)" : Loc.f("Continue: page {0}", "\(page)") + " · " + sura)
                         : (Loc.ar ? "القرآن الكريم · رواية حفص" : L("The Holy Quran · Hafs")))
                        .font(.sys(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.forward").font(.sys(size: 15, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
