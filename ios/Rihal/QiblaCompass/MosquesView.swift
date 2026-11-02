import SwiftUI
import MapKit
import CoreLocation

/// The mosque line icon (template image: takes the colour of its surroundings).
struct MosqueGlyph: View {
    var size: CGFloat = 22
    var body: some View {
        Image("MosqueIcon").renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size)
    }
}

struct Mosque: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let lat: Double
    let lon: Double
    let meters: Double
    var item: MKMapItem?
    var sources: [String] = []
    var verified: Bool { sources.count > 1 }
    static func == (a: Mosque, b: Mosque) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Finds mosques around a point with Apple Maps search (needs internet).
final class MosqueService: ObservableObject {
    @Published var results: [Mosque] = []
    @Published var loading = false
    @Published var failed = false
    private var token = 0

    private struct Cached: Codable { var id, name, address: String; var lat, lon: Double; var sources: [String] }
    private func key(_ lat: Double, _ lon: Double) -> String { String(format: "mosques_%.2f_%.2f", lat, lon) }

    /// Show the last result for this spot instantly while the fresh search runs.
    func loadCache(lat: Double, lon: Double) {
        guard results.isEmpty, let d = UserDefaults.standard.data(forKey: key(lat, lon)),
              let c = try? JSONDecoder().decode([Cached].self, from: d) else { return }
        let me = CLLocation(latitude: lat, longitude: lon)
        results = c.map { Mosque(id: $0.id, name: $0.name, address: $0.address, lat: $0.lat, lon: $0.lon,
                                 meters: me.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon)), item: nil, sources: $0.sources) }
            .sorted { $0.meters < $1.meters }
    }
    private func saveCache(_ list: [Mosque], lat: Double, lon: Double) {
        let c = list.prefix(40).map { Cached(id: $0.id, name: $0.name, address: $0.address, lat: $0.lat, lon: $0.lon, sources: $0.sources) }
        if let d = try? JSONEncoder().encode(Array(c)) { UserDefaults.standard.set(d, forKey: key(lat, lon)) }
    }

    func search(lat: Double, lon: Double) {
        token += 1; let mine = token
        loading = true; failed = false
        let center = CLLocation(latitude: lat, longitude: lon)
        let queries = ["mosque", "masjid", "مسجد"]
        var found: [Mosque] = []
        var errors = 0, jobs = 0
        var pending = false
        let lock = NSLock()
        let group = DispatchGroup()

        func add(_ m: Mosque) {
            lock.lock(); defer { lock.unlock() }
            let here = CLLocation(latitude: m.lat, longitude: m.lon)
            // same building listed by two sources: merge them and mark it as confirmed by both
            if let i = found.firstIndex(where: { CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: here) < 60 }) {
                for src in m.sources where !found[i].sources.contains(src) { found[i].sources.append(src) }
                if found[i].item == nil, let it = m.item { found[i].item = it }
                if found[i].address.isEmpty { found[i] = Mosque(id: found[i].id, name: found[i].name, address: m.address, lat: found[i].lat, lon: found[i].lon, meters: found[i].meters, item: found[i].item, sources: found[i].sources) }
                return
            }
            found.append(m)
        }

        // Show what we have as soon as any source answers (no waiting for the slowest one).
        func publish() {
            lock.lock()
            if pending { lock.unlock(); return }
            pending = true; lock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.token == mine else { return }
                lock.lock(); pending = false; let snap = found; lock.unlock()
                if !snap.isEmpty {
                    self.results = snap.sorted { $0.meters < $1.meters }.prefix(40).map { $0 }
                    self.failed = false
                    self.loading = false
                }
            }
        }

        // 1) Apple Maps: a small area first (so near mosques are not crowded out), then a wide one
        for span in [2500.0, 16000.0] {
            let region = MKCoordinateRegion(center: center.coordinate, latitudinalMeters: span, longitudinalMeters: span)
            for q in queries {
                jobs += 1; group.enter()
                let req = MKLocalSearch.Request()
                req.naturalLanguageQuery = q
                req.region = region
                MKLocalSearch(request: req).start { resp, err in
                    if err != nil { lock.lock(); errors += 1; lock.unlock() }
                    for it in resp?.mapItems ?? [] {
                        let c = it.placemark.coordinate
                        let d = center.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                        guard d < 20000 else { continue }
                        let name = it.name ?? L("Mosque")
                        if name.lowercased().contains("parking") { continue }
                        let addr = [it.placemark.thoroughfare, it.placemark.subLocality ?? it.placemark.locality]
                            .compactMap { $0 }.joined(separator: ", ")
                        add(Mosque(id: String(format: "%.5f,%.5f", c.latitude, c.longitude), name: name, address: addr,
                                   lat: c.latitude, lon: c.longitude, meters: d, item: it, sources: ["Apple"]))
                    }
                    publish()
                    group.leave()
                }
            }
        }

        // 2) OpenStreetMap (also lists small neighbourhood mosques that Apple Maps misses)
        jobs += 1; group.enter()
        let ql = "[out:json][timeout:8];(node[\"amenity\"=\"place_of_worship\"][\"religion\"=\"muslim\"](around:3000,\(String(format: "%.2f", lat)),\(String(format: "%.2f", lon)));way[\"amenity\"=\"place_of_worship\"][\"religion\"=\"muslim\"](around:3000,\(String(format: "%.2f", lat)),\(String(format: "%.2f", lon))););out center tags 40;"
        // The main Overpass server often times out: ask five mirrors at once and use the first good answer (as on Android).
        let hosts = ["https://overpass-api.de", "https://lz4.overpass-api.de", "https://z.overpass-api.de",
                     "https://overpass.private.coffee", "https://maps.mail.ru/osm/tools/overpass"]
        var answered = false, failures = 0
        for h in hosts {
            var comps = URLComponents(string: h + "/api/interpreter")!
            comps.queryItems = [URLQueryItem(name: "data", value: ql)]
            var req = URLRequest(url: comps.url!); req.timeoutInterval = 9
            URLSession.shared.dataTask(with: req) { data, _, _ in
                let els = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["elements"] as? [[String: Any]]
                lock.lock()
                if answered { lock.unlock(); return }            // another mirror already answered
                guard let els else {
                    failures += 1
                    let last = failures == hosts.count
                    if last { errors += 1; answered = true }
                    lock.unlock()
                    if last { publish(); group.leave() }
                    return
                }
                answered = true
                lock.unlock()
                for e in els {
                    let c = e["center"] as? [String: Any]
                    guard let la = (e["lat"] as? Double) ?? (c?["lat"] as? Double),
                          let lo = (e["lon"] as? Double) ?? (c?["lon"] as? Double) else { continue }
                    let t = e["tags"] as? [String: Any] ?? [:]
                    let name = (t["name:en"] as? String) ?? (t["name"] as? String) ?? (t["name:ar"] as? String) ?? "Mosque"
                    let addr = [t["addr:street"] as? String, (t["addr:suburb"] as? String) ?? (t["addr:city"] as? String)]
                        .compactMap { $0 }.joined(separator: ", ")
                    let d = center.distance(from: CLLocation(latitude: la, longitude: lo))
                    add(Mosque(id: String(format: "%.5f,%.5f", la, lo), name: name, address: addr, lat: la, lon: lo, meters: d, item: nil, sources: ["OSM"]))
                }
                publish()
                group.leave()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.token == mine else { return }
            self.loading = false
            let final = found.sorted { $0.meters < $1.meters }.prefix(40).map { $0 }
            if !final.isEmpty { self.results = final; self.saveCache(final, lat: lat, lon: lon) }
            self.failed = self.results.isEmpty && errors >= jobs
        }
    }
}

