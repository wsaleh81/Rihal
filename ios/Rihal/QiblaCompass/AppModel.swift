import SwiftUI
import Combine
import CoreLocation

enum LocBanner: Equatable { case detecting, confirmed, changed(from: String), failed, manual }

final class AppModel: ObservableObject {
    @AppStorage("welcomed") var welcomed = false
    @AppStorage("methodID") var methodID = "kuwait"
    @AppStorage("hanafi") var hanafi = false
    @AppStorage("showNow") var showNow = true
    @AppStorage("usingGPS") var usingGPS = true
    @AppStorage("cityName") var cityName = "Kuwait City"
    @AppStorage("themeID") var themeID = "modern"
    @AppStorage("paletteID") var paletteID = "ocean"
    @AppStorage("appearance") var appearance = "auto"
    @AppStorage("textSize") var textSize = "1"
    @AppStorage("boldText") var boldText = false
    @AppStorage("azkarSize") var azkarSize = "1"
    @AppStorage("langID") var langID = "ar"
    @AppStorage("fontID") var fontID = "system"
    @AppStorage("lastGPSJSON") var lastGPSJSON = ""
    @AppStorage("pinnedJSON") var pinnedJSON = ""
    @AppStorage("notifOn") var notifOn = false
    @AppStorage("notifBefore") var notifBefore = 0
    @AppStorage("notifSunrise") var notifSunrise = false
    @AppStorage("adhanSound") var adhanSound = "adhan"
    @AppStorage("fajrSound") var fajrSound = "adhan"
    @AppStorage("azMorning") var azMorning = false
    @AppStorage("azEvening") var azEvening = false
    @AppStorage("azPrayer") var azPrayer = false
    @AppStorage("azFriday") var azFriday = false

    @Published var tab = 0
    /// when the app went to the background; after 5 minutes away it opens on Prayer Times again
    var leftAt: Date?
    @Published var changedFrom: String?
    @Published var previousPlace: Place?
    @Published var timedOut = false
    let location = LocationService()
    let weather = WeatherService()
    let network = NetworkMonitor()
    private var bag = Set<AnyCancellable>()

