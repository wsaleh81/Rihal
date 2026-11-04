import SwiftUI
import UIKit

struct QiblaView: View {
    /// true when shown inside the combined home page (no own scroll view, title or source line)
    var embedded = false
    @AppStorage("compassStyle") private var compassStyle = "rings"
    @EnvironmentObject var model: AppModel
    @State private var shown: Double = 0
    @State private var wasAligned = false

    private var target: Double? { model.location.heading }
    private var delta: Double? {
        guard let t = target else { return nil }
        return QiblaMath.diff(model.qibla, t)
    }
    private var aligned: Bool { (delta.map { abs($0) <= 3 }) ?? false }

    private var inner: some View {
            VStack(spacing: 0) {
                if !embedded { PageTitle(en: "Qibla", ar: "القبلة") }
                if !embedded { header; sourceLine }

                if embedded {
                    dial
                        .frame(maxWidth: 250)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22).padding(.bottom, 16)
                } else {
                    dial
                        .overlay { distanceLabel }
                        .frame(maxWidth: 320)
                        .padding(.top, 26).padding(.bottom, 34)
                        .padding(.horizontal, 10)
                    statusCard
                }
                if let note = sensorNote { Text(note).font(.footnote).foregroundStyle(Theme.muted).padding(.top, 12).multilineTextAlignment(.center) }
            }
            .padding(.horizontal, embedded ? 0 : 20)
            .padding(.bottom, embedded ? 14 : 110)
    }

    /// Tall bar beside the compass: arrow on top, the instruction reading upwards below it.
    private var sideBar: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(zone)
                Image(systemName: aligned ? "checkmark" : (delta ?? 1) < 0 ? "arrow.counterclockwise" : "arrow.clockwise")
                    .font(.sys(size: 15, weight: .bold)).foregroundStyle(Color.black.opacity(0.78))
            }
            .frame(width: 32, height: 32)
            Text(title).font(.sys(size: 15, weight: .heavy, design: Theme.design)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7).fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 22, height: 150)
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .frame(width: 46)
        .background(LinearGradient(colors: [zone.opacity(0.32), zone.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                    in: Capsule())
        .overlay(Capsule().stroke(zone.opacity(0.5), lineWidth: 1))
        .animation(.easeInOut(duration: 0.25), value: zone)
    }

    /// Distance to Makkah, inside the compass, with no title
    private var distanceLabel: some View {
        GeometryReader { g in
            Text("\(Int(model.distance.rounded()).formatted()) \(Loc.ar ? "كم" : "km")")
                .font(.sys(size: g.size.width * 0.04, weight: .heavy, design: Theme.design)).monospacedDigit()
                .foregroundStyle(Theme.isClassic ? Color(hex: 0x0A1430) : Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: g.size.width * 0.28)
                .position(x: g.size.width / 2, y: g.size.height * (Theme.isClassic ? 0.605 : 0.64))
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        Group {
            if embedded { inner } else { ScrollView { inner }.scrollIndicators(.hidden) }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; model.location.startHeading(); follow() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; model.location.stopHeading() }
        .onChange(of: target) { _, _ in follow() }
        .onChange(of: aligned) { _, now in
            if now && !wasAligned { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            wasAligned = now
        }
    }

    private func follow() {
        guard let t = target else { return }
        let step = QiblaMath.diff(t, shown)
        withAnimation(.easeOut(duration: 0.18)) { shown += step }
    }

    private var sensorNote: String? {
        let l = model.location
        if !CLHeadingAvailable { return Loc.ar ? "هذا الجهاز بلا بوصلة." : L("This device has no compass.") }
        if l.denied { return L("Location access is off. Turn it on in Settings so the compass can point to true north.") }
        if l.heading == nil { return L("Starting the compass…") }
        if l.headingAccuracy < 0 || l.headingAccuracy > 25 { return L("Compass needs calibration. Move your phone in a figure of eight.") }
        if !l.usesTrueNorth { return L("Showing magnetic north. Allow location for true north.") }
        return nil
    }
    private var CLHeadingAvailable: Bool { LocationService.headingAvailable }

    private var sun: SunInfo { SunMath.info(lat: model.place.lat, lon: model.place.lon, date: Date()) }

    /// Arrow shown in the middle of the compass: which way to turn, or a tick when facing the Qibla
    private var turnIcon: (icon: String, color: Color) {
        (aligned ? "checkmark" : (delta ?? 1) < 0 ? "arrow.counterclockwise" : "arrow.clockwise", zone)
    }

    // A compass is a physical map: east is always clockwise from north. Arabic and Urdu switch the
    // app to right-to-left, which mirrors the dial's drawing (Qibla, sun and degrees all showed
    // 360 - true), so the dial is always drawn left-to-right, like the Mushaf pages.
    private var dial: some View {
        Group {
            if compassStyle == "rings" {
                RingsDial(heading: shown, qibla: model.qibla, aligned: aligned, tint: embedded ? zone : nil)
            } else if Theme.isClassic {
                ClassicDial(heading: shown, qibla: model.qibla, sun: sun, turn: nil, themed: compassStyle != "classicGrey", aligned: aligned)
            } else {
                CompassDial(heading: shown, qibla: model.qibla, aligned: aligned, sun: sun, turn: embedded ? turnIcon : nil)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @AppStorage("tempUnit") private var tempUnit = "c"

    private var weatherChip: some View {
        let w = model.weather.snapshot
        let text: String = {
            guard let w else { return model.network.online ? "…" : "—" }
            return tempUnit == "f" ? "\(Int((w.tempC * 9 / 5 + 32).rounded()))°F" : "\(Int(w.tempC.rounded()))°C"
        }()
        return HStack(spacing: 7) {
            Image(systemName: w.map { WeatherService.symbol(code: $0.code, isDay: $0.isDay) } ?? (model.network.online ? "cloud" : "cloud.slash"))
                .font(.sys(size: 17, weight: .bold)).symbolRenderingMode(.multicolor)
            Text(text).font(.sys(size: 17, weight: .heavy, design: Theme.design)).monospacedDigit()
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14).frame(height: 44)
        .background(Theme.tile, in: Capsule())
        .accessibilityLabel("Weather \(text)")
    }

    /// One line: how the position was found and whether the phone is online.
    private var sourceLine: some View {
        let acc = model.location.accuracy.map { "±\(Int($0.rounded())) " + L("m") } ?? (Loc.ar ? "لا يوجد تحديد" : Loc.f("no fix yet"))
        return HStack(spacing: 6) {
            Circle().fill(model.network.online ? Theme.zoneGreen : Theme.zoneYellow).frame(width: 7, height: 7)
            Text(Loc.ar ? (model.network.online ? "متصل · GPS \(acc)" : "دون اتصال · GPS والبوصلة · \(acc)") : (model.network.online ? Loc.f("Online · GPS {0}", acc) : Loc.f("Offline · using GPS and compass · {0}", acc)))
                .font(.sys(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(.top, 8).padding(.leading, 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { model.tab = 2 } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.mintDeep)
                    Text(model.place.name).font(.sys(size: 15, weight: .semibold, design: Theme.design)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.sys(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)
                .padding(.leading, 12).padding(.trailing, 14)
                .frame(height: 44)
                .card(22)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            weatherChip
        }
        .padding(.top, 10)
    }

    private var zone: Color {
        guard let d = delta else { return Theme.muted }
        let a = abs(d)
        return a > 45 ? Theme.zoneRed : (a > 15 ? Theme.zoneYellow : Theme.zoneGreen)
    }

    private func clock(_ d: Date?, _ tz: TimeZone) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.timeZone = tz; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private var statusCard: some View {
        let sub = Theme.muted
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(zone)
                    Image(systemName: aligned ? "checkmark" : (delta ?? 1) < 0 ? "arrow.counterclockwise" : "arrow.clockwise")
                        .font(.sys(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.78))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.sys(size: embedded ? 17 : 24, weight: .heavy, design: Theme.design)).foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.8).lineLimit(1)
                    if !embedded || aligned { Text(subtitle).font(.sys(size: 12)).foregroundStyle(sub).lineLimit(1).minimumScaleFactor(0.8) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, embedded ? 7 : 12)
            .background(
                LinearGradient(colors: [zone.opacity(0.32), zone.opacity(0.08)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(zone.opacity(0.5), lineWidth: 1))
        }
        .padding(.horizontal, embedded ? 0 : 14).padding(.vertical, embedded ? 0 : 14)
        .background(embedded ? Color.clear : Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(embedded ? 0 : 0.1), radius: 14, y: 8)
        .animation(.easeInOut(duration: 0.25), value: zone)
    }

    private var title: String {
        guard let d = delta else { return L("Finding the compass") }
        if abs(d) <= 3 { return L("You're facing the Qibla") }
        if Loc.ar { return "لُف \(d > 0 ? "يمينًا" : "يسارًا") \(Int(abs(d).rounded()))°" }
        return Loc.f(d > 0 ? "Turn right {0}°" : "Turn left {0}°", "\(Int(abs(d).rounded()))")
    }
    private var subtitle: String {
        guard let d = delta else { return Loc.ar ? "القبلة \(Int(model.qibla.rounded()))° من الشمال الحقيقي" : Loc.f("Qibla is {0}° {1} of true north", "\(Int(model.qibla.rounded()))", QiblaMath.cardinal(model.qibla)) }
        if abs(d) <= 3 { return L("Hold steady, then begin your prayer") }
        return L(abs(d) <= 15 ? "Almost there, hold steady" : (abs(d) <= 45 ? "Getting closer, keep turning" : "Rotate until the Kaaba reaches the top"))
    }

    private func tileView(_ icon: String, _ label: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.sys(size: 13, weight: .bold))
                Text(L(label)).font(.sys(size: 12, weight: .bold))
            }
            .foregroundStyle(tint)
            Text(value).font(.sys(size: 19, weight: .heavy, design: Theme.design)).monospacedDigit().foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(L(unit)).font(.sys(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

}


/// Main page: the Qibla compass on top, then today's prayer times.
struct HomeView: View {
    var body: some View {
        GeometryReader { g in
            ScrollView {
                VStack(spacing: 0) {
                    PageTitle(en: "Prayer Times", ar: "مواقيت الصلاة").padding(.horizontal, 20)
                    PrayerView(embedded: true, middle: AnyView(QiblaView(embedded: true)), wide: g.size.width >= 600)
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