struct MosquesView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var svc = MosqueService()
    @State private var around: Place?          // nil = my current place
    @State private var showPicker = false
    @State private var chosen: Mosque?

    private var center: Place { model.place }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(en: "Mosques", ar: "المساجد")

                HStack(spacing: 10) {
                    Button { showPicker = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: model.usingGPS ? "location.fill" : "mappin.and.ellipse").foregroundStyle(Theme.mintDeep)
                            Text(model.usingGPS ? L("Near me") + " · \(center.name)" : (Loc.ar ? "بالقرب من \(center.name)" : Loc.f("Near {0}", center.name)))
                                .font(.sys(size: 15, weight: .semibold, design: Theme.design)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.sys(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).frame(minHeight: 44).card(22)
                    }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if svc.loading && !svc.results.isEmpty { ProgressView().controlSize(.small) }
                    Button { load() } label: {
                        Image(systemName: "arrow.clockwise").font(.sys(size: 16, weight: .bold)).foregroundStyle(Theme.mintDeep)
                            .frame(width: 44, height: 44).background(Theme.card, in: Circle())
                    }.buttonStyle(.plain)
                }.padding(.top, 10)

                if !model.network.online && svc.results.isEmpty {
                    notice("wifi.slash", "You are offline", "Finding mosques needs internet. Prayer times and Qibla keep working without it.")
                } else if svc.loading && svc.results.isEmpty {
                    HStack(spacing: 10) { ProgressView(); Text(L("Looking for mosques…")).foregroundStyle(Theme.muted) }
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else if svc.failed {
                    notice("exclamationmark.triangle", "Couldn’t search", "Check your connection and tap refresh.")
                } else if svc.results.isEmpty {
                    notice("mappin.slash", "No mosques found nearby", "Try another city from the menu above.")
                } else {
                    if let first = svc.results.first { suggested(first).padding(.top, 14) }
                    Text(L("nearby")).font(.sys(size: 20, weight: .bold, design: Theme.design)).foregroundStyle(Theme.muted)
                        .padding(.leading, 6).padding(.top, 18).padding(.bottom, 8)
                    VStack(spacing: 8) {
                        ForEach(svc.results.dropFirst()) { m in rowView(m) }
                    }
                    Text(L("Sources: Apple Maps and © OpenStreetMap contributors. A seal means both list the mosque. Distances are straight-line from your position."))
                        .font(.sys(size: 11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .onAppear { if svc.results.isEmpty { load() } }
        .onChange(of: model.place) { _, _ in load() }
        .sheet(isPresented: $showPicker) {
            MosqueCityPicker(current: model.place, selected: model.usingGPS ? nil : model.place) { p in
                if let p {
                    if Cities.all.contains(where: { $0.name == p.name && $0.isoCode == p.isoCode }) { model.chooseCity(p) } else { model.pin(p) }
                } else { model.useMyLocation() }
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(chosen?.name ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible) {
            if let m = chosen {
                Button(L("Open in Apple Maps")) { openApple(m) }
                Button(L("Open in Google Maps")) { openGoogle(m) }
                Button(L("Open in Waze")) { openWaze(m) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            if let m = chosen { Text("\(dist(m.meters)) away") }
        }
    }

    private func load() { svc.loadCache(lat: center.lat, lon: center.lon); svc.search(lat: center.lat, lon: center.lon) }

    // MARK: pieces
    private func suggested(_ m: Mosque) -> some View {
        Button { chosen = m } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("SUGGESTED")).font(.sys(size: 11, weight: .heavy)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 9).padding(.vertical, 3).background(Theme.mint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                    Text("Closest to \(model.usingGPS ? "you" : center.name)").font(.sys(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 14) {
                    MosqueGlyph(size: 32).foregroundStyle(Theme.mint)
                        .frame(width: 54, height: 54).background(Theme.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.name).font(.sys(size: 19, weight: .heavy, design: Theme.design)).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                        if !m.address.isEmpty { Text(m.address).font(.sys(size: 13)).foregroundStyle(Theme.muted).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    infoPill("mappin.and.ellipse", dist(m.meters))
                    infoPill("figure.walk", walkShort(m.meters) + " " + L("walk"))
                    if m.verified { infoPill("checkmark.seal.fill", L("Confirmed")) }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.sys(size: 16, weight: .bold))
                    Text(L("Directions")).font(.sys(size: 16, weight: .heavy)).lineLimit(1)
                }
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        }.buttonStyle(.plain)
    }

    private func rowView(_ m: Mosque) -> some View {
        Button { chosen = m } label: {
            HStack(spacing: 12) {
                MosqueGlyph(size: 24).foregroundStyle(Theme.mint)
                    .frame(width: 40, height: 40).background(Theme.tile, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(m.name).font(.sys(size: 15, weight: .bold, design: Theme.design)).foregroundStyle(Theme.ink).lineLimit(1)
                        if m.verified { Image(systemName: "checkmark.seal.fill").font(.sys(size: 12)).foregroundStyle(Theme.mint) }
                    }
                    Text(m.address.isEmpty ? L("Mosque") : m.address)
                        .font(.sys(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dist(m.meters)).font(.sys(size: 15, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.ink)
                    Text(walkShort(m.meters)).font(.sys(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.right").font(.sys(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12).frame(minHeight: 62)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line.opacity(0.35), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func infoPill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.sys(size: 12, weight: .bold))
            Text(L(text)).font(.sys(size: 13, weight: .bold)).monospacedDigit()
        }
        .foregroundStyle(Theme.ink).lineLimit(1).fixedSize().padding(.horizontal, 12).frame(minHeight: 34).background(Theme.tile, in: Capsule())
    }

    private func notice(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.sys(size: 34)).foregroundStyle(Theme.muted)
            Text(L(title)).font(.sys(size: 18, weight: .heavy)).foregroundStyle(Theme.ink)
            Text(L(sub)).font(.sys(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36).padding(.horizontal, 20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous)).padding(.top, 18)
    }

    // MARK: helpers
    private func dist(_ m: Double) -> String { m < 1000 ? "\(Int((m / 10).rounded()) * 10) " + L("m") : String(format: "%.1f ", m / 1000) + L("km") }
    private func walkShort(_ m: Double) -> String {
        let min = Int((m / 80).rounded())
        return Loc.ar ? (min < 1 ? "١ د" : (min >= 60 ? "\(min / 60) س \(min % 60) د" : "\(min) د")) : (min < 1 ? Loc.f("1 min") : (min >= 60 ? Loc.f("{0} h {1} m", "\(min / 60)", "\(min % 60)") : Loc.f("{0} min", "\(min)")))
    }
    private func walk(_ m: Double) -> String {
        let min = Int((m / 80).rounded())          // ~4.8 km/h
        return min < 1 ? "1 min walk" : (min >= 60 ? "\(min / 60) h \(min % 60) min walk" : "\(min) min walk")
    }
    private func openApple(_ m: Mosque) {
        let item = m.item ?? MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: m.lat, longitude: m.lon)))
        item.name = m.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
    private func openWaze(_ m: Mosque) {
        // Opens the Waze app if installed, otherwise Waze in the browser.
        if let u = URL(string: "https://waze.com/ul?ll=\(m.lat),\(m.lon)&navigate=yes") { UIApplication.shared.open(u) }
    }
    private func openGoogle(_ m: Mosque) {
        // Opens the Google Maps app if installed, otherwise Google Maps in the browser.
        if let u = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(m.lat),\(m.lon)&travelmode=walking") {
            UIApplication.shared.open(u)
        }
    }
}

/// Choose "near me" or any listed city to look for mosques there.
struct MosqueCityPicker: View {
    let current: Place
    let selected: Place?
    let onPick: (Place?) -> Void
    var title = "Find mosques in"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CityPickerList(selectedName: selected?.name, onPick: { c in onPick(c); dismiss() }, header: {
                Button { onPick(nil); dismiss() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill").foregroundStyle(Theme.mintDeep)
                            .frame(width: 38, height: 34)
                            .background(Theme.mintDeep.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Near me · \(current.name)").font(.sys(size: 17, weight: .semibold))
                        Spacer()
                        if selected == nil { Image(systemName: "checkmark").foregroundStyle(Theme.mintDeep) }
                    }
                    .foregroundStyle(Theme.ink).padding(.horizontal, 16).frame(minHeight: 56).card(28)
                }
                .buttonStyle(.plain)
            })
            .navigationTitle(L(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { dismiss() } } }
        }
    }
}
