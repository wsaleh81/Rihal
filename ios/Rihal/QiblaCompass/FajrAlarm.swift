import SwiftUI
import AVFoundation
import UIKit
import UserNotifications

// MARK: - Fajr rug alarm (iPhone)
// iPhone can't keep a screen locked over everything, so at Fajr the alert repeats every 2 minutes for 30 minutes
// until the user opens the app and photographs their prayer rug (or chooses "not praying today", or the emergency stop).
// The photo is compared on the phone with the one saved in Settings. Same rules and streak as the Android app.

/// A photo's "fingerprint": colour mix with brightness taken out, hue spread, and how busy the pattern is.
struct RugPrint: Codable {
    var rg: [Double]
    var hue: [Double]
    var edge: Double
    var lum: Double
    var ok: Bool
}

enum RugMatch {
    static let threshold = 0.8
    private static let N = 96

    static func features(_ img: CGImage) -> RugPrint {
        let w = img.width, h = img.height, s = Int(Double(min(w, h)) * 0.7)
        let crop = img.cropping(to: CGRect(x: (w - s) / 2, y: (h - s) / 2, width: s, height: s)) ?? img
        var px = [UInt8](repeating: 0, count: N * N * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        px.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4,
                                   space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .medium
                ctx.draw(crop, in: CGRect(x: 0, y: 0, width: N, height: N))
            }
        }
        var rg = [Double](repeating: 0, count: 64), hue = [Double](repeating: 0, count: 12), gray = [Double](repeating: 0, count: N * N)
        var lum = 0.0, cnt = 0
        for k in 0..<(N * N) {
            let r = Double(px[k * 4]), g = Double(px[k * 4 + 1]), b = Double(px[k * 4 + 2]), sum = r + g + b
            gray[k] = sum / 3; lum += sum / 3
            if sum < 40 || sum > 735 { continue }
            let cr = r / sum, cg = g / sum
            rg[min(7, Int(cr * 16)) * 8 + min(7, Int(cg * 16))] += 1; cnt += 1
            let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
            if d > 18 {
                var H: Double
                if mx == r { H = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
                else if mx == g { H = (b - r) / d + 2 }
                else { H = (r - g) / d + 4 }
                let bin = Int((H * 2 + 12).truncatingRemainder(dividingBy: 12))
                hue[max(0, min(11, bin))] += d / mx
            }
        }
        var edge = 0.0
        for y in 1..<(N - 1) { for x in 1..<(N - 1) {
            let k = y * N + x
            edge += abs(gray[k + 1] - gray[k - 1]) + abs(gray[k + N] - gray[k - N])
        } }
        func norm(_ a: [Double]) -> [Double] { let t = a.reduce(0, +); return t > 0 ? a.map { $0 / t } : a }
        return RugPrint(rg: norm(rg), hue: norm(hue), edge: edge / Double(N * N), lum: lum / Double(N * N), ok: cnt > N * N / 4)
    }

    private static func bhatt(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + ($1.0 * $1.1).squareRoot() }
    }

    /// 0…1: how alike two fingerprints are. A plain surface (no pattern) never passes.
    static func score(_ a: RugPrint, _ b: RugPrint) -> Double {
        let c = bhatt(a.rg, b.rg), h = bhatt(a.hue, b.hue)
        let e = min(a.edge, b.edge) / max(a.edge, b.edge, 0.01)
        if e < 0.35 { return min(0.5, 0.6 * c + 0.3 * h) }
        return 0.6 * c + 0.3 * h + 0.1 * min(1, e * 1.4)
    }
}

struct FajrStreak: Codable {
    var cur = 0
    var best = 0
    var days: [String: String] = [:]      // "2026-11-05": "ok" | "skip" | "miss"
}

final class FajrStore: ObservableObject {
    static let shared = FajrStore()
    enum Screen: String, Identifiable { case alarm, camera, setup, done; var id: String { rawValue } }

    @Published var on: Bool { didSet { d.set(on, forKey: "fajrOn") } }
    @Published var emer: Int { didSet { d.set(emer, forKey: "fajrEmer") } }
    @Published var rug: RugPrint? { didSet { d.set(try? JSONEncoder().encode(rug), forKey: "rugRef") } }
    @Published var streak: FajrStreak { didSet { d.set(try? JSONEncoder().encode(streak), forKey: "fajrStreak") } }
    @Published var screen: Screen? = nil
    @Published var since: Date = Date()           // the Fajr time now ringing
    @Published var lateResult = false
    var onChange: (() -> Void)?                   // rebuild the notification schedule
    private let d = UserDefaults.standard
    private var times: [Double] { get { d.array(forKey: "fajrTimes") as? [Double] ?? [] } set { d.set(newValue, forKey: "fajrTimes") } }
    static let window: TimeInterval = 30 * 60     // keeps ringing for 30 minutes
    static let repeatEvery: TimeInterval = 120

