import Foundation
import UserNotifications
import UIKit
import AVFoundation

/// Local (on-device) prayer-time notifications. No server involved.
enum Notifier {
    static func requestAuth(_ done: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            DispatchQueue.main.async { done?(ok) }
        }
    }

    static func status(_ done: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { done(s.authorizationStatus) }
        }
    }

    static func openIPhoneSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    /// Adhan sounds (Sounds/*.caf). iPhone plays at most 30 seconds, so the complete adhans are their first 29 seconds.
    /// "adhan" is the default recording (allahu-akbar.caf, supplied by the app owner).
    static let sounds: [(key: String, file: String, short: Bool)] = [
        ("adhan", "allahu-akbar", true), ("azan1", "azan1", true), ("azan2", "azan2", true), ("azan3", "azan3", true),
        ("azan4", "azan4", false), ("azan5", "azan5", false), ("azan6", "azan6", false), ("azan7", "azan7", false),
        ("azan8", "azan8", false), ("azan9", "azan9", false), ("azan10", "azan10", false), ("azan11", "azan11", false)
    ]
    static let fajrSounds: [(key: String, file: String, short: Bool)] = [("fajr1", "fajr1", true)]
    static func file(_ key: String) -> String { ((sounds + fajrSounds).first { $0.key == key } ?? sounds[0]).file }

    /// "أذان ١ – قصير", "Azan 4 – complete", "Default"
    static func label(_ key: String) -> String {
        guard let s = (sounds + fajrSounds).first(where: { $0.key == key }), key != "adhan" else { return Loc.ar ? "الافتراضي" : L("Default") }
        let n = Int(key.filter(\.isNumber)) ?? 0
        let fajr = key.hasPrefix("fajr")
        if Loc.ar {
            let digits = Array("٠١٢٣٤٥٦٧٨٩")
            let arN = String(String(n).map { digits[$0.wholeNumberValue ?? 0] })
            return (fajr ? "أذان الفجر" : "أذان \(arN)") + " – " + (s.short ? "قصير" : "كامل")
        }
        return (fajr ? L("Fajr azan") : "Azan \(n)") + " – " + L(s.short ? "short" : "complete")
    }

    private static var player: AVAudioPlayer?

    /// Plays a sound in the app, for the play button in Settings. A second tap stops it.
    static func preview(_ key: String) {
        if player?.isPlaying == true { player?.stop(); player = nil; return }
        guard let url = Bundle.main.url(forResource: file(key), withExtension: "caf") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
    static func previewAzan() { preview(UserDefaults.standard.string(forKey: "adhanSound") ?? "adhan") }

    struct Options {
        var sound = "adhan", fajrSound = "adhan"
        var morning = true, evening = true, afterPrayer = false, friday = true
    }

    /// Each prayer has two switches: the notification (bell) and the alarm (adhan sound).
    /// Alarm on: the alert plays the adhan. Alarm off, bell on: a normal notification. Both off: nothing.
    /// Azkar reminders (same timings as the Android app) are added after the prayer alerts; iPhone keeps 64 at most.
    static func schedule(place: Place, method: CalcMethod, hanafi: Bool, on: Bool, before: Int, muted: [Prayer: Bool], alarm: [Prayer: Bool], opt: Options = Options()) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard on else { return }
        let now = Date()
        var items: [(Date, Prayer, Bool)] = []          // date, prayer, isReminder
        for day in 0..<7 {
            let d = now.addingTimeInterval(Double(day) * 86400)
            let ev = PrayerCalculator.events(around: d, lat: place.lat, lon: place.lon, timeZone: place.timeZone,
                                             method: method, hanafi: hanafi).today
            for (p, t) in ev where muted[p] != true || alarm[p] == true {
                if t > now { items.append((t, p, false)) }
                if before > 0, p != .sunrise {
                    let r = t.addingTimeInterval(-Double(before) * 60)
                    if r > now { items.append((r, p, true)) }
                }
            }
        }
        items.sort { $0.0 < $1.0 }
        let azkar = azkarReminders(place: place, method: method, hanafi: hanafi, opt: opt, now: now)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = place.timeZone
        let f = DateFormatter(); f.timeZone = place.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"
        func add(_ id: String, _ c: UNNotificationContent, _ t: Date) {
            var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: t)
            comps.timeZone = place.timeZone
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        for (t, p, reminder) in items.prefix(64 - azkar.count) {
            let c = UNMutableNotificationContent()
            let when = reminder ? t.addingTimeInterval(Double(before) * 60) : t
            c.title = Loc.ar && p != .sunrise ? "صلاة \(p.name)" : p.name
            c.body = Loc.ar ? (reminder ? "\(p.name) بعد \(before) دقيقة · \(f.string(from: when)) · \(place.name)" : "حان الآن وقت \(p.name) · \(f.string(from: when)) · \(place.name)")
                       : ((reminder ? Loc.f("{0} in {1} min", p.name, "\(before)") : Loc.f("It is time for {0}", p.name)) + " · \(f.string(from: when)) · \(place.name)")
            let snd = file(p == .fajr ? opt.fajrSound : opt.sound) + ".caf"
            c.sound = reminder ? nil : (alarm[p] == true ? UNNotificationSound(named: UNNotificationSoundName(snd)) : .default)
            add("\(p.rawValue)-\(Int(t.timeIntervalSince1970))", c, t)
        }
        for (i, r) in azkar.enumerated() {
            let c = UNMutableNotificationContent()
            c.title = r.title; c.body = r.body; c.sound = .default
            c.userInfo = ["azcat": r.cat]
            add("azkar-\(i)-\(Int(r.at.timeIntervalSince1970))", c, r.at)
        }
    }

    /// Morning: 15 min after Fajr, then every 2 hours until Dhuhr. Evening: 15 min after Asr, then every 2 hours until Isha.
    /// After prayer: 15 min after each prayer. Friday: Surat al-Kahf 2½ h before Dhuhr, the hour of dua 1 h before Maghrib.
    /// A finished set gets no more reminders that day. Only the next 2 days, so the prayer alerts keep most of the 64 places.
    static func azkarReminders(place: Place, method: CalcMethod, hanafi: Bool, opt: Options, now: Date) -> [(at: Date, cat: String, title: String, body: String)] {
        let store = AzkarStore.shared
        store.sync(place: place, method: method, hanafi: hanafi)
        let M = 60.0
        let body = Loc.ar ? "لم تكتمل بعد، اضغط للمتابعة" : L("Not finished yet. Tap to continue.")
        let names = Loc.ar ? ["أذكار الصباح", "أذكار المساء", "أذكار بعد الصلاة"] : [L("Morning azkar"), L("Evening azkar"), L("After-prayer azkar")]
        var ev: [PrayerEvent] = []
        for day in 0..<3 {
            ev += PrayerCalculator.events(around: now.addingTimeInterval(Double(day) * 86400), lat: place.lat, lon: place.lon,
                                          timeZone: place.timeZone, method: method, hanafi: hanafi).all
        }
        var seen = Set<Int>()
        ev = ev.filter { seen.insert(Int($0.date.timeIntervalSince1970)).inserted }.sorted { $0.date < $1.date }
        let limit = now.addingTimeInterval(2 * 86400)
        func next(_ e: PrayerEvent, _ p: Prayer) -> PrayerEvent? { ev.first { $0.prayer == p && $0.date > e.date } }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = place.timeZone
        func isFriday(_ d: Date) -> Bool { cal.component(.weekday, from: d) == 6 }
        var out: [(at: Date, cat: String, title: String, body: String)] = []
        for e in ev where e.date < limit {
            if e.prayer == .fajr, opt.morning, let end = next(e, .dhuhr), !store.finished("morning", periodStart: e.date) {
                var t = e.date.addingTimeInterval(15 * M)
                while t < end.date { if t > now { out.append((t, "morning", names[0], body)) }; t.addTimeInterval(120 * M) }
            }
            if e.prayer == .asr, opt.evening, let end = next(e, .isha), !store.finished("evening", periodStart: e.date) {
                var t = e.date.addingTimeInterval(15 * M)
                while t < end.date { if t > now { out.append((t, "evening", names[1], body)) }; t.addTimeInterval(120 * M) }
            }
            if opt.afterPrayer, e.prayer != .sunrise, e.date.addingTimeInterval(15 * M) > now, !store.finished("afterPrayer", periodStart: e.date) {
                out.append((e.date.addingTimeInterval(15 * M), "afterPrayer", names[2], "\(e.prayer.name) · \(body)"))
            }
            if opt.friday, isFriday(e.date) {
                if e.prayer == .dhuhr, e.date.addingTimeInterval(-150 * M) > now {
                    out.append((e.date.addingTimeInterval(-150 * M), "m:0",
                                Loc.ar ? "يوم الجمعة: سورة الكهف" : L("Friday: Surat al-Kahf"),
                                Loc.ar ? "اقرأ سورة الكهف وأكثر من الصلاة على النبي ﷺ" : L("Read Surat al-Kahf and send many prayers on the Prophet ﷺ")))
                }
                if e.prayer == .maghrib, e.date.addingTimeInterval(-60 * M) > now {
                    out.append((e.date.addingTimeInterval(-60 * M), "m:0",
                                Loc.ar ? "ساعة الإجابة يوم الجمعة" : L("Friday: the hour of answered dua"),
                                Loc.ar ? "آخر ساعة قبل المغرب، أكثر من الدعاء" : L("The last hour before Maghrib. Make plenty of dua.")))
                }
            }
        }
        return Array(out.sorted { $0.at < $1.at }.prefix(22))
    }
}

/// Show the banner and play the sound even while the app is open.
final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .sound])
    }
    /// Tapping an azkar reminder opens that list.
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler h: @escaping () -> Void) {
        if let cat = r.notification.request.content.userInfo["azcat"] as? String {
            DispatchQueue.main.async { AzkarStore.shared.openRequest = cat }
        }
        h()
    }
}
