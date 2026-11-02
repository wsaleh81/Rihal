import Foundation

enum Prayer: String, CaseIterable, Identifiable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha
    var id: String { rawValue }
    var name: String {
        if Loc.ar { return arabic }
        if Loc.isX, let n = LocX.prayer[Loc.langID]?[rawValue] { return n }
        return english
    }
    var english: String {
        switch self {
        case .fajr: return "Fajr"
        case .sunrise: return "Sunrise"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }
    /// Name in the language chosen in Settings (English labels stay English)
    var local: String { Loc.isX ? english : (Prayer.names[AppLang.current.id]?[self] ?? arabic) }
    var arabic: String {
        switch self {
        case .fajr: return "الفجر"
        case .sunrise: return "الشروق"
        case .dhuhr: return "الظهر"
        case .asr: return "العصر"
        case .maghrib: return "المغرب"
        case .isha: return "العشاء"
        }
    }
    static let names: [String: [Prayer: String]] = [
        "tr": [.fajr: "İmsak", .sunrise: "Güneş", .dhuhr: "Öğle", .asr: "İkindi", .maghrib: "Akşam", .isha: "Yatsı"],
        "fr": [.fajr: "Fajr (Aube)", .sunrise: "Lever du soleil", .dhuhr: "Dhuhr (Midi)", .asr: "Asr (Après-midi)", .maghrib: "Maghrib (Coucher)", .isha: "Isha (Nuit)"],
        "it": [.fajr: "Fajr (Alba)", .sunrise: "Alba solare", .dhuhr: "Dhuhr (Mezzogiorno)", .asr: "Asr (Pomeriggio)", .maghrib: "Maghrib (Tramonto)", .isha: "Isha (Notte)"],
        "de": [.fajr: "Fadschr (Morgen)", .sunrise: "Sonnenaufgang", .dhuhr: "Dhuhr (Mittag)", .asr: "Asr (Nachmittag)", .maghrib: "Maghrib (Abend)", .isha: "Ischa (Nacht)"],
        "nl": [.fajr: "Fadjr (Dageraad)", .sunrise: "Zonsopkomst", .dhuhr: "Dhuhr (Middag)", .asr: "Asr (Namiddag)", .maghrib: "Maghrib (Zonsondergang)", .isha: "Isja (Nacht)"],
        "es": [.fajr: "Fajr (Alba)", .sunrise: "Amanecer", .dhuhr: "Dhuhr (Mediodía)", .asr: "Asr (Tarde)", .maghrib: "Magrib (Atardecer)", .isha: "Isha (Noche)"]
    ]
    /// Sunrise is shown but is not a prayer you count down to
    var isPrayer: Bool { self != .sunrise }
}

struct CalcMethod: Identifiable, Hashable {
    let id: String
    let name: String
    let fajr: Double
    let isha: Double
    let ishaMinutes: Double

    static let all: [CalcMethod] = [
        .init(id: "kuwait", name: "Kuwait", fajr: 18, isha: 17.5, ishaMinutes: 0),
        .init(id: "mwl", name: "Muslim World League", fajr: 18, isha: 17, ishaMinutes: 0),
        .init(id: "egypt", name: "Egyptian General Authority", fajr: 19.5, isha: 17.5, ishaMinutes: 0),
        .init(id: "karachi", name: "Karachi (UIS)", fajr: 18, isha: 18, ishaMinutes: 0),
        .init(id: "isna", name: "ISNA (North America)", fajr: 15, isha: 15, ishaMinutes: 0),
        .init(id: "ummalqura", name: "Umm al-Qura (Makkah)", fajr: 18.5, isha: 0, ishaMinutes: 90)
    ]
    static func with(id: String) -> CalcMethod { all.first { $0.id == id } ?? all[0] }
}

struct PrayerEvent: Identifiable {
    let prayer: Prayer
    let date: Date
    var id: String { "\(prayer.rawValue)-\(date.timeIntervalSince1970)" }
}

enum PrayerCalculator {
    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func fix(_ a: Double, _ b: Double) -> Double {
        let v = a - b * floor(a / b)
        return v < 0 ? v + b : v
    }