    init() {
        // A new install starts with the ring compass and every alert off. Someone updating keeps what they had:
        // a setting they never changed keeps the old default (alerts and azkar reminders on, classic compass).
        let d = UserDefaults.standard
        if d.object(forKey: "defaultsV2") == nil {
            if d.bool(forKey: "welcomed") {
                for k in ["notifOn", "azMorning", "azEvening", "azFriday"] where d.object(forKey: k) == nil { d.set(true, forKey: k) }
                if d.object(forKey: "compassStyle") == nil { d.set("classic", forKey: "compassStyle") }
            }
            d.set(true, forKey: "defaultsV2")
        }
        UserDefaults.standard.register(defaults: ["usingGPS": true])
        network.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send(); if self?.network.online == true { self?.refreshWeather() } }
        }.store(in: &bag)
        weather.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }.store(in: &bag)
        location.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send(); self?.handleFix() }
        }.store(in: &bag)
        refreshLocation()
        // A finished (or reset) azkar set changes today's reminders; wait a moment so a run of taps rebuilds once.
        AzkarStore.shared.onSetChange = { [weak self] in
            self?.pendingReschedule?.cancel()
            let w = DispatchWorkItem { self?.rescheduleNotifications() }
            self?.pendingReschedule = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
        }
    }
    private var pendingReschedule: DispatchWorkItem?

    // MARK: place
    private func decode(_ s: String) -> Place? { s.isEmpty ? nil : (try? JSONDecoder().decode(Place.self, from: Data(s.utf8))) }
    private func encode(_ p: Place) -> String { (try? String(data: JSONEncoder().encode(p), encoding: .utf8)) ?? "" }

    private var gpsPlace: Place? {
        guard let c = location.coordinate else { return nil }
        return Place(name: location.placeName ?? nearestCityName(c) ?? "My location", country: location.placeCountry ?? "", lat: c.latitude, lon: c.longitude,
                     tz: (location.timeZone ?? .current).identifier, isGPS: true)
    }

    /// Offline fallback for the place name: the closest listed city within 80 km.
    private func nearestCityName(_ c: CLLocationCoordinate2D) -> String? {
        let best = Cities.all.map { ($0, QiblaMath.haversineKm($0.lat, $0.lon, c.latitude, c.longitude)) }.min { $0.1 < $1.1 }
        return best.flatMap { $0.1 < 80 ? $0.0.name : nil }
    }

    func refreshWeather(force: Bool = false) {
        let p = place
        weather.refresh(lat: p.lat, lon: p.lon, force: force)
    }

    var place: Place {
        if usingGPS {
            if let g = gpsPlace { return g }
            if let last = decode(lastGPSJSON) { return last }
        } else if let pin = decode(pinnedJSON) { return pin }
        return Cities.all.first { $0.name == cityName } ?? Cities.all[0]
    }

    var lastGPSName: String? { decode(lastGPSJSON)?.name }

    var method: CalcMethod { CalcMethod.with(id: methodID) }
    var qibla: Double { QiblaMath.bearing(lat: place.lat, lon: place.lon) }
    var distance: Double { QiblaMath.distanceKm(lat: place.lat, lon: place.lon) }

    func chooseCity(_ p: Place) { usingGPS = false; pinnedJSON = ""; cityName = p.name; changedFrom = nil }
    func pin(_ p: Place) { pinnedJSON = encode(p); usingGPS = false; changedFrom = nil }
    func useMyLocation() { usingGPS = true; refreshLocation() }

    // MARK: automatic location check (every launch / return to the app)
    func refreshLocation() {
        guard usingGPS else { return }
        timedOut = false
        location.requestAccess()
        location.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.usingGPS, self.location.coordinate == nil || self.location.fixDate.map({ Date().timeIntervalSince($0) > 20 }) == true else { return }
            if self.location.coordinate == nil { self.timedOut = true; self.objectWillChange.send() }
        }
    }

    private func handleFix() {
        guard usingGPS, let g = gpsPlace else { return }
        if let last = decode(lastGPSJSON) {
            let km = QiblaMath.haversineKm(last.lat, last.lon, g.lat, g.lon)
            if km > 50 && changedFrom == nil { changedFrom = last.name; previousPlace = last }
        }
        let new = encode(g)
        if new != lastGPSJSON { lastGPSJSON = new }
    }

    func keepNewPlace() { changedFrom = nil }
    func goBackToPrevious() { if let p = previousPlace { pin(p) } }

    var banner: LocBanner {
        if !usingGPS { return .manual }
        if location.denied { return .failed }
        if location.coordinate != nil { return changedFrom.map { .changed(from: $0) } ?? .confirmed }
        return (timedOut || location.failed) ? .failed : .detecting
    }

    // MARK: notifications
    func isMuted(_ p: Prayer) -> Bool {
        p == .sunrise ? !notifSunrise : UserDefaults.standard.bool(forKey: "mute_" + p.rawValue)
    }
    /// Alarm: the prayer's alert plays the adhan. Off by default; sunrise has no adhan.
    func isAlarm(_ p: Prayer) -> Bool {
        p != .sunrise && UserDefaults.standard.bool(forKey: "alarmOn_" + p.rawValue)
    }
    func toggleAlarm(_ p: Prayer) {
        guard p != .sunrise else { return }
        UserDefaults.standard.set(!isAlarm(p), forKey: "alarmOn_" + p.rawValue)
        objectWillChange.send()
    }
    func toggleMute(_ p: Prayer) {
        if p == .sunrise { notifSunrise.toggle() }
        else { UserDefaults.standard.set(!isMuted(p), forKey: "mute_" + p.rawValue) }
        objectWillChange.send()
    }
    /// Changes whenever the schedule must be rebuilt.
    var notifKey: String {
        let d = UserDefaults.standard
        let offs = Prayer.allCases.map { String(d.integer(forKey: "off_" + $0.rawValue)) }.joined(separator: ",")
        let mutes = Prayer.allCases.map { (isMuted($0) ? "1" : "0") + (isAlarm($0) ? "a" : "") }.joined()
        let p = place
        return "\(notifOn)|\(notifBefore)|\(mutes)|\(methodID)|\(hanafi)|\(offs)|\(String(format: "%.1f,%.1f", p.lat, p.lon))|\(AppLang.current.id)|\(adhanSound)|\(fajrSound)|\(azMorning)\(azEvening)\(azPrayer)\(azFriday)"
    }
    func rescheduleNotifications() {
        Notifier.schedule(place: place, method: method, hanafi: hanafi, on: notifOn, before: notifBefore,
                          muted: Dictionary(uniqueKeysWithValues: Prayer.allCases.map { ($0, isMuted($0)) }),
                          alarm: Dictionary(uniqueKeysWithValues: Prayer.allCases.map { ($0, isAlarm($0)) }),
                          opt: .init(sound: adhanSound, fajrSound: fajrSound, morning: azMorning, evening: azEvening, afterPrayer: azPrayer, friday: azFriday))
    }
}
