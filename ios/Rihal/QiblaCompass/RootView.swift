import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase

    private var viewID: String {
        let a: String = model.themeID + model.langID + model.paletteID
        let b: String = model.appearance + model.textSize + model.azkarSize
        return a + b + (model.boldText ? "b" : "n")
    }

    private var scheme: ColorScheme? {
        switch model.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            Group {
                switch model.tab {
                case 0, 1: HomeView()
                case 5: MoshafView(onClose: { model.tab = 0 })
                case 3: MosquesView()
                case 4: AzkharView()
                default: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentMargins(.bottom, 84, for: .scrollContent)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { v in
                        let dx = v.translation.width, dy = v.translation.height
                        guard abs(dx) > 70, abs(dx) > abs(dy) * 1.6 else { return }
                        guard model.tab != 5 else { return }   // the Mushaf pages use their own swipe
                        let order = [0, 3, 4, 5, 2]            // same order as the tab bar
                        guard let i = order.firstIndex(of: model.tab) else { return }
                        let forward = AppLang.current.isRTL ? dx > 0 : dx < 0   // the tab bar runs right to left in Arabic
                        let j = forward ? i + 1 : i - 1
                        guard order.indices.contains(j) else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { model.tab = order[j] }
                    }
            )
            if model.tab != 5 {   // the Mushaf reader uses the whole screen
                TabBar()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }
            if !model.welcomed {
                WelcomeView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.welcomed)
        .onChange(of: phase) { _, p in
            if p == .active {
                if let t = model.leftAt, Date().timeIntervalSince(t) > 300, AzkarStore.shared.openRequest == nil { model.tab = 0 }
                model.leftAt = nil
                AzkarStore.shared.sync(place: model.place, method: model.method, hanafi: model.hanafi)
                model.refreshLocation(); model.rescheduleNotifications(); model.refreshWeather()
                if model.tab == 0 || model.tab == 1 { model.location.startHeading() }
            } else if p == .background {
                model.leftAt = Date()
                model.location.pause()
            }
        }
        .onChange(of: model.location.coordinate?.latitude) { _, _ in model.refreshWeather() }
        .onChange(of: model.notifKey) { _, _ in model.rescheduleNotifications() }
        // A tapped azkar reminder opens the Azkar tab (the list itself opens there); the Kahf button opens the Mushaf.
        .onReceive(AzkarStore.shared.$openRequest) { r in
            guard r != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if model.tab != 4 { model.tab = 4 } }
        }
        .onReceive(AzkarStore.shared.$kahfRequest.dropFirst()) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { model.tab = 5 }
        }
        .task(id: model.welcomed) {
            guard model.welcomed else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if model.notifOn { Notifier.requestAuth { _ in model.rescheduleNotifications() } }
        }
        .id(viewID)
        .preferredColorScheme(scheme)
    }
}

struct TabBar: View {
    @EnvironmentObject var model: AppModel
    // display order (left to right): Qibla, Prayer Times, Mosques, Azkhar, Settings
    private let items: [(id: Int, title: String, icon: String)] = [
        (0, "Prayer Times", "safari"), (3, "Mosques", "MosqueIcon"), (4, "Azkhar", "DuaSolid"), (5, "Mushaf", "book.fill"), (2, "Settings", "gearshape")
    ]

    var body: some View {
        // Arabic and Urdu read from the right: Prayer Times on the right, Settings on the left (like the Android app)
        let shown = AppLang.current.isRTL ? Array(items.reversed()) : items
        return HStack(spacing: 2) {
            ForEach(shown, id: \.id) { it in
                let on = model.tab == it.id
                Button { model.tab = it.id } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            if it.icon == "MosqueIcon" { MosqueGlyph(size: 23) }
                            else if it.icon == "DuaSolid" { Image("DuaSolid").renderingMode(.template).resizable().scaledToFit().frame(width: 23, height: 23) }
                            else { Image(systemName: it.icon).font(.system(size: 20, weight: .semibold)) }
                        }
                        .frame(width: 30, height: 26)
                        Text(L(it.title))
                            .font(.system(size: 11, weight: .semibold, design: Theme.design))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(height: 14)
                    }
                    .foregroundStyle(on ? Theme.mintDeep : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        if on {
                            Capsule().fill(Theme.mintDeep.opacity(0.16))
                                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.8))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(it.title)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(5)
        .modifier(GlassBar())
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.tab)
    }
}

/// iOS 26 Liquid Glass when available, frosted material before that.
private struct GlassBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        }
    }
}