    private static func julian(_ y: Int, _ m: Int, _ d: Int) -> Double {
        var y = y, m = m
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(Double(y) / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(d) + b - 1524.5
    }

    private static func sun(_ jd: Double) -> (decl: Double, eqt: Double) {
        let d = jd - 2451545.0
        let g = fix(357.529 + 0.98560028 * d, 360)
        let q = fix(280.459 + 0.98564736 * d, 360)
        let l = fix(q + 1.915 * sin(rad(g)) + 0.020 * sin(rad(2 * g)), 360)
        let e = 23.439 - 0.00000036 * d
        let ra = fix(deg(atan2(cos(rad(e)) * sin(rad(l)), cos(rad(l)))) / 15, 24)
        return (deg(asin(sin(rad(e)) * sin(rad(l)))), q / 15 - ra)
    }

    /// Times for one civil day (y-m-d) at the given place. Values are absolute Dates; missing ones are nil.
    static func day(year: Int, month: Int, day: Int, lat: Double, lon: Double,
                    method: CalcMethod, hanafi: Bool) -> [Prayer: Date] {
        let jd = julian(year, month, day) - lon / (15 * 24)
        func midDay(_ t: Double) -> Double { fix(12 - sun(jd + t).eqt, 24) }
        func angle(_ a: Double, _ t: Double, ccw: Bool) -> Double {
            let dec = sun(jd + t).decl
            let x = (-sin(rad(a)) - sin(rad(dec)) * sin(rad(lat))) / (cos(rad(dec)) * cos(rad(lat)))
            let tt = deg(acos(x)) / 15
            return midDay(t) + (ccw ? -tt : tt)
        }
        func asr(_ f: Double, _ t: Double) -> Double {
            let dec = sun(jd + t).decl
            let a = -deg(atan(1 / (f + tan(rad(abs(lat - dec))))))
            return angle(a, t, ccw: false)
        }
        var fajr = 5.0, sunrise = 6.0, dhuhr = 12.0, asrT = 13.0, sunset = 18.0, isha = 18.0
        for _ in 0..<2 {
            fajr = angle(method.fajr, fajr / 24, ccw: true)
            sunrise = angle(0.833, sunrise / 24, ccw: true)
            dhuhr = midDay(dhuhr / 24)
            asrT = asr(hanafi ? 2 : 1, asrT / 24)
            sunset = angle(0.833, sunset / 24, ccw: false)
            isha = angle(method.isha, isha / 24, ccw: false)
        }
        // High-latitude rule (angle-based): when the twilight angle is never reached, or the gap to
        // sunrise/sunset is larger than angle/60 of the night, use that share of the night instead.
        if !sunrise.isNaN && !sunset.isNaN {
            let night = fix(sunrise - sunset, 24)
            if method.fajr > 0 {
                let portion = method.fajr / 60 * night
                if fajr.isNaN || fix(sunrise - fajr, 24) > portion { fajr = sunrise - portion }
            }
            if method.isha > 0 {
                let portion = method.isha / 60 * night
                if isha.isNaN || fix(isha - sunset, 24) > portion { isha = sunset + portion }
            }
        }
        if method.ishaMinutes > 0 { isha = sunset + method.ishaMinutes / 60 }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let base = utc.date(from: DateComponents(year: year, month: month, day: day)) else { return [:] }
        let offset = lon / 15
        func make(_ h: Double) -> Date? {
            if h.isNaN || h.isInfinite { return nil }
            return base.addingTimeInterval((h - offset) * 3600)
        }
        var out: [Prayer: Date] = [:]
        let pairs: [(Prayer, Double)] = [(.fajr, fajr), (.sunrise, sunrise), (.dhuhr, dhuhr), (.asr, asrT), (.maghrib, sunset), (.isha, isha)]
        for (p, h) in pairs {
            if let d = make(h) {
                // per-prayer manual offset in minutes (Settings > Adjust times)
                let off = Double(UserDefaults.standard.integer(forKey: "off_" + p.rawValue))
                out[p] = d.addingTimeInterval(off * 60)
            }
        }
        return out
    }

    /// Three days (yesterday, today, tomorrow) in the place's time zone, sorted.
    static func events(around now: Date, lat: Double, lon: Double, timeZone: TimeZone,
                       method: CalcMethod, hanafi: Bool) -> (today: [Prayer: Date], all: [PrayerEvent]) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: now)
        var today: [Prayer: Date] = [:]
        var all: [PrayerEvent] = []
        for k in -1...1 {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            guard let anchor = utc.date(from: DateComponents(year: c.year, month: c.month, day: (c.day ?? 1) + k)) else { continue }
            let u = utc.dateComponents([.year, .month, .day], from: anchor)
            let t = day(year: u.year!, month: u.month!, day: u.day!, lat: lat, lon: lon, method: method, hanafi: hanafi)
            if k == 0 { today = t }
            for (p, d) in t { all.append(PrayerEvent(prayer: p, date: d)) }
        }
        all.sort { $0.date < $1.date }
        return (today, all)
    }
}

struct AppLang: Identifiable, Hashable {
    let id: String, title: String
    static let all = [
        AppLang(id: "ar", title: "العربية · Arabic"), AppLang(id: "en", title: "English · English"), AppLang(id: "tr", title: "Türkçe · Turkish"),
        AppLang(id: "fr", title: "Français · French"), AppLang(id: "it", title: "Italiano · Italian"),
        AppLang(id: "de", title: "Deutsch · German"), AppLang(id: "nl", title: "Nederlands · Dutch"),
        AppLang(id: "es", title: "Español · Spanish"), AppLang(id: "ur", title: "اردو · Urdu"),
        AppLang(id: "ta", title: "தமிழ் · Tamil"), AppLang(id: "ru", title: "Русский · Russian")
    ]
    static var current: AppLang {
        let id = UserDefaults.standard.string(forKey: "langID") ?? "ar"
        return all.first { $0.id == id } ?? all[0]
    }
    var isRTL: Bool { id == "ar" || id == "ur" }
    /// The language's own name only ("Türkçe"), as in the language picker.
    var native: String { title.components(separatedBy: " · ").first ?? title }
}