    init() {
        on = d.bool(forKey: "fajrOn")
        emer = d.object(forKey: "fajrEmer") == nil ? 10 : d.integer(forKey: "fajrEmer")
        rug = d.data(forKey: "rugRef").flatMap { try? JSONDecoder().decode(RugPrint.self, from: $0) }
        streak = d.data(forKey: "fajrStreak").flatMap { try? JSONDecoder().decode(FajrStreak.self, from: $0) } ?? FajrStreak()
    }

    var active: Bool { on && rug != nil }

    static func dayKey(_ t: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = tz
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: t)
    }

    func mark(_ key: String, _ v: String) {
        var s = streak
        if s.days[key] == "ok" || s.days[key] == v { return }
        s.days[key] = v
        if v == "ok" { s.cur += 1; s.best = max(s.best, s.cur) }
        if v == "miss" { s.cur = 0 }
        let keys = s.days.keys.sorted()
        for k in keys.prefix(max(0, keys.count - 60)) { s.days[k] = nil }
        streak = s
    }

    static func sunrise(after t: Date, place: Place, method: CalcMethod, hanafi: Bool) -> Date {
        PrayerCalculator.events(around: t, lat: place.lat, lon: place.lon, timeZone: place.timeZone, method: method, hanafi: hanafi)
            .all.first { $0.prayer == .sunrise && $0.date > t }?.date ?? t.addingTimeInterval(90 * 60)
    }

    /// Alarms that rang with no rug photo before sunrise break the streak. Opens the alarm screen if one is ringing now.
    func sync(place: Place, method: CalcMethod, hanafi: Bool) {
        let now = Date()
        var keep: [Double] = []
        for t in times {
            let date = Date(timeIntervalSince1970: t), key = Self.dayKey(date, place.timeZone)
            if date > now { keep.append(t); continue }
            if streak.days[key] != nil { continue }
            if now > Self.sunrise(after: date, place: place, method: method, hanafi: hanafi) { mark(key, "miss") } else { keep.append(t) }
        }
        times = keep
        if let t = ringingTime(now) { since = t; if screen == nil || screen == .done { screen = .alarm } }
    }

    /// The Fajr time ringing now (within the 30 minutes, with no photo / skip yet), if any.
    func ringingTime(_ now: Date = Date()) -> Date? {
        guard active else { return nil }
        for t in times {
            let date = Date(timeIntervalSince1970: t)
            if date <= now && now < date.addingTimeInterval(Self.window),
               streak.days[Self.dayKey(date, FajrTZ.tz)] == nil { return date }
        }
        return nil
    }

    /// Alerts for the next Fajr (and the one after, if within 36 hours): one every 2 minutes for 30 minutes.
    func requests(place: Place, method: CalcMethod, hanafi: Bool, soundFile: String) -> [UNNotificationRequest] {
        guard active else { times = []; return [] }
        let now = Date()
        var fajrs: [Date] = []
        for day in 0..<3 {
            let ev = PrayerCalculator.events(around: now.addingTimeInterval(Double(day) * 86400), lat: place.lat, lon: place.lon,
                                             timeZone: place.timeZone, method: method, hanafi: hanafi).today
            if let f = ev[.fajr], f.addingTimeInterval(Self.window) > now, f < now.addingTimeInterval(36 * 3600), !fajrs.contains(f) { fajrs.append(f) }
        }
        fajrs.sort()
        times = Array(Set(times.filter { $0 < now.timeIntervalSince1970 } + fajrs.map(\.timeIntervalSince1970))).sorted()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = place.timeZone
        var out: [UNNotificationRequest] = []
        for f in fajrs.prefix(2) {
            if streak.days[Self.dayKey(f, place.timeZone)] != nil { continue }      // already done or skipped today
            for i in 0..<Int(Self.window / Self.repeatEvery) {
                let at = f.addingTimeInterval(Double(i) * Self.repeatEvery)
                if at <= now { continue }
                let c = UNMutableNotificationContent()
                c.title = Loc.ar ? "صلاة الفجر" : Prayer.fajr.name
                c.body = Loc.ar ? "صوّر السجادة لإيقاف المنبّه" : L("Photograph your prayer rug to stop the alarm")
                c.sound = UNNotificationSound(named: UNNotificationSoundName(soundFile))
                c.interruptionLevel = .timeSensitive
                c.userInfo = ["fajr": f.timeIntervalSince1970]
                var comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
                comps.timeZone = place.timeZone
                out.append(UNNotificationRequest(identifier: "fajr-\(Int(f.timeIntervalSince1970))-\(i)", content: c,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
        return out
    }

    /// Fajr times covered by the rug alarm (the plain Fajr alert is left out for them).
    var alarmTimes: Set<Int> { Set(times.map { Int($0) }) }

    /// Silence today's alarm: remove the remaining repeats and the delivered ones.
    func stopRinging() {
        let c = UNUserNotificationCenter.current()
        c.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix("fajr-\(Int(self.since.timeIntervalSince1970))") }
            c.removePendingNotificationRequests(withIdentifiers: ids)
        }
        c.getDeliveredNotifications { ns in
            c.removeDeliveredNotifications(withIdentifiers: ns.map(\.request.identifier).filter { $0.hasPrefix("fajr-") })
        }
    }

    /// A Fajr alert was delivered or tapped: open the alarm screen unless today is already done or skipped.
    func ring(_ t: Date) {
        guard active, streak.days[Self.dayKey(t, FajrTZ.tz)] == nil, Date() < t.addingTimeInterval(Self.window + 600) else { return }
        since = t
        if screen == nil || screen == .done { screen = .alarm }
    }

    func finish(_ v: String) {
        mark(Self.dayKey(since, FajrTZ.tz), v)
        stopRinging()
        onChange?()
    }
}

/// The place's time zone, read where the store has no AppModel at hand.
enum FajrTZ {
    static var tz: TimeZone {
        if let s = UserDefaults.standard.string(forKey: "lastPlaceTZ"), let z = TimeZone(identifier: s) { return z }
        return .current
    }
}

// MARK: - Camera

final class RugCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var torch = false
    @Published var failed = false
    private var device: AVCaptureDevice?
    private var last: CGImage?
    private let ci = CIContext()
    private let q = DispatchQueue(label: "rihal.rugcam")

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { DispatchQueue.main.async { self.failed = true }; return }
            self.q.async {
                guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: dev) else { DispatchQueue.main.async { self.failed = true }; return }
                self.device = dev
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720
                if self.session.canAddInput(input) { self.session.addInput(input) }
                let out = AVCaptureVideoDataOutput()
                out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                out.setSampleBufferDelegate(self, queue: self.q)
                if self.session.canAddOutput(out) { self.session.addOutput(out) }
                self.session.commitConfiguration()
                self.session.startRunning()
                // in the dark, turn the flash on by itself
                self.q.asyncAfter(deadline: .now() + 1.2) {
                    if let f = self.last, RugMatch.features(f).lum < 45 { DispatchQueue.main.async { self.setTorch(true) } }
                }
            }
        }
    }

    func stop() {
        setTorch(false)
        q.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func setTorch(_ on: Bool) {
        guard let dev = device, dev.hasTorch else { return }
        try? dev.lockForConfiguration()
        dev.torchMode = on ? .on : .off
        dev.unlockForConfiguration()
        torch = on
    }

    func frame() -> CGImage? { q.sync { last } }

    private var n = 0
    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        n += 1
        guard n % 6 == 0, let pb = CMSampleBufferGetImageBuffer(sb) else { return }   // about 5 pictures a second is plenty
        let im = CIImage(cvPixelBuffer: pb)
        last = ci.createCGImage(im, from: im.extent)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class V: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var pl: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> V { let v = V(); v.pl.session = session; v.pl.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ uiView: V, context: Context) {}
}

