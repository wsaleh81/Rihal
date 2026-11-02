import SwiftUI

extension Prayer {
    var symbol: String {
        switch self {
        case .fajr: return "sunrise"
        case .sunrise: return "sun.horizon.fill"
        case .dhuhr: return "sun.max.fill"
        case .asr: return "cloud.sun.fill"
        case .maghrib: return "sunset.fill"
        case .isha: return "moon.stars.fill"
        }
    }
}

struct PrayerView: View {
    var embedded = false
    /// shown right under the date (the Qibla compass on the home page)
    var middle: AnyView? = nil
    /// unfolded phone / tablet: prayer times on the right, compass, countdown and coordinates on the left
    var wide = false
    @EnvironmentObject var model: AppModel
    @State private var dayOffset = 0
    @State private var showPicker = false
    @AppStorage("tempUnit") private var tempUnit = "c"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            content(now: ctx.date)
        }
    }

    private func content(now: Date) -> AnyView {
        let p = model.place
        let r = PrayerCalculator.events(around: now, lat: p.lat, lon: p.lon, timeZone: p.timeZone,
                                        method: model.method, hanafi: model.hanafi)
        let counted = r.all.filter { $0.prayer.isPrayer }
        let next = counted.first { $0.date > now }
        let prev = counted.last { $0.date <= now }
        // after sunrise the Fajr time is over: the card shows "الصبح" (morning) from sunrise until Dhuhr
        let cur = r.all.last { $0.date <= now }
        let nowEv = cur?.prayer == .sunrise ? cur : prev
        let shown = Calendar.current.date(byAdding: .day, value: dayOffset, to: now) ?? now
        let day = dayOffset == 0 ? r.today
            : PrayerCalculator.events(around: shown, lat: p.lat, lon: p.lon, timeZone: p.timeZone,
                                      method: model.method, hanafi: model.hanafi).today
        let fmt = timeFormatter(p.timeZone)

        let sn = SunMath.info(lat: p.lat, lon: p.lon, date: shown)
        let dir: LayoutDirection = AppLang.current.isRTL ? .rightToLeft : .leftToRight
        let rowsView = VStack(spacing: 8) {
            ForEach(Prayer.allCases) { pr in
                let t = day[pr]
                let isNow = dayOffset == 0 && nowEv?.prayer == pr && t == nowEv?.date
                let isNext = dayOffset == 0 && next?.prayer == pr && t == next?.date
                row(pr, time: t, az: nil, past: dayOffset == 0 && !isNow && (t.map { $0 < now } ?? false),
                    isNow: isNow, isNext: isNext, fmt: fmt)
            }
        }
        let footer = Text(Loc.ar ? "تم الحساب على هذا الجهاز · طريقة \(L(model.method.name))" : Loc.f("Calculated on this device · {0} method", L(model.method.name)))
            .font(.sys(size: 12)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
        let inner = VStack(alignment: .leading, spacing: 0) {
                if !embedded { PageTitle(en: "Prayer Times", ar: "مواقيت الصلاة") }
                header(shown, p)
                if wide {
                    // physical sides: left = compass, countdown, coordinates; right = prayer times
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 0) {
                            banner(now: now, place: p).padding(.top, 10)
                            hero(next: next, prev: prev, nowEv: nowEv, now: now, fmt: fmt).padding(.top, 10)
                            if let middle { middle }
                        }
                        .frame(maxWidth: .infinity)
                        .environment(\.layoutDirection, dir)
                        VStack(spacing: 0) {
                            rowsView.padding(.top, 10)
                            footer.padding(.top, 12)
                        }
                        .frame(maxWidth: .infinity)
                        .environment(\.layoutDirection, dir)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                } else {
                    banner(now: now, place: p).padding(.top, 10)
                    hero(next: next, prev: prev, nowEv: nowEv, now: now, fmt: fmt).padding(.top, 10)
                    if let middle { middle }
                    rowsView.padding(.top, 12)
                    footer.padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        let page = inner
            .environment(\.layoutDirection, AppLang.current.isRTL ? .rightToLeft : .leftToRight)   // Arabic reads from the right
            .sheet(isPresented: $showPicker) {
            MosqueCityPicker(current: p, selected: model.usingGPS ? nil : p, onPick: { c in
                if let c {
                    if Cities.all.contains(where: { $0.name == c.name && $0.isoCode == c.isoCode }) { model.chooseCity(c) } else { model.pin(c) }
                } else { model.useMyLocation() }
            }, title: "City")
            .presentationDetents([.large])
        }
        if embedded { return AnyView(page) }
        return AnyView(ScrollView { page }.scrollIndicators(.hidden))
    }

    // MARK: header

    private func header(_ d: Date, _ p: Place) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(fmtDate(d, p.timeZone, dayOffset == 0 ? "EEEEdMMMM" : "EEEEdMMMMyyyy"))
                    .font(.sys(size: 17, weight: .heavy, design: Theme.design)).foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.75).lineLimit(1)
                Text(hijri(d, p.timeZone)).foregroundStyle(Color(hex: 0x7AD0FF))
                    .font(.sys(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                // previous day first: on the left in English, on the right in Arabic (arrows point the reading direction's way)
                navButton(AppLang.current.isRTL ? "chevron.right" : "chevron.left") { dayOffset -= 1 }
                navButton(AppLang.current.isRTL ? "chevron.left" : "chevron.right") { dayOffset += 1 }
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.sys(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                .frame(width: 28, height: 28).background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    /// Latitude and longitude of the place the times are calculated for
    private func coordsCard(_ p: Place) -> some View {
        let lat = String(format: "%.4f° %@", abs(p.lat), p.lat >= 0 ? "N" : "S")
        let lon = String(format: "%.4f° %@", abs(p.lon), p.lon >= 0 ? "E" : "W")
        return HStack(spacing: 12) {
            iconBox("location.north.line.fill", fill: Theme.mint.opacity(0.16), fg: Theme.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text(Loc.ar ? "الإحداثيات" : L("Coordinates")).font(.sys(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                Text("\(lat)  ·  \(lon)").font(.sys(size: 16, weight: .heavy, design: Theme.design)).monospacedDigit()
                    .foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(minHeight: 56)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 12)
    }

    // MARK: location banner

    @ViewBuilder private func banner(now: Date, place: Place) -> some View {
        let loc = place.country.isEmpty ? place.name : "\(place.name), \(place.country)"
        switch model.banner {
        case .detecting:
            bannerCard(tint: Theme.mint, title: L("Finding your location…"), sub: Loc.ar ? "عرض \(place.name) حتى التأكيد" : Loc.f("Showing {0} until confirmed", place.name), spinner: true) { EmptyView() }
        case .confirmed:
            bannerCard(tint: Theme.zoneGreen, title: loc, sub: Loc.ar ? "GPS مؤكد · " + ago(model.location.fixDate, now) : Loc.f("GPS confirmed · {0}", ago(model.location.fixDate, now)), dot: true) {
                pill("arrow.triangle.2.circlepath", L("Refresh"), Theme.mintDeep, Theme.tile) { model.refreshLocation() }
            }
        case .manual:
            bannerCard(tint: Theme.muted, title: place.name, sub: L("Manual city")) {
                pill("location.fill", L("Use GPS"), Theme.mintDeep, Theme.tile) { model.useMyLocation() }
            }
        case .failed:
            bannerCard(tint: Theme.zoneRed, title: L("Location not found"), sub: Loc.ar ? "استخدام \(place.name)" : Loc.f("Using {0}", place.name), icon: "location.slash.fill") {
                pill(nil, L("Choose city"), Theme.onAccent, Theme.mint) { showPicker = true }
            }
        case .changed(let from):
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    iconBox("mappin.and.ellipse", fill: Theme.zoneYellow, fg: .black)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Loc.ar ? "أنت الآن في \(loc)" : Loc.f("You are now in {0}", loc)).font(.sys(size: 15, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                        Text(Loc.ar ? "تم تحديث المواقيت · كنت في \(from)" : Loc.f("Prayer times updated · was {0}", from)).font(.sys(size: 12, weight: .bold)).foregroundStyle(Theme.zoneYellow).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button { model.keepNewPlace() } label: {
                        Text(Loc.ar ? "نعم، ابقَ في \(place.name)" : Loc.f("Yes, keep {0}", place.name)).font(.sys(size: 13, weight: .heavy)).foregroundStyle(.black)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 34).background(Theme.zoneYellow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain)
                    Button { model.goBackToPrevious() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward").font(.sys(size: 12, weight: .bold))
                            Text(Loc.ar ? "العودة إلى \(from)" : Loc.f("Back to {0}", from)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .font(.sys(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 34).background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(LinearGradient(colors: [Theme.zoneYellow.opacity(0.2), Theme.zoneYellow.opacity(0.07)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.zoneYellow.opacity(0.6), lineWidth: 1))
        }
    }

    private func bannerCard<T: View>(tint: Color, title: String, sub: String, icon: String = "mappin.and.ellipse",
                                     spinner: Bool = false, dot: Bool = false, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                if spinner { ProgressView().tint(tint).frame(width: 36, height: 36).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                else { iconBox(icon, fill: tint.opacity(0.16), fg: tint) }
                if dot { Circle().fill(tint).frame(width: 11, height: 11).overlay(Circle().stroke(Theme.card, lineWidth: 2)).offset(x: 3, y: -3) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(L(title)).font(.sys(size: 15, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                Text(L(sub)).font(.sys(size: 12, weight: .bold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            trailing()
            if icon != "location.slash.fill" {   // always allow picking a city by hand, e.g. when GPS does not work
                pill(nil, L("City"), Theme.ink, Theme.tile) { showPicker = true }
            }
        }
        .padding(.leading, 12).padding(.trailing, 10)
        .frame(minHeight: 56)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tint.opacity(0.5), lineWidth: 1))
    }

    private func iconBox(_ name: String, fill: Color, fg: Color) -> some View {
        Image(systemName: name).font(.sys(size: 17, weight: .bold)).foregroundStyle(fg)
            .frame(width: 36, height: 36).background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pill(_ icon: String?, _ title: String, _ fg: Color, _ bg: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.sys(size: 12, weight: .bold)) }
                Text(L(title)).font(.sys(size: 12.5, weight: .heavy)).lineLimit(1)
            }
            .foregroundStyle(fg).padding(.horizontal, 12).frame(minHeight: 34)
            .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: hero

    private func hero(next: PrayerEvent?, prev: PrayerEvent?, nowEv: PrayerEvent?, now: Date, fmt: DateFormatter) -> some View {
        let frac: Double = {
            guard let n = next, let p = prev else { return 0 }
            return max(0.02, min(1, now.timeIntervalSince(p.date) / n.date.timeIntervalSince(p.date)))
        }()
        let nowName: String = {
            guard let e = nowEv else { return "—" }
            return e.prayer == .sunrise ? (Loc.ar ? "الصبح" : L("Morning")) : e.prayer.name
        }()
        let ring = 88 * min(Theme.textScale, 1.3)
        return HStack(spacing: 8) {
            // "Now" off: the weather takes its place on the side; "Now" on: the weather sits in the middle.
            if !model.showNow { weatherBlock.frame(maxWidth: .infinity, alignment: .leading) } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(L("NOW")).font(.sys(size: 10, weight: .heavy)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.mint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Image(systemName: nowEv?.prayer.symbol ?? "clock").font(.sys(size: 13, weight: .semibold)).foregroundStyle(Theme.mint)
                    Text(nowName).font(.sys(size: 15, weight: .heavy, design: Theme.design)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(nowEv.map { fmt.string(from: $0.date) } ?? "--:--")
                    .font(.sys(size: 20, weight: .heavy, design: Theme.design)).monospacedDigit().foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.showNow { weatherBlock }

            ZStack {
                Circle().stroke(Theme.tile, lineWidth: 5)
                Circle().trim(from: 0, to: frac)
                    .stroke(LinearGradient(colors: [Theme.mint, Theme.mintDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: next?.prayer.symbol ?? "clock").font(.sys(size: 9, weight: .bold)).foregroundStyle(Theme.sunOrange)
                        Text(Loc.ar ? "\(next?.prayer.name ?? "—") بعد" : Loc.f("{0} in", next?.prayer.name ?? "—")).font(.sys(size: 10, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    Text(next.map { counter($0.date.timeIntervalSince(now)) } ?? "--:--:--")
                        .font(.sys(size: 13.5, weight: .heavy, design: Theme.design)).monospacedDigit()
                        .minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(countsDown: true))
                    Text(next.map { Loc.ar ? "عند " + fmt.string(from: $0.date) : Loc.f("at {0}", fmt.string(from: $0.date)) } ?? L("Not available here"))
                        .font(.sys(size: 9.5, weight: .heavy)).foregroundStyle(Theme.mint).lineLimit(1).minimumScaleFactor(0.5)
                }
                // keep every line inside the circle: the top and bottom lines are where the circle is narrowest
                .frame(width: ring * 0.7)
            }
            .frame(width: ring, height: ring)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }

    /// Temperature between the current prayer and the countdown ring
    private var weatherBlock: some View {
        let w = model.weather.snapshot
        let text: String = {
            guard let w else { return model.network.online ? "…" : "—" }
            return tempUnit == "f" ? "\(Int((w.tempC * 9 / 5 + 32).rounded()))°F" : "\(Int(w.tempC.rounded()))°C"
        }()
        let hum: String = {
            if let h = w?.humidity { return "\(Int(h.rounded()))%" }
            return w == nil && model.network.online ? "…" : "—"
        }()
        // two boxes, centred between the current prayer and the ring: temperature, then humidity
        return HStack(spacing: 6) {
            VStack(spacing: 3) {
                Image(systemName: w.map { WeatherService.symbol(code: $0.code, isDay: $0.isDay) } ?? (model.network.online ? "cloud" : "cloud.slash"))
                    .font(.sys(size: 17, weight: .bold)).symbolRenderingMode(.multicolor)
                Text(text).font(.sys(size: 12.5, weight: .heavy, design: Theme.design)).monospacedDigit().foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(minWidth: 44).padding(.horizontal, 6).padding(.vertical, 6)
            .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore).accessibilityLabel("Weather \(text)")
            VStack(spacing: 3) {
                Image(systemName: "drop.fill").font(.sys(size: 17, weight: .bold)).foregroundStyle(Color(hex: 0x5AC8FA))
                Text(hum).font(.sys(size: 12.5, weight: .heavy, design: Theme.design)).monospacedDigit().foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(minWidth: 44).padding(.horizontal, 6).padding(.vertical, 6)
            .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore).accessibilityLabel(Loc.ar ? "الرطوبة \(hum)" : "Humidity \(hum)")
        }
        .fixedSize()
    }

    // MARK: rows

    /// English name on the left, time in the middle, local name and bell on the right
    private func row(_ pr: Prayer, time: Date?, az: Int?, past: Bool, isNow: Bool, isNext: Bool, fmt: DateFormatter) -> some View {
        let muted = model.isMuted(pr)
        let alarm = model.isAlarm(pr)
        let tone = past ? Theme.muted : Theme.ink
        return HStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: pr.symbol).font(.sys(size: 17, weight: .semibold)).foregroundStyle(Theme.mint).frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(pr.name).font(.sys(size: 15, weight: .bold, design: Theme.design)).lineLimit(1).minimumScaleFactor(0.75)
                }
                if isNow { chip(L("NOW"), Theme.mint, Theme.onAccent) }
                else if isNext { chip(L("NEXT"), Theme.tile, Theme.ink) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(time.map { fmt.string(from: $0) } ?? "—")
                .font(.sys(size: 17, weight: .heavy, design: Theme.design)).monospacedDigit()
            HStack(spacing: 6) {
                if pr != .sunrise {
                    Button { model.toggleAlarm(pr) } label: {
                        Image(systemName: alarm ? "alarm.fill" : "alarm").font(.sys(size: 15, weight: .semibold))
                            .foregroundStyle(alarm ? Theme.mint : Theme.muted)
                            .frame(width: 34, height: 34).background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain)
                    .accessibilityLabel(Loc.ar ? (alarm ? "إيقاف الأذان لصلاة \(pr.name)" : "تشغيل الأذان لصلاة \(pr.name)")
                                               : (alarm ? "Turn off adhan for \(pr.name)" : "Turn on adhan for \(pr.name)"))
                }
                Button { model.toggleMute(pr) } label: {
                    Image(systemName: muted ? "bell.slash" : "bell.fill").font(.sys(size: 15, weight: .semibold))
                        .foregroundStyle(muted ? Theme.muted : Theme.mint)
                        .frame(width: 34, height: 34).background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain)
                .accessibilityLabel(muted ? "Turn on alert for \(pr.name)" : "Turn off alert for \(pr.name)")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(tone)
        .padding(.leading, 12).padding(.trailing, 10)
        .frame(minHeight: 48)
        .background(isNow ? Theme.rowNow : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isNow ? Theme.mint.opacity(0.55) : Theme.line.opacity(0.35), lineWidth: 1))
    }

    private func chip(_ t: String, _ bg: Color, _ fg: Color) -> some View {
        Text(t).font(.sys(size: 10, weight: .heavy)).foregroundStyle(fg)
            .padding(.horizontal, 7).frame(minHeight: 18).background(bg, in: Capsule())
    }

    // MARK: formatting

    private func counter(_ s: TimeInterval) -> String {
        let t = max(0, Int(s.rounded(.up)))
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
    private func since(_ s: TimeInterval) -> String {
        let m = max(0, Int(s / 60))
        if Loc.ar { return m >= 60 ? "منذ \(m / 60) س \(m % 60) د" : (m == 0 ? "الآن" : "منذ \(m) د") }
        return m >= 60 ? Loc.f("{0} h {1} min ago", "\(m / 60)", "\(m % 60)") : (m == 0 ? Loc.f("just now") : Loc.f("{0} min ago", "\(m)"))
    }
    private func ago(_ d: Date?, _ now: Date) -> String {
        guard let d else { return L("just now") }
        let m = Int(now.timeIntervalSince(d) / 60)
        if Loc.ar { return m < 1 ? "الآن" : (m < 60 ? "منذ \(m) د" : "منذ \(m / 60) س") }
        return m < 1 ? Loc.f("just now") : (m < 60 ? Loc.f("{0} min ago", "\(m)") : Loc.f("{0} h ago", "\(m / 60)"))
    }
    private func timeFormatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter(); f.timeZone = tz; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"; return f
    }
    /// `template` is a skeleton (e.g. "EEEEdMMMMyyyy"); the locale decides order and punctuation
    private func fmtDate(_ d: Date, _ tz: TimeZone, _ template: String) -> String {
        let f = DateFormatter(); f.timeZone = tz; f.locale = Loc.dateLocale; f.setLocalizedDateFormatFromTemplate(template); return f.string(from: d)
    }
    private func hijri(_ d: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .islamicUmmAlQura); f.timeZone = tz
        f.locale = (Loc.ar || Loc.hasUI) ? Loc.dateLocale : Locale(identifier: "en"); f.dateFormat = "d MMMM y"
        return f.string(from: d) + (Loc.ar ? " هـ" : Loc.f(" AH"))
    }
}