// MARK: - Screens

struct FajrAlarmView: View {
    @ObservedObject var store = FajrStore.shared
    @EnvironmentObject var model: AppModel
    @StateObject private var cam = RugCamera()
    @State private var msg = ""
    @State private var holding = false
    let screen: FajrStore.Screen

    var body: some View {
        Group {
            switch screen {
            case .alarm: alarm
            case .camera, .setup: camera
            case .done: done
            }
        }
        .environment(\.layoutDirection, AppLang.current.isRTL ? .rightToLeft : .leftToRight)
        .onAppear { if screen == .camera || screen == .setup { cam.start() } }
        .onDisappear { cam.stop() }
        .interactiveDismissDisabled(screen == .alarm)
    }

    private func arDigits(_ n: Int) -> String {
        guard Loc.ar else { return String(n) }
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(n).map { digits[$0.wholeNumberValue ?? 0] })
    }

    // 1 · the alarm
    private var alarm: some View {
        VStack(spacing: 0) {
            Image(systemName: "moon").font(.system(size: 42, weight: .regular)).foregroundStyle(Color(hex: 0x9CC9F5)).padding(.top, 50)
            Text(Loc.ar ? "صلاة الفجر" : Prayer.fajr.name).font(.sys(size: 28, weight: .heavy)).padding(.top, 8)
            Text(timeString(store.since)).font(.system(size: 64, weight: .heavy, design: .rounded)).monospacedDigit()
            Text(Loc.ar ? "الصلاة خير من النوم" : L("Prayer is better than sleep")).font(.sys(size: 17)).opacity(0.8)
            ZStack {
                Circle().fill(Color(hex: 0x2F9BE8).opacity(0.12)).frame(width: 186, height: 186)
                Circle().fill(Color(hex: 0x2F9BE8)).frame(width: 100, height: 100)
                Image(systemName: "speaker.wave.2").font(.system(size: 40, weight: .regular))
            }
            .padding(.vertical, 26)
            Button { store.screen = .camera } label: {
                Label(Loc.ar ? "صوّر السجادة" : L("Photograph the rug"), systemImage: "camera")
                    .font(.sys(size: 19, weight: .heavy)).foregroundStyle(Color(hex: 0x0E1726))
                    .frame(maxWidth: .infinity, minHeight: 60).background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { store.finish("skip"); store.screen = nil } label: {
                Text(Loc.ar ? "لا أصلي اليوم" : L("Not praying today")).font(.sys(size: 15)).underline().opacity(0.75).padding(10)
            }
            .buttonStyle(.plain).padding(.top, 6)
            Spacer(minLength: 0)
            if store.emer > 0 { emergency }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadialGradient(colors: [Color(hex: 0x1D4F86), Color(hex: 0x0A1424)], center: .init(x: 0.5, y: 0.2), startRadius: 0, endRadius: 600).ignoresSafeArea())
    }

    private var emergency: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = store.since.addingTimeInterval(Double(store.emer) * 60).timeIntervalSince(ctx.date)
            let open = left <= 0
            HStack(spacing: 8) {
                Image(systemName: open ? "lock.open" : "lock")
                Text(open ? (Loc.ar ? "إيقاف طارئ · اضغط مطوّلًا ٥ ثوانٍ" : L("Emergency stop · hold 5 seconds"))
                          : (Loc.ar ? "إيقاف طارئ · بعد \(mmss(left))" : Loc.f("Emergency stop in {0}", mmss(left))))
            }
            .font(.sys(size: 13))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(Color.red.opacity(0.55)).frame(width: holding ? g.size.width : 0)
                        .animation(holding ? .linear(duration: 5) : .easeOut(duration: 0.2), value: holding)
                }
            }
            .background(open ? Color.red.opacity(0.18) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(open ? 0.95 : 0.55)
            .onLongPressGesture(minimumDuration: 5, perform: {
                guard open else { return }
                holding = false
                store.finish("miss"); store.screen = nil
            }, onPressingChanged: { p in if open { holding = p } })
        }
    }

    // 2 · the camera
    private var camera: some View {
        let setup = screen == .setup
        return ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: cam.session).ignoresSafeArea()
            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.92), lineWidth: 3)
                .padding(.horizontal, 44).padding(.top, 170).padding(.bottom, 210)
            VStack {
                HStack {
                    Button { store.screen = setup ? nil : .alarm } label: { circleIcon("xmark") }
                    Spacer()
                    Button { cam.setTorch(!cam.torch) } label: { circleIcon("bolt.fill", on: cam.torch) }
                }
                .padding(.horizontal, 18).padding(.top, 10)
                Text(setup ? (Loc.ar ? "صوّر سجادة صلاتك داخل الإطار" : L("Photograph your prayer rug inside the frame"))
                           : (Loc.ar ? "ضع السجادة داخل الإطار" : L("Fit the rug inside the frame")))
                    .font(.sys(size: 18, weight: .heavy)).shadow(radius: 4).padding(.top, 20)
                Text(setup ? (Loc.ar ? "ستُقارن بها كل صباح، وتبقى على هاتفك فقط" : L("It's compared every morning and stays on your phone"))
                           : (Loc.ar ? "الفلاش يعمل تلقائيًا في الظلام" : L("The flash turns on by itself in the dark")))
                    .font(.sys(size: 13)).opacity(0.85).shadow(radius: 4)
                Spacer()
                if !msg.isEmpty || cam.failed {
                    Text(cam.failed ? (Loc.ar ? "تعذّر فتح الكاميرا. اسمح لرحّال باستخدام الكاميرا من الإعدادات." : L("Can't open the camera. Allow Rihal to use the camera in Settings.")) : msg)
                        .font(.sys(size: 15, weight: .heavy)).padding(12).frame(maxWidth: .infinity)
                        .background(Color(hex: 0xFF5A5F).opacity(0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 20).padding(.bottom, 20)
                }
                Button { shoot() } label: {
                    ZStack { Circle().stroke(.white, lineWidth: 5).frame(width: 78, height: 78); Circle().fill(.white).frame(width: 58, height: 58) }
                }
                .padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
    }

    private func circleIcon(_ n: String, on: Bool = false) -> some View {
        Image(systemName: n).font(.system(size: 19, weight: .semibold)).foregroundStyle(on ? Color.black : Color.white)
            .frame(width: 46, height: 46).background(on ? Color(hex: 0xFFD560) : Color.white.opacity(0.16), in: Circle())
    }

    private func shoot() {
        guard let img = cam.frame() else { return }
        let f = RugMatch.features(img)
        if f.lum < 18 || !f.ok {
            msg = Loc.ar ? "المكان مظلم، شغّل الفلاش" : L("Too dark. Turn on the flash")
            UINotificationFeedbackGenerator().notificationOccurred(.error); return
        }
        if screen == .setup {
            store.rug = f; store.on = true; store.screen = nil; store.onChange?()
            UINotificationFeedbackGenerator().notificationOccurred(.success); return
        }
        guard let ref = store.rug, RugMatch.score(ref, f) >= RugMatch.threshold else {
            msg = Loc.ar ? "هذه ليست سجادتك، حاول مرة أخرى" : L("That's not your rug. Try again")
            UINotificationFeedbackGenerator().notificationOccurred(.error); return
        }
        let late = Date() > FajrStore.sunrise(after: store.since.addingTimeInterval(-60), place: model.place, method: model.method, hanafi: model.hanafi)
        store.lateResult = late
        store.finish(late ? "miss" : "ok")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.screen = .done
    }

    // 3 · after the rug matched
    private var done: some View {
        let keys = (0..<7).reversed().map { FajrStore.dayKey(store.since.addingTimeInterval(-Double($0) * 86400), model.place.timeZone) }
        return VStack(spacing: 0) {
            ZStack {
                Circle().fill(Theme.mintDeep).frame(width: 104, height: 104).shadow(color: Theme.mintDeep.opacity(0.4), radius: 12, y: 8)
                Image(systemName: "checkmark").font(.system(size: 46, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.top, 60)
            Text(Loc.ar ? "تقبّل الله" : L("May Allah accept it")).font(.sys(size: 30, weight: .heavy)).foregroundStyle(Theme.ink).padding(.top, 18)
            VStack(spacing: 6) {
                if store.lateResult { Text(Loc.ar ? "بعد الشروق، بدأت سلسلة جديدة" : L("After sunrise: a new streak begins")).font(.sys(size: 13)).foregroundStyle(Theme.muted) }
                Text(arDigits(store.streak.cur)).font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundStyle(Theme.mintDeep)
                Text(Loc.ar ? "يومًا متتاليًا في صلاة الفجر" : L("days in a row praying Fajr")).font(.sys(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { i, k in
                        let v = store.streak.days[k]
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(v == "ok" ? Theme.mintDeep : v == "miss" ? Theme.muted.opacity(0.35) : Theme.tile)
                            .frame(width: 28, height: 28)
                            .overlay(Text(v == "ok" ? "✓" : v == "skip" ? "–" : "").font(.system(size: 13, weight: .bold)).foregroundStyle(v == "ok" ? Color.white : Theme.muted))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(i == 6 ? Theme.mint.opacity(0.6) : Color.clear, lineWidth: 3))
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .padding(.top, 8)
                Text(Loc.ar ? "أفضل سلسلة: \(arDigits(store.streak.best)) يومًا" : Loc.f("Best streak: {0} days", "\(store.streak.best)"))
                    .font(.sys(size: 13)).foregroundStyle(Theme.muted).padding(.top, 6)
            }
            .padding(18).frame(maxWidth: .infinity).card(26).padding(.top, 22)
            Text("«مَن صلَّى الصُّبحَ فهو في ذمَّةِ اللهِ»").font(.sys(size: 15)).foregroundStyle(Theme.ink)
                .padding(12).frame(maxWidth: .infinity).background(Theme.tile, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.top, 18)
            Spacer()
            Button {
                store.screen = nil; model.tab = 4
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { AzkarStore.shared.openRequest = "morning" }
            } label: {
                Text(Loc.ar ? "أذكار الصباح" : L("Morning azkar")).font(.sys(size: 17, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54).background(Theme.mintDeep, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { store.screen = nil } label: { Text(Loc.ar ? "إغلاق" : L("Close")).font(.sys(size: 15)).foregroundStyle(Theme.muted).padding(10) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Theme.rowNow, Theme.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = model.place.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private func mmss(_ s: TimeInterval) -> String { String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60) }
}

// MARK: - Settings section

struct FajrSettings: View {
    @ObservedObject var fajr: FajrStore
    var onAsk: () -> Void
    @State private var showHint = false

    private func ic(_ n: String) -> some View { Image(systemName: n).font(.sys(size: 20)).foregroundStyle(Theme.muted).frame(width: 28) }
    private func t(_ s: String) -> some View { Text(s).font(.sys(size: 17)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7) }
    private func after(_ n: Int) -> String {
        if n == 0 { return Loc.ar ? "بدون" : L("None") }
        return Loc.ar ? "بعد \(n) دقائق" : Loc.f("After {0} min", "\(n)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ic("alarm")
                Button { withAnimation { showHint.toggle() } } label: {
                    HStack(spacing: 6) {
                        t(Loc.ar ? "منبّه الفجر" : L("Fajr alarm"))
                        Image(systemName: "info.circle").font(.sys(size: 13)).foregroundStyle(Theme.muted.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { fajr.active }, set: { on in
                    if !on { fajr.on = false; fajr.onChange?(); return }
                    onAsk()
                    if fajr.rug == nil { fajr.screen = .setup } else { fajr.on = true; fajr.onChange?() }
                })).labelsHidden().tint(Theme.mintDeep)
            }
            .frame(minHeight: 56)
            if showHint {
                Text(Loc.ar ? "عند الفجر يتكرر التنبيه كل دقيقتين لمدة نصف ساعة حتى تفتح التطبيق وتصوّر سجادة صلاتك، ويعدّ الأيام التي تصلي فيها الفجر متتالية."
                            : L("At Fajr the alert repeats every 2 minutes for half an hour until you open the app and photograph your prayer rug. It also counts the days you pray Fajr in a row."))
                    .font(.footnote).foregroundStyle(Theme.muted).sideAligned().padding(.bottom, 10)
            }
            Divider().overlay(Theme.line).padding(.leading, 42)
            HStack(spacing: 14) {
                ic("camera")
                t(Loc.ar ? "تصوير السجادة" : L("Prayer rug photo"))
                Spacer(minLength: 8)
                Button { onAsk(); fajr.screen = .setup } label: {
                    Text(fajr.rug == nil ? (Loc.ar ? "التقاط صورة" : L("Take photo")) : (Loc.ar ? "إعادة التصوير" : L("Retake")))
                        .font(.sys(size: 14, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8).background(Theme.mintDeep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 56)
            Divider().overlay(Theme.line).padding(.leading, 42)
            HStack(spacing: 14) {
                ic("lock.open")
                t(Loc.ar ? "الإيقاف الطارئ" : L("Emergency stop"))
                Spacer(minLength: 8)
                Menu {
                    Picker("", selection: $fajr.emer) { ForEach([5, 10, 15, 0], id: \.self) { Text(after($0)).tag($0) } }
                } label: {
                    HStack(spacing: 4) {
                        Text(after(fajr.emer)).font(.sys(size: 15)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.up.chevron.down").font(.sys(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(minHeight: 56)
        }
        .padding(.horizontal, 18).frame(maxWidth: .infinity, alignment: .leading).card(28)

        HStack(spacing: 0) {
            stat("\(fajr.streak.cur)", Loc.ar ? "أيام متتالية" : L("Days in a row"))
            Rectangle().fill(Theme.line).frame(width: 1, height: 44)
            stat("\(fajr.streak.best)", Loc.ar ? "أفضل سلسلة" : L("Best streak"))
        }
        .padding(.vertical, 14).frame(maxWidth: .infinity).card(24).padding(.top, 14)
    }

    private func stat(_ v: String, _ s: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Theme.mintDeep)
            Text(s).font(.sys(size: 13)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}
