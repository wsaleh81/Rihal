import { X, U } from "./langs.js";
import { Capacitor, registerPlugin } from "@capacitor/core";
import { LocalNotifications } from "@capacitor/local-notifications";
import { Geolocation } from "@capacitor/geolocation";
import DATA from "./data.json";
import AR from "./ar.json";
import MORE from "./azkar_more.json";
import { classicSVG, ringsSVG, updateDial as dialUpdate, sunLayerSVG } from "./dials.js";
import { azIcon } from "./azicons.js";
import { rugFeatures, rugScore, RUG_MATCH, dayKey, streakOf, markDay } from "./fajr.js";
import { mushafHTML, mushafAfter, mushafIndexToggle, mushafSetPage, mushafBy, SURAS } from "./mushaf.js";
import { Qibla, haversine, diff, norm, cardinal, sunInfo, METHODS, PRAYERS, prayerEvents, dayFor } from "./core.js";

/* ---------- palettes (same as the iOS app) ---------- */
const H = n => "#" + n.toString(16).padStart(6, "0");
const P = (id, title, bg, card, ink, muted, line, tile, accent, deep, tint, rowNow, on) => ({ id, title, c: { bg, card, ink, muted, line, tile, accent, deep, tint, rowNow, on } });
const PALETTES = [
  P("ocean", "Ocean", [0xEDF2F8, 0x0A1430], [0xFFFFFF, 0x12224D], [0x0E1726, 0xF5F0E4], [0x5B677A, 0xA9B2CC], [0xDCE5F0, 0x2B4080], [0xE3ECF6, 0x1C3170], [0x2F9BE8, 0xE4BB68], [0x1B7FCC, 0xF1D9A2], [0xDCEBFA, 0x1B2E66], [0xDCEBFA, 0x1F3470], [0xFFFFFF, 0x0A1430]),
  P("emerald", "Emerald", [0xEAF5EF, 0x07140E], [0xFFFFFF, 0x0E3226], [0x0B2A1F, 0xECF8F2], [0x527466, 0xA3C4B6], [0xD2E5DB, 0x1F5A44], [0xDDEEE5, 0x154633], [0x22B07D, 0x34D399], [0x0A7552, 0x8DEBC6], [0xD8F3E6, 0x154633], [0xD8F3E6, 0x18503B], [0xFFFFFF, 0x06150F]),
  P("royal", "Royal", [0xF2EEFA, 0x130C26], [0xFFFFFF, 0x2A1B50], [0x1B1230, 0xF3EEFC], [0x6A5C86, 0xB9ABD3], [0xE1D8F2, 0x4A3590], [0xE9E1F7, 0x38256A], [0x8A5CE0, 0xB794F6], [0x6D3FC4, 0xD3BBFA], [0xE8DEFA, 0x38256A], [0xE8DEFA, 0x42307A], [0xFFFFFF, 0x150E26]),
  P("sunset", "Sunset", [0xFDF1EA, 0x1E0E07], [0xFFFFFF, 0x4B2010], [0x2B1308, 0xFDF1EA], [0x8A6552, 0xD2B3A0], [0xF3DACB, 0x7A3E1C], [0xF9E5D8, 0x5E2C14], [0xF26B21, 0xFF8A4C], [0xD04E0A, 0xFFC09A], [0xFCDDC8, 0x5E2C14], [0xFCDDC8, 0x6B3318], [0xFFFFFF, 0x1E0C03]),
  P("rose", "Rose", [0xFCEFF2, 0x1F0A11], [0xFFFFFF, 0x4D1828], [0x2B0F18, 0xFDEFF3], [0x8A5A68, 0xD3AEBB], [0xF2D6DD, 0x8A3552], [0xF8E3E8, 0x66243A], [0xEE5C85, 0xFF7A9C], [0xC8325A, 0xFFB5C9], [0xFBDDE6, 0x66243A], [0xFBDDE6, 0x722A42], [0xFFFFFF, 0x1E0810]),
  P("graphite", "Graphite", [0xEFF0F2, 0x111214], [0xFFFFFF, 0x24272C], [0x15171A, 0xF2F3F5], [0x5F656E, 0xA9AEB6], [0xDDE0E4, 0x42474E], [0xE6E8EB, 0x30343A], [0x4A5058, 0xD6DAE0], [0x2B3036, 0xE4E7EB], [0xE1E4E8, 0x30343A], [0xE1E4E8, 0x383D44], [0xFFFFFF, 0x101113]),
];

/* ---------- settings store ---------- */
const DEF = {
  lang: "ar", palette: "ocean", appearance: "auto", textSize: "1", bold: false, azkarSize: "1",
  method: "kuwait", hanafi: false, showNow: true, adhanSound: "adhan", fajrSound: "adhan", azMorning: false, azEvening: false, azPrayer: false, azFriday: false, volKeys: true, fajrOn: false, fajrEmer: 10, rugRef: null, off: {}, notif: false, remind: 0, sunriseAlert: false, muted: {},
  temp: "c", tab: 0, welcomed: false, compass: "rings", alarm: {}, fontID: "system", v: 2,
  place: { name: "Kuwait City", country: "Kuwait", lat: 29.3759, lon: 47.9774, tz: "Asia/Kuwait", iso: "KW" },
  gps: false,
};
let S = { ...DEF };
// A new install starts with the ring compass and every alert off. After an update the user's own settings stay as
// they were; a setting saved before it existed keeps the old default (alerts and azkar reminders on, classic compass).
let stored = null;
try { stored = JSON.parse(localStorage.getItem("rihal") || "null"); } catch (e) {}
const freshInstall = !stored;
if (stored) {
  const OLD = { notif: true, compass: "classic", azMorning: true, azEvening: true, azFriday: true };
  for (const k in OLD) if (stored[k] === undefined) stored[k] = OLD[k];
  Object.assign(S, stored);
}
delete S.preview;
function safeTz(tz) { try { new Intl.DateTimeFormat("en", { timeZone: tz }); return tz; } catch (e) { return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"; } }
if (S.place) S.place.tz = safeTz(S.place.tz);
if (S.v !== 2) { S.tab = 0; S.v = 2; S.alarm = S.alarm || {}; }
if (!S.nv) { if (!freshInstall) S.notif = true; S.nv = 1; }
S.tab = 0; // the app always opens on Prayer Times (a widget tap can still open Mosques)
const save = () => { try { localStorage.setItem("rihal", JSON.stringify(S)); } catch (e) {} };
const ar = () => S.lang === "ar";
const F = (t, ...a) => { const x = (U[S.lang] && U[S.lang].tpl[t]) || t; return x.replace(/\{(\d)\}/g, (_, i) => a[i]); };
const rtl = () => S.lang === "ar" || S.lang === "ur";
const L = s => (ar() ? (AR[s] || s) : ((U[S.lang] && U[S.lang].ui[s]) || s));
const esc = s => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const $ = (s, r = document) => r.querySelector(s);
const method = () => METHODS.find(m => m.id === S.method) || METHODS[0];
const iso3 = c => DATA.iso3[c] || c;
const CITIES = DATA.cities.map(c => ({ name: c[0], country: c[1], lat: c[2], lon: c[3], tz: c[4], iso: c[5] }));

const LANGS = [["ar", "العربية"], ["en", "English"], ["tr", "Türkçe"], ["fr", "Français"], ["it", "Italiano"], ["de", "Deutsch"], ["nl", "Nederlands"], ["es", "Español"], ["ur", "اردو"], ["ta", "தமிழ்"], ["ru", "Русский"]];
const PNAME_EN = { fajr: "Fajr", sunrise: "Sunrise", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha" };
const PNAME_AR = { fajr: "الفجر", sunrise: "الشروق", dhuhr: "الظهر", asr: "العصر", maghrib: "المغرب", isha: "العشاء" };
const PNAME_LOCAL = {
  tr: { fajr: "İmsak", sunrise: "Güneş", dhuhr: "Öğle", asr: "İkindi", maghrib: "Akşam", isha: "Yatsı" },
  fr: { fajr: "Fajr (Aube)", sunrise: "Lever du soleil", dhuhr: "Dhuhr (Midi)", asr: "Asr (Après-midi)", maghrib: "Maghrib (Coucher)", isha: "Isha (Nuit)" },
  it: { fajr: "Fajr (Alba)", sunrise: "Alba solare", dhuhr: "Dhuhr (Mezzogiorno)", asr: "Asr (Pomeriggio)", maghrib: "Maghrib (Tramonto)", isha: "Isha (Notte)" },
  de: { fajr: "Fadschr (Morgen)", sunrise: "Sonnenaufgang", dhuhr: "Dhuhr (Mittag)", asr: "Asr (Nachmittag)", maghrib: "Maghrib (Abend)", isha: "Ischa (Nacht)" },
  nl: { fajr: "Fadjr (Dageraad)", sunrise: "Zonsopkomst", dhuhr: "Dhuhr (Middag)", asr: "Asr (Namiddag)", maghrib: "Maghrib (Zonsondergang)", isha: "Isja (Nacht)" },
  es: { fajr: "Fajr (Alba)", sunrise: "Amanecer", dhuhr: "Dhuhr (Mediodía)", asr: "Asr (Tarde)", maghrib: "Magrib (Atardecer)", isha: "Isha (Noche)" },
};
const pName = p => (ar() ? PNAME_AR[p] : X[S.lang] ? X[S.lang].prayer[p] : PNAME_EN[p]);
const pLocal = p => (X[S.lang] ? PNAME_EN[p] : (PNAME_LOCAL[S.lang] || PNAME_AR)[p]);
const CAT_TITLES = {
  ar: ["الصباح", "المساء", "بعد الصلاة", "النوم", "السفر"], en: ["Morning", "Evening", "After prayer", "Sleep", "Travel"],
  tr: ["Sabah", "Akşam", "Namaz sonrası", "Uyku", "Yolculuk"], fr: ["Matin", "Soir", "Après la prière", "Sommeil", "Voyage"],
  it: ["Mattina", "Sera", "Dopo la preghiera", "Sonno", "Viaggio"], de: ["Morgen", "Abend", "Nach dem Gebet", "Schlaf", "Reise"],
  nl: ["Ochtend", "Avond", "Na het gebed", "Slaap", "Reis"], es: ["Mañana", "Tarde", "Tras la oración", "Dormir", "Viaje"],
};
Object.keys(X).forEach(k => { CAT_TITLES[k] = X[k].cats; });
const CATS = ["morning", "evening", "afterPrayer", "sleep", "travel"];
const catTitle = i => (CAT_TITLES[S.lang] || CAT_TITLES.en)[i];

/* ---------- icons ---------- */
const I = {
  qibla: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 5.5l3 6.5-3 6.5-3-6.5z" fill="currentColor"/></svg>',
  clock: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 6.5V12l3.5 2.2" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
  mosque: '<svg viewBox="0 0 24 24"><path d="M12 2c.8 1.4 1 2 1 3a1 1 0 0 1-2 0c0-1 .2-1.6 1-3zM5 21v-8h14v8M3 21h18M7.5 13c0-3 2-5 4.500-5s4.500 2 4.500 5M3 21V10M21 21V10" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>',
  dua: '<span class="mask" style="-webkit-mask-image:url(dua.png);mask-image:url(dua.png)"></span>',
  gear: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3.2" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.100 2.100M16.600 16.600l2.100 2.100M5.300 18.700l2.100-2.100M16.600 7.400l2.100-2.100" stroke="currentColor" stroke-width="2.200" stroke-linecap="round"/></svg>',
  pin: '<svg viewBox="0 0 24 24"><path d="M12 21s7-6.2 7-11.500A7 7 0 0 0 5 9.500C5 14.800 12 21 12 21z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="9.500" r="2.500" fill="currentColor"/></svg>',
  chev: '<svg viewBox="0 0 24 24"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2.400" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  left: '<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.600" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  right: '<svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="2.600" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  refresh: '<svg viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.500-5.800M20 4v5h-5" fill="none" stroke="currentColor" stroke-width="2.400" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  bell: '<svg viewBox="0 0 24 24"><path d="M6 17V11a6 6 0 0 1 12 0v6l1.500 2h-15zM10 21a2 2 0 0 0 4 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>',
  bellOff: '<svg viewBox="0 0 24 24"><path d="M6 17V11a6 6 0 0 1 12 0v6l1.500 2h-15zM10 21a2 2 0 0 0 4 0M4 4l16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>',
  check: '<svg viewBox="0 0 24 24"><path d="M5 12.500l4.500 4.500L19 7" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  rot: '<svg viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.500-5.800M20 4v5h-5" fill="none" stroke="currentColor" stroke-width="2.600" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  rotL: '<svg viewBox="0 0 24 24" style="transform:scaleX(-1)"><path d="M20 12a8 8 0 1 1-2.500-5.800M20 4v5h-5" fill="none" stroke="currentColor" stroke-width="2.600" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  walk: '<svg viewBox="0 0 24 24"><path d="M13.5 5.5c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zM9.8 8.9L7 23h2.1l1.8-8 2.1 2v6h2v-7.5l-2.1-2 .6-3C14.8 12 16.8 13 19 13v-2c-1.9 0-3.5-1-4.3-2.4l-1-1.6c-.4-.6-1-1-1.7-1-.3 0-.5.1-.8.1L6 8.3V13h2V9.6l1.8-.7" fill="currentColor"/></svg>',
  dir: '<svg viewBox="0 0 24 24"><path d="M3 11l18-8-8 18-2-8z" fill="currentColor"/></svg>',
  palette: '<svg viewBox="0 0 24 24"><path d="M12 3a9 9 0 1 0 0 18c1.500 0 2-1 1.500-2.200-.5-1.300.2-2.300 1.500-2.300H17a4 4 0 0 0 4-4C21 6.500 17 3 12 3z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="7.500" cy="11" r="1.300" fill="currentColor"/><circle cx="10.500" cy="7.500" r="1.300" fill="currentColor"/><circle cx="15" cy="8" r="1.300" fill="currentColor"/></svg>',
};

/* ---------- theme ---------- */
let T = {};
const FONTS = [["system", "System default"], ["cairo", "Cairo"], ["tajawal", "Tajawal"], ["almarai", "Almarai"], ["ibm-plex-sans-arabic", "IBM Plex Sans Arabic"], ["readex-pro", "Readex Pro"], ["mada", "Mada"], ["changa", "Changa"], ["el-messiri", "El Messiri"], ["noto-kufi-arabic", "Noto Kufi Arabic"], ["reem-kufi", "Reem Kufi"], ["kufam", "Kufam"], ["reem-kufi-fun", "Reem Kufi Fun"], ["alexandria", "Alexandria"], ["marhey", "Marhey"], ["baloo-bhaijaan-2", "Baloo Bhaijaan 2"], ["blaka", "Blaka"], ["lalezar", "Lalezar"], ["rakkas", "Rakkas"], ["noto-naskh-arabic", "Noto Naskh Arabic"], ["amiri", "Amiri"]];
const ONEWEIGHT = ["blaka", "lalezar", "rakkas"];
function applyFont() {
  let st = document.getElementById("appfont"); if (!st) { st = document.createElement("style"); st.id = "appfont"; document.head.appendChild(st); }
  const id = S.fontID;
  if (!id || id === "system") { st.textContent = ""; return; }
  const reg = id.split("-").map(w => w[0].toUpperCase() + w.slice(1)).join("");
  st.textContent = `@font-face{font-family:AppFont;font-weight:400;src:url(fonts/${id}-regular.woff2)}` + (ONEWEIGHT.includes(id) ? "" : `@font-face{font-family:AppFont;font-weight:700 900;src:url(fonts/${id}-bold.woff2)}`) + `:root{--ff:AppFont}`;
}
function applyTheme() {
  const pal = PALETTES.find(p => p.id === S.palette) || PALETTES[0];
  const dark = S.appearance === "dark" || (S.appearance === "auto" && matchMedia("(prefers-color-scheme: dark)").matches);
  const r = document.documentElement.style, i = dark ? 1 : 0;
  for (const [k, v] of Object.entries(pal.c)) r.setProperty("--" + k, H(v[i]));
  const g = k => H(pal.c[k][i]);
  T = { accent: g("accent"), deep: g("deep"), tint: g("tint"), card: g("card"), tile: g("tile"), line: g("line"), ink: g("ink"), muted: g("muted"), night: H(pal.c.bg[1]), ok: "#3DD68C", sun: "#FFB627" };
  applyFont();
  r.setProperty("--zg", "#35D07F"); r.setProperty("--zy", "#FFC83D"); r.setProperty("--zr", "#FF5A5F"); r.setProperty("--sun", "#FF9F1C");
  r.setProperty("--ts", String(+S.textSize || 1)); r.setProperty("--as", String(+S.azkarSize || 1));
  document.documentElement.style.fontSize = 16 * (+S.textSize || 1) + "px";
  document.documentElement.dir = rtl() ? "rtl" : "ltr";
  document.documentElement.lang = S.lang;
  document.body.classList.toggle("bold", !!S.bold);
  document.body.classList.toggle("dark", dark);
  document.querySelector('meta[name="theme-color"]').setAttribute("content", H(pal.c.bg[i]));
}
matchMedia("(prefers-color-scheme: dark)").addEventListener?.("change", () => { applyTheme(); render(); });

/* ---------- compass sensor ---------- */
const sensor = { heading: null, accuracy: null, available: true, listening: false, needPermission: false };
let shown = 0, dialEls = null, wasAligned = false;
// Android: native fused compass (CompassPlugin.java) does tilt compensation, declination and smoothing.
const NativeCompass = Capacitor.getPlatform() === "android" ? registerPlugin("Compass") : null;
let nativeOn = false;
// Android home-screen widgets (RihalWidgetPlugin.java): the app hands over the coming prayer times and the nearest mosque.
const NativeWidget = Capacitor.getPlatform() === "android" ? registerPlugin("RihalWidget") : null;
let widgetSig = "", widgetTimer = null;
// The widgets use the app's chosen colours: both the light and the dark set, so "Auto" can follow the phone.
function widgetTheme() {
  const pal = (PALETTES.find(x => x.id === S.palette) || PALETTES[0]).c, hx = n => "#" + n.toString(16).padStart(6, "0");
  const set = k => ({ bg: hx(k ? pal.card[1] : pal.tint[0]), line: hx(pal.line[k]), accent: hx(pal.accent[k]), deep: hx(pal.deep[k]), ink: hx(pal.ink[k]), muted: hx(pal.muted[k]) });
  return { mode: S.appearance || "auto", dark: set(1), light: set(0) };
}
function pushWidget() {
  if (!NativeWidget) return;
  clearTimeout(widgetTimer);
  widgetTimer = setTimeout(async () => {
    const p = S.place, now = Date.now(), key = p.lat.toFixed(2) + "," + p.lon.toFixed(2);
    const ev = prayerEvents(now, p.lat, p.lon, p.tz, method(), S.hanafi, offs(), 7).all.filter(e => e.prayer !== "sunrise");
    let list = mosqueState.key === key ? mosqueState.list : null;
    if (!list || !list.length) { try { list = JSON.parse(localStorage.getItem("rafeeq_m_" + key) || "null"); } catch (e) { list = null; } }
    const m = list && list[0];
    const data = {
      lang: S.lang, city: p.name,
      events: ev.map(e => ({ t: e.date, ar: PNAME_AR[e.prayer], name: ar() ? PNAME_EN[e.prayer] : pName(e.prayer), hm: clock(e.date, p.tz) })),
      mosque: m ? { name: m.name, d: Math.round(m.d) } : null,
      theme: widgetTheme(),
    };
    const sig = JSON.stringify(data);
    if (sig === widgetSig) return;
    widgetSig = sig;
    try { await NativeWidget.update({ data: sig }); } catch (e) {}
  }, 800);
}
async function pushLocation() {
  if (!NativeCompass || !S.place) return;
  try { await NativeCompass.setLocation({ lat: S.place.lat, lon: S.place.lon, alt: 0 }); } catch (e) {}
}
function headingFrom(e) {
  if (e.webkitCompassHeading != null) return e.webkitCompassHeading;
  if (e.alpha == null) return null;
  const a = e.alpha * Math.PI / 180, b = (e.beta || 0) * Math.PI / 180, g = (e.gamma || 0) * Math.PI / 180;
  const cA = Math.cos(a), sA = Math.sin(a), sB = Math.sin(b), cB = Math.cos(b), sG = Math.sin(g), cG = Math.cos(g);
  const rA = -cA * sG - sA * sB * cG, rB = -sA * sG + cA * sB * cG;
  let h = Math.atan2(rA, rB); if (h < 0) h += 2 * Math.PI;
  return h * 180 / Math.PI;
}
let lastSensor = 0;
function onOrient(e) {
  if (nativeOn) return;
  if (e.type === "deviceorientation" && sensor.absSeen && e.webkitCompassHeading == null) return;
  if (e.type === "deviceorientationabsolute") sensor.absSeen = true;
  if (e.type === "deviceorientation" && e.webkitCompassHeading == null && e.absolute !== true) return;
  const h = headingFrom(e); if (h == null || isNaN(h)) return;
  sensor.heading = h; sensor.accuracy = e.webkitCompassAccuracy ?? null;
  const now = performance.now(); if (now - lastSensor < 40) return; lastSensor = now;
  if (S.tab === 0) updateDial();
}
async function startCompass() {
  if (sensor.listening) return;
  if (NativeCompass) {
    try {
      const r = await NativeCompass.start();
      if (r && r.available) {
        if (!nativeOn) {
          nativeOn = true;
          NativeCompass.addListener("heading", o => {
            sensor.heading = o.heading; sensor.accuracy = o.accuracy;
            if (S.tab === 0) updateDial();
          });
        }
        sensor.listening = true;
        await pushLocation();
        return;
      }
    } catch (e) {}
  }
  try {
    if (typeof DeviceOrientationEvent !== "undefined" && typeof DeviceOrientationEvent.requestPermission === "function") {
      const r = await DeviceOrientationEvent.requestPermission();
      if (r !== "granted") { sensor.denied = true; return; }
    }
  } catch (e) { sensor.needPermission = true; return; }
  window.addEventListener("deviceorientationabsolute", onOrient, true);
  window.addEventListener("deviceorientation", onOrient, true);
  sensor.listening = true;
  setTimeout(() => { if (sensor.heading == null) { sensor.available = false; if (S.tab === 0) render(); } }, 2500);
}
const needsPerm = () => typeof DeviceOrientationEvent !== "undefined" && typeof DeviceOrientationEvent.requestPermission === "function";

/* ---------- state: place, weather ---------- */
const net = { online: navigator.onLine };
addEventListener("online", () => { net.online = true; loadWeather(); render(); }); addEventListener("offline", () => { net.online = false; render(); });
let weather = null;
async function loadWeather() {
  try {
    const p = S.place;
    const r = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${r2(p.lat)}&longitude=${r2(p.lon)}&current=temperature_2m,relative_humidity_2m,weather_code,is_day&timezone=auto`);
    const j = await r.json(); weather = { t: j.current.temperature_2m, h: j.current.relative_humidity_2m, code: j.current.weather_code, day: j.current.is_day === 1 };
    const el = $("#wchip"); if (el) el.outerHTML = weatherChip();
  } catch (e) {}
}
function wIcon(c, day) {
  if (c === 0) return day ? "☀️" : "🌙"; if (c <= 2) return day ? "🌤️" : "☁️"; if (c === 3) return "☁️"; if (c <= 48) return "🌫️";
  if (c <= 57) return "🌦️"; if (c <= 67) return "🌧️"; if (c <= 77) return "🌨️"; if (c <= 82) return "🌧️"; if (c <= 86) return "🌨️"; return "⛈️";
}
function weatherChip() { return weatherBlock(); }
// Coordinates sent to online services are rounded to 2 decimals (about 1 km), as in the iPhone app.
const r2 = v => (Math.round(v * 100) / 100).toFixed(2);
const PRIVACY_URL = "https://github.com/wsaleh81/Rihal/blob/main/PRIVACY.md";
const PRIVACY_LABEL = { ar: "سياسة الخصوصية", tr: "Gizlilik politikası", fr: "Politique de confidentialité", it: "Informativa sulla privacy", de: "Datenschutzerklärung", nl: "Privacybeleid", es: "Política de privacidad", ur: "رازداری کی پالیسی", ta: "தனியுரிமைக் கொள்கை", ru: "Политика конфиденциальности" };
function qiblaDeg() { return Qibla.bearing(S.place.lat, S.place.lon); }

async function useGPS(silent) {
  gpsState = "finding"; if (!silent) render();
  try {
    let pos;
    if (Capacitor.isNativePlatform()) {
      const pm = await Geolocation.requestPermissions();
      if (pm.location === "denied") throw new Error("denied");
      pos = await Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 15000 });
    } else {
      pos = await new Promise((ok, no) => navigator.geolocation.getCurrentPosition(ok, no, { enableHighAccuracy: true, timeout: 15000 }));
    }
    const { latitude: lat, longitude: lon, accuracy } = pos.coords;
    gpsAcc = accuracy;
    let near = CITIES.map(c => ({ c, d: haversine(lat, lon, c.lat, c.lon) })).sort((a, b) => a.d - b.d)[0];
    let name = near.d < 40 ? near.c.name : "My location", country = near.c.country, iso = near.c.iso;
    if (net.online) {
      try {
        const r = await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&zoom=10&accept-language=${ar() ? "ar" : "en"}&lat=${r2(lat)}&lon=${r2(lon)}`);
        const j = await r.json(); const a = j.address || {};
        name = a.city || a.town || a.village || a.suburb || a.county || a.state || name; country = a.country || country; iso = (a.country_code || iso || "--").toUpperCase();
      } catch (e) {}
    } else if (near.d >= 40) { iso = near.c.iso; }
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || near.c.tz;
    S.place = { name, country, lat, lon, tz, iso, gps: true }; S.gps = true; save(); pushLocation();
    gpsState = "ok"; gpsFixAt = Date.now(); weather = null; loadWeather(); scheduleAlerts(); render(); if (S.tab === 1 || NativeWidget) loadMosques();
  } catch (e) { gpsState = "denied"; render(); }
}
let gpsState = "idle", gpsAcc = null;

/* ---------- alerts ---------- */
const nativeOK = () => Capacitor.isNativePlatform();
async function scheduleAlerts() {
  if (!nativeOK()) return;
  pushFajr();
  try {
    const pending = await LocalNotifications.getPending();
    if (pending.notifications.length) await LocalNotifications.cancel({ notifications: pending.notifications });
    const azOn = S.azMorning || S.azEvening || S.azPrayer || S.azFriday;
    if (!S.notif && !azOn) return;
    const perm = await LocalNotifications.checkPermissions();
    if (perm.display !== "granted") { alertsDenied = true; return; }
    alertsDenied = false;
    try { exactOK = (await LocalNotifications.checkExactNotificationSetting()).exact_alarm === "granted"; } catch (e) { exactOK = true; }
    await LocalNotifications.createChannel({ id: "adhan", name: "Prayer alerts", importance: 5, visibility: 1, vibration: true });
    await LocalNotifications.createChannel({ id: "adhan_sound", name: "Adhan", importance: 5, visibility: 1, vibration: true, sound: "adhan.wav" });
    // A channel per chosen sound (Android fixes a channel's sound when it is created).
    const chan = k => k === "adhan" ? "adhan_sound" : "adhan_" + k + "_v2";   // _v2: Azan 2 and the Fajr adhan were swapped (a channel keeps its first sound)
    for (const k of new Set([S.adhanSound, S.fajrSound])) if (k !== "adhan") await LocalNotifications.createChannel({ id: chan(k), name: "Adhan " + k.replace(/\D/g, ""), importance: 5, visibility: 1, vibration: true, sound: sndFile(k) });
    const p = S.place, now = Date.now();
    const ev = prayerEvents(now, p.lat, p.lon, p.tz, method(), S.hanafi, offs(), 10).all
      .filter(e => e.date > now && (e.prayer !== "sunrise" || S.sunriseAlert) && (!S.muted[e.prayer] || alarmOn(e.prayer)));
    const list = []; let id = 1;
    if (S.notif) for (const e of ev.slice(0, 120)) {
      const nm = pName(e.prayer), sound = alarmOn(e.prayer);
      list.push({ id: id++, title: ar() && e.prayer !== "sunrise" ? "صلاة " + nm : nm, body: p.name, channelId: sound ? chan(e.prayer === "fajr" ? S.fajrSound : S.adhanSound) : "adhan", sound: sound ? sndFile(e.prayer === "fajr" ? S.fajrSound : S.adhanSound) : undefined, isExactNotification: exactOK, schedule: { at: new Date(e.date), allowWhileIdle: true } });
      if (S.remind > 0 && e.date - S.remind * 60000 > now)
        list.push({ id: id++, title: ar() ? `${nm} بعد ${S.remind} دقيقة` : F("{0} in {1} minutes", nm, S.remind), body: p.name, channelId: "adhan", isExactNotification: exactOK, schedule: { at: new Date(e.date - S.remind * 60000), allowWhileIdle: true } });
    }
    if (azOn) azkarReminders(now).forEach(r => list.push({ id: 5000 + id++, title: r.title, body: r.body, channelId: "adhan", isExactNotification: exactOK, extra: { azcat: r.cat }, schedule: { at: new Date(r.at), allowWhileIdle: true } }));
    for (let i = 0; i < list.length; i += 50) await LocalNotifications.schedule({ notifications: list.slice(i, i + 50) });
  } catch (e) { console.log("alerts", e); }
}
// Azkar reminders for the next 7 days: morning Fajr+15 then every 2 h until Dhuhr, evening Asr+15 then every 2 h until Isha,
// after-prayer 15 min after each prayer. Today's reminders are skipped once that azkar is finished.
function azkarReminders(now) {
  syncAzkarResets();
  const p = S.place, M = 60000, out = [];
  const body = ar() ? "لم تكتمل بعد، اضغط للمتابعة" : L("Not finished yet. Tap to continue.");
  const AZN = ar() ? ["أذكار الصباح", "أذكار المساء", "أذكار بعد الصلاة"] : [L("Morning azkar"), L("Evening azkar"), L("After-prayer azkar")];
  const ev = prayerEvents(now, p.lat, p.lon, p.tz, method(), S.hanafi, offs(), 7).all;
  const next = (e, name) => ev.find(x => x.prayer === name && x.date > e.date);
  for (const e of ev) {
    if (e.prayer === "fajr" && S.azMorning) {
      const end = next(e, "dhuhr"), done = Math.abs((azStamp.morning || 0) - e.date) < 1800000 && catDone("morning");
      if (end && !done) for (let t = e.date + 15 * M; t < end.date; t += 120 * M) if (t > now) out.push({ at: t, cat: 0, title: AZN[0], body });
    }
    if (e.prayer === "asr" && S.azEvening) {
      const end = next(e, "isha"), done = Math.abs((azStamp.evening || 0) - e.date) < 1800000 && catDone("evening");
      if (end && !done) for (let t = e.date + 15 * M; t < end.date; t += 120 * M) if (t > now) out.push({ at: t, cat: 1, title: AZN[1], body });
    }
    if (S.azPrayer && e.prayer !== "sunrise" && e.date + 15 * M > now && !(Math.abs((azStamp.afterPrayer || 0) - e.date) < 1800000 && catDone("afterPrayer")))
      out.push({ at: e.date + 15 * M, cat: 2, title: AZN[2], body: `${pName(e.prayer)} · ${body}` });
  }
  // Friday: Surat al-Kahf two and a half hours before Dhuhr (Jumu'ah), and the hour of answered dua one hour before Maghrib.
  if (S.azFriday) {
    const isFri = t => new Intl.DateTimeFormat("en-US", { timeZone: p.tz, weekday: "short" }).format(new Date(t)) === "Fri";
    for (const e of ev) {
      if (e.prayer === "dhuhr" && isFri(e.date) && e.date - 150 * M > now)
        out.push({ at: e.date - 150 * M, cat: "m:0", title: ar() ? "يوم الجمعة: سورة الكهف" : L("Friday: Surat al-Kahf"), body: ar() ? "اقرأ سورة الكهف وأكثر من الصلاة على النبي ﷺ" : L("Read Surat al-Kahf and send many prayers on the Prophet ﷺ") });
      if (e.prayer === "maghrib" && isFri(e.date) && e.date - 60 * M > now)
        out.push({ at: e.date - 60 * M, cat: "m:0", title: ar() ? "ساعة الإجابة يوم الجمعة" : L("Friday: the hour of answered dua"), body: ar() ? "آخر ساعة قبل المغرب، أكثر من الدعاء" : L("The last hour before Maghrib. Make plenty of dua.") });
    }
  }
  return out.sort((a, b) => a.at - b.at).slice(0, 150);
}
async function setAlerts(on) {
  if (on && nativeOK()) {
    const r = await LocalNotifications.requestPermissions();
    if (r.display !== "granted") { alertsDenied = true; S.notif = false; save(); render(); return; }
    try { const ex = await LocalNotifications.checkExactNotificationSetting(); if (ex.exact_alarm !== "granted") await LocalNotifications.changeExactNotificationSetting(); } catch (e) {}
  } else if (on && typeof Notification !== "undefined") { try { await Notification.requestPermission(); } catch (e) {} }
  alertsDenied = false; S.notif = on; save(); await scheduleAlerts(); render();
}
let alertsDenied = false, exactOK = true, battOK = true;
// Battery optimization (Samsung "sleeping apps" and the like) holds alerts back for hours; check and ask Android to exempt Rihal.
async function checkBattery() {
  if (!NativeWidget) return;
  try { const r = await NativeWidget.batteryStatus(); battOK = !!r.ignoring; exactOK = !!r.exact; } catch (e) {}
}
async function askBattery() { if (!NativeWidget) return; try { await NativeWidget.requestBattery(); } catch (e) {} }
// Explain first, then open Android's Allow / Deny question.
function explainBattery() {
  return new Promise(done => confirmBox(
    ar() ? "سيسألك الهاتف الآن عن السماح لرحّال بالعمل دون قيود توفير البطارية. اختر «السماح» حتى يصل الأذان والتذكيرات في وقتها تمامًا، ولا يؤثر ذلك على البطارية إلا قليلًا."
      : L("Your phone will now ask to let Rihal run without battery-saving limits. Choose Allow so the adhan and reminders arrive exactly on time. It uses very little battery."),
    async () => { await askBattery(); done(); },
    { title: ar() ? "لكي يصل الأذان في وقته" : L("So the adhan arrives on time"), yes: ar() ? "متابعة" : L("Continue"), no: ar() ? "لاحقًا" : L("Later"), good: true }));
}
// First start (and every start while alerts are on): ask for notification permission, like the iPhone app does.
async function ensureAlertPermission() {
  if (!nativeOK() || !S.notif) return;
  try {
    let r = await LocalNotifications.checkPermissions();
    if (r.display === "prompt" || r.display === "prompt-with-rationale") r = await LocalNotifications.requestPermissions();
    alertsDenied = r.display !== "granted";
  } catch (e) {}
  await checkBattery();
  // Ask once by itself (the system shows Allow / Deny); after that the Settings row offers it.
  if (!battOK && !S.battAsked && !alertsDenied) { S.battAsked = true; save(); explainBattery(); }
  await scheduleAlerts(); if (S.tab === 4) render();
}
async function azkarPermission() {
  if (nativeOK()) { try { const r = await LocalNotifications.requestPermissions(); alertsDenied = r.display !== "granted"; } catch (e) {} }
  await scheduleAlerts(); render();
}
async function askExact() { try { await LocalNotifications.changeExactNotificationSetting(); } catch (e) {} await scheduleAlerts(); render(); }
const offs = () => S.off || {};

/* ---------- formatting ---------- */
const tf = tz => new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false });
const clock = (ms, tz) => (ms == null ? "—" : tf(tz).format(new Date(ms)));
const pad = n => String(n).padStart(2, "0");
const cd = ms => { const s = Math.max(0, Math.floor(ms / 1000)); return `${pad(Math.floor(s / 3600))}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}`; };

/* ---------- UI pieces ---------- */
const title = (en, arT) => (ar() ? `<div class="ptitle ar">${arT}</div>` : `<div class="ptitle"><span>${L(en)}</span><span class="ar">${arT}</span></div>`);
const badge = c => `<span class="iso">${esc(iso3((c || "--").toUpperCase()))}</span>`;
let prayDay = 0, azkarCat = null, azkarCounts = {}, mosqueAround = null, mosqueState = { loading: false, list: [], failed: false, key: "" };
let pickerOpen = null, pickerQuery = "", pickerRemote = [], sheet = null;
try { azkarCounts = JSON.parse(localStorage.getItem("rafeeq_counts") || "{}"); } catch (e) {}

/* ---------- azkar progress: automatic reset by prayer time, reminders ---------- */
// Morning azkar start again at Fajr, evening at Asr, after-prayer at every prayer, sleep at Isha. Travel and "more" only by hand.
const AZ_RESET = { morning: ["fajr"], evening: ["asr"], afterPrayer: ["fajr", "dhuhr", "asr", "maghrib", "isha"], sleep: ["isha"] };
let azStamp = {}; try { azStamp = JSON.parse(localStorage.getItem("rihal_azstamp") || "{}"); } catch (e) {}
function lastPrayer(names, now = Date.now()) {
  const p = S.place, ev = prayerEvents(now, p.lat, p.lon, p.tz, method(), S.hanafi, offs(), 1).all.filter(e => names.includes(e.prayer) && e.date <= now);
  return ev.length ? ev[ev.length - 1].date : 0;
}
function saveCounts() { try { localStorage.setItem("rafeeq_counts", JSON.stringify(azkarCounts)); localStorage.setItem("rihal_azstamp", JSON.stringify(azStamp)); } catch (e) {} }
// Everything else (travel, Friday and all "more azkar") starts again every day at Fajr.
const azDaily = () => [...DATA.azkar.travel, ...MORE.flatMap(g => g.items)];
function syncAzkarResets() {
  let ch = false;
  const groups = { ...Object.fromEntries(Object.keys(AZ_RESET).map(c => [c, [AZ_RESET[c], () => DATA.azkar[c]]])), daily: [["fajr"], azDaily] };
  for (const cat in groups) {
    const [names, items] = groups[cat], st = lastPrayer(names);
    // Same prayer time (a small GPS move shifts it by seconds): keep the counts.
    if (!st || (azStamp[cat] != null && Math.abs(azStamp[cat] - st) < 30 * 60000)) continue;
    for (const d of items()) if (azkarCounts[d.id]) delete azkarCounts[d.id];
    azStamp[cat] = st; ch = true;
  }
  if (ch) saveCounts();
}
const catDone = cat => DATA.azkar[cat].every(d => (azkarCounts[d.id] || 0) >= d.n);
const listItems = () => azkarCat === "more" || azkarCat == null ? null : isMore() ? MORE[+azkarCat.slice(2)].items : DATA.azkar[CATS[azkarCat]];
const findDhikr = id => { for (const c of CATS) { const d = DATA.azkar[c].find(x => x.id === id); if (d) return d; } for (const g of MORE) { const d = g.items.find(x => x.id === id); if (d) return d; } return null; };
const progBadge = items => { const t = items.length, d = items.filter(x => (azkarCounts[x.id] || 0) >= x.n).length; return d === t ? `<small class="pdone">✓</small>` : `<small>${d ? `${d}/${t}` : t}</small>`; };

function placeBtn() {
  return `<button class="pill" data-act="picker">${I.pin}<span class="pn">${esc(S.place.name)}</span>${I.chev}</button>`;
}

/* ----- Home: date, location, now/next with weather, compass, prayer rows ----- */
const PI = {
  fajr: '<svg viewBox="0 0 24 24"><path d="M3 18h18M12 6v4M5.5 9.5l2 2M18.5 9.5l-2 2M7 18a5 5 0 0 1 10 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  sunrise: '<svg viewBox="0 0 24 24"><path d="M3 18h18M12 4v3M4.5 9l2 2M19.5 9l-2 2M7 18a5 5 0 0 1 10 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  dhuhr: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4.2" fill="currentColor"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2 2M16.7 16.7l2 2M5.3 18.7l2-2M16.7 7.3l2-2" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
  asr: '<svg viewBox="0 0 24 24"><circle cx="9" cy="9" r="3.4" fill="currentColor"/><path d="M9 2.5v1.8M2.5 9h1.8M4.4 4.4l1.2 1.2M13.6 4.4l-1.2 1.2" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M8 20h10a3.5 3.5 0 0 0 .3-7 4.5 4.5 0 0 0-8.6 1A3 3 0 0 0 8 20z" fill="currentColor" opacity=".9"/></svg>',
  maghrib: '<svg viewBox="0 0 24 24"><path d="M3 18h18M12 8v-3M4.5 11l2 2M19.5 11l-2 2M7 18a5 5 0 0 1 10 0M9 21h6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  isha: '<svg viewBox="0 0 24 24"><path d="M20 14.5A8 8 0 1 1 9.500 4a6.500 6.500 0 0 0 10.500 10.500z" fill="currentColor"/><path d="M17 3v3M15.500 4.500h3" stroke="currentColor" stroke-width="1.800" stroke-linecap="round"/></svg>',
  alarm: '<svg viewBox="0 0 24 24"><circle cx="12" cy="13" r="7" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 9.500V13l2.500 1.500M4 6l3-2.500M20 6l-3-2.500" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  alarmOn: '<svg viewBox="0 0 24 24"><circle cx="12" cy="13" r="7.500" fill="currentColor"/><path d="M12 9v4.500l2.500 1.500M4 6l3-2.500M20 6l-3-2.500" fill="none" stroke="var(--tile)" stroke-width="2" stroke-linecap="round"/></svg>',
  gps: '<svg viewBox="0 0 24 24"><path d="M12 21s7-6.2 7-11.500A7 7 0 0 0 5 9.500C5 14.800 12 21 12 21z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="9.500" r="2.500" fill="currentColor"/></svg>',
  gpsOff: '<svg viewBox="0 0 24 24"><path d="M12 21s7-6.2 7-11.500A7 7 0 0 0 5 9.500C5 14.800 12 21 12 21z" fill="none" stroke="currentColor" stroke-width="2"/><path d="M4 4l16 16" stroke="currentColor" stroke-width="2.400" stroke-linecap="round"/></svg>',
  book: '<svg viewBox="0 0 24 24"><path d="M4 5.500A2.500 2.500 0 0 1 6.500 3H20v15H6.500A2.500 2.500 0 0 0 4 20.500zM4 20.500A2.500 2.500 0 0 0 6.500 23H20" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>',
};
I.book = PI.book;
let gpsFixAt = null;
const agoTxt = () => {
  if (!gpsFixAt) return L("just now"); const m = Math.floor((Date.now() - gpsFixAt) / 60000);
  if (ar()) return m < 1 ? "الآن" : m < 60 ? `منذ ${m} د` : `منذ ${Math.floor(m / 60)} س`;
  return m < 1 ? L("just now") : m < 60 ? F("{0} min ago", m) : F("{0} h ago", Math.floor(m / 60));
};
const alarmOn = k => k !== "sunrise" && !!(S.alarm && S.alarm[k]);

function bannerHTML() {
  const p = S.place, loc = p.country ? `${p.name}, ${p.country}` : p.name;
  const pill = (ic, t, act, cls) => `<button class="bpill ${cls || ""}" data-act="${act}">${ic ? ic : ""}<span>${t}</span></button>`;
  const cityPill = pill("", L("City"), "picker");
  let tint, title, sub, icon = I.pin, trailing = "", dot = false, spin = false;
  if (gpsState === "finding") { tint = "var(--accent)"; title = L("Finding your location…"); sub = ar() ? `عرض ${p.name} حتى التأكيد` : F("Showing {0} until confirmed", p.name); spin = true; trailing = cityPill; }
  else if (gpsState === "denied") { tint = "var(--zr)"; title = L("Location not found"); sub = ar() ? `استخدام ${p.name}` : F("Using {0}", p.name); icon = PI.gpsOff; trailing = pill("", L("Choose city"), "picker", "solid"); }
  else if (S.gps) { tint = "var(--zg)"; title = loc; sub = ar() ? "GPS مؤكد · " + agoTxt() : F("GPS confirmed · {0}", agoTxt()); dot = true; trailing = pill(I.refresh, L("Refresh"), "refreshGPS", "deep") + cityPill; }
  else { tint = "var(--muted)"; title = p.name; sub = L("Manual city"); trailing = pill(PI.gps, L("Use GPS"), "refreshGPS", "deep") + cityPill; }
  return `<div class="bnr" style="--t:${tint}"><div class="bico">${spin ? '<i class="spin"></i>' : icon}${dot ? '<i class="bdot"></i>' : ""}</div>
    <div class="btxt"><b>${esc(title)}</b><small>${esc(sub)}</small></div><div class="bact">${trailing}</div></div>`;
}
function weatherBlock() {
  const w = weather;
  const txt = !w ? (net.online ? "…" : "—") : (S.temp === "f" ? Math.round(w.t * 9 / 5 + 32) + "°F" : Math.round(w.t) + "°C");
  const hum = w && w.h != null ? Math.round(w.h) + "%" : (!w && net.online ? "…" : "—");
  return `<div class="wgrp" id="wchip"><div class="wblk"><span class="wi">${w ? wIcon(w.code, w.day) : (net.online ? "☁️" : "📴")}</span><b>${txt}</b></div>
    <div class="wblk" aria-label="${ar() ? "الرطوبة" : L("Humidity")}"><span class="wi">💧</span><b>${hum}</b></div></div>`;
}

// The native sensor runs only while the compass is on screen; it stops on other tabs.
async function stopCompass() {
  if (!nativeOn || !sensor.listening) return;
  sensor.listening = false;
  try { await NativeCompass.stop(); } catch (e) {}
}
function zoneHex(d) { if (d == null) return T.muted; const a = Math.abs(d); return a > 45 ? "#FF5A5F" : a > 15 ? "#FFC93C" : "#3DD68C"; }
function target() { return sensor.heading; }
// Heading shown on the dial follows the sensor like the iPhone app: ignore changes under 1 degree,
// then ease to the new heading over about 0.18 s.
let goal = null, animating = false, lastDrawn = null;
function updateDial() {
  const root = $("#hdial"); if (!root) { animating = false; return; }
  const t = target();
  if (t != null) { const n = $(".hleft > .note:not(.calib)"); if (n && !n.querySelector("button")) n.remove(); }
  if (t != null && (goal == null || Math.abs(diff(t, goal)) >= 1)) goal = t;
  calibNote();
  if (goal != null && !animating && Math.abs(diff(goal, shown)) >= 0.05) { animating = true; requestAnimationFrame(animateDial); }
  if (!animating && lastDrawn != null && t != null && Math.abs(diff(t, lastDrawn)) < 0.5) return;
  drawDial();
}
function animateDial() {
  if (!$("#hdial") || goal == null) { animating = false; return; }
  const step = diff(goal, shown);
  if (Math.abs(step) < 0.05) { shown = norm(goal); animating = false; drawDial(); return; }
  shown = norm(shown + step * 0.22);
  drawDial();
  requestAnimationFrame(animateDial);
}
function drawDial() {
  const root = $("#hdial"); if (!root) return;
  const t = target(), q = qiblaDeg();
  lastDrawn = t;
  const d = t == null ? null : diff(q, t), aligned = d != null && Math.abs(d) <= 3;
  dialUpdate(root, T, shown, q, aligned, S.compass === "rings" ? zoneHex(d) : null);
  if (aligned && !wasAligned && navigator.vibrate) navigator.vibrate(40);
  wasAligned = aligned;
}
// Android reports magnetometer accuracy: 0 unreliable, 1 low. Ask for a figure-of-eight, like the iPhone app.
function calibNote() {
  const need = nativeOn && sensor.accuracy != null && sensor.accuracy <= 1;
  let n = $(".hleft > .note.calib");
  if (need && !n) {
    const host = $(".hleft .hdial"); if (!host) return;
    host.insertAdjacentHTML("afterend", `<div class="note calib">${L("Compass needs calibration. Move your phone in a figure of eight.")}</div>`);
  } else if (!need && n) n.remove();
}
function dialHTML() {
  const rings = S.compass === "rings";
  return `<div class="hdial ${rings ? "rings" : "classic"}"><div class="dialwrap2" id="hdial"><div class="${rings ? "" : "dial"}">${rings ? ringsSVG(T) : classicSVG(T, S.compass !== "classicGrey")}</div></div></div>`;
}
function viewHome() {
  const now = Date.now(), p = S.place;
  const shownMs = now + prayDay * 86400000;
  const day = prayDay === 0 ? prayerEvents(now, p.lat, p.lon, p.tz, method(), S.hanafi, offs()).today : dayFor(shownMs, p.lat, p.lon, p.tz, method(), S.hanafi, offs());
  const dopt = prayDay === 0 ? { weekday: "long", day: "numeric", month: "long" } : { weekday: "long", day: "numeric", month: "long", year: "numeric" };
  const greg = new Intl.DateTimeFormat(ar() ? "ar-u-nu-latn" : U[S.lang] ? S.lang + "-u-nu-latn" : "en-GB", { timeZone: p.tz, ...dopt }).format(new Date(shownMs));
  const hij = new Intl.DateTimeFormat((ar() || !U[S.lang] ? "ar-SA" : S.lang) + "-u-ca-islamic-umalqura-nu-latn", { timeZone: p.tz, day: "numeric", month: "long", year: "numeric" }).format(new Date(shownMs)).replace(/\s*هـ$/, "") + (U[S.lang] ? "" : " هـ");
  let note = "";
  const noCompass = ar() ? "هذا الجهاز بلا بوصلة." : L("This device has no compass.");
  {
    if (sensor.denied) note = noCompass;
    else if (needsPerm() && !sensor.listening) note = `<button class="btn" data-act="compass">${ar() ? "تشغيل البوصلة" : F("Start the compass")}</button>`;
    else if (!sensor.available) note = noCompass;
    else if (sensor.heading == null) note = L("Starting the compass…");
  }
  const rows = PRAYERS.map(k => `<div class="r2" id="r-${k}" data-k="${k}"><div class="rl"><span class="ri">${PI[k]}</span><span class="rn">${pName(k)}</span><span class="rchip" id="rc-${k}"></span></div>
    <div class="rt">${clock(day[k], p.tz)}</div><div class="rr">${k === "sunrise" ? "" : `<button class="rb ${alarmOn(k) ? "on" : ""}" data-act="alarm" data-k="${k}" aria-label="adhan">${alarmOn(k) ? PI.alarmOn : PI.alarm}</button>`}
    <button class="rb ${S.muted[k] ? "" : "on"}" data-act="mute" data-k="${k}" aria-label="alert">${S.muted[k] ? I.bellOff : I.bell}</button></div></div>`).join("");
  return `${title("Prayer Times", "مواقيت الصلاة")}
  <div class="datecard"><div class="dtx"><b>${greg}</b><span>${hij}</span></div>
    <div class="dnav"><button class="nbtn" data-act="day" data-d="-1">${rtl() ? I.right : I.left}</button><button class="nbtn" data-act="day" data-d="1">${rtl() ? I.left : I.right}</button></div></div>
  <div class="hsplit">
   <div class="hleft">
    <div id="bnrhost">${bannerHTML()}</div>
    <div class="hero2" id="hero"></div>
    ${dialHTML()}
    ${(note ? `<div class="note">${note}</div>` : "")}
   </div>
   <div class="hright">
    <div class="plist2">${rows}</div>
    <div class="foot">${ar() ? `تم الحساب على هذا الجهاز · طريقة ${L(method().name)}` : F("Calculated on this device · {0} method", L(method().name))}</div>
   </div>
  </div>`;
}
function afterHome() {
  dialEls = true; lastDrawn = null;
  const p = S.place; const sl = $("#sunlayer"); if (sl) sl.innerHTML = sunLayerSVG(sunInfo(p.lat, p.lon, new Date()));
  updateDial(); tickHome();
  startCompass();
}
function tickHome() {
  const hero = $("#hero"); if (!hero) return;
  const p = S.place, now = Date.now();
  const r = prayerEvents(now, p.lat, p.lon, p.tz, method(), S.hanafi, offs());
  const counted = r.all.filter(e => e.prayer !== "sunrise");
  const next = counted.find(e => e.date > now), prev = [...counted].reverse().find(e => e.date <= now);
  // after sunrise the Fajr time is over: the card shows "الصبح" (morning) from sunrise until Dhuhr
  const cur = [...r.all].reverse().find(e => e.date <= now);
  const nowEv = cur && cur.prayer === "sunrise" ? cur : prev;
  const nowName = !nowEv ? "—" : nowEv.prayer === "sunrise" ? (ar() ? "الصبح" : L("Morning")) : pName(nowEv.prayer);
  const frac = next && prev ? Math.max(0.02, Math.min(1, (now - prev.date) / (next.date - prev.date))) : 0;
  const C = 2 * Math.PI * 46.5;
  hero.classList.toggle("nonow", S.showNow === false);
  hero.innerHTML = `${S.showNow === false ? "" : `<div class="hn"><div class="hnm"><span class="nowb">${L("NOW")}</span><span class="hic">${nowEv ? PI[nowEv.prayer] : I.clock}</span><b>${nowName}</b></div><span class="hnt">${nowEv ? clock(nowEv.date, p.tz) : "--:--"}</span></div>`}
    ${weatherBlock()}
    <div class="hrg"><svg viewBox="0 0 104 104"><defs><linearGradient id="rg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="var(--accent)"/><stop offset="1" stop-color="var(--deep)"/></linearGradient></defs><circle cx="52" cy="52" r="46.5" fill="none" stroke="var(--tile)" stroke-width="7"/><circle cx="52" cy="52" r="46.5" fill="none" stroke="url(#rg)" stroke-width="7" stroke-linecap="round" stroke-dasharray="${C * frac} ${C}" transform="rotate(-90 52 52)"/></svg>
      <div class="hrt"><div class="r1"><i>${next ? PI[next.prayer] : ""}</i>${next ? (ar() ? `${pName(next.prayer)} بعد` : F("{0} in", pName(next.prayer))) : "—"}</div><div class="r2t">${next ? cd(next.date - now) : "--:--:--"}</div><div class="r3">${next ? (ar() ? "عند " + clock(next.date, p.tz) : F("at {0}", clock(next.date, p.tz))) : L("Not available here")}</div></div></div>`;
  fitRing();
  for (const k of PRAYERS) {
    const el = $("#r-" + k); if (!el) continue;
    const t = r.today[k];
    const isNow = prayDay === 0 && nowEv && nowEv.prayer === k && nowEv.date === t, isNext = prayDay === 0 && next && next.prayer === k && next.date === t;
    el.classList.toggle("now", !!isNow); el.classList.toggle("past", prayDay === 0 && !isNow && t != null && t < now);
    const ch = $("#rc-" + k); if (ch) ch.innerHTML = isNow ? `<i class="chip1 on">${L("NOW")}</i>` : isNext ? `<i class="chip1">${L("NEXT")}</i>` : "";
  }
}

/* ----- Mosques tab ----- */
function distTxt(m) { return m < 1000 ? `${Math.round(m)} ${L("m")}` : `${(m / 1000).toFixed(1)} ${L("km")}`; }
function viewMosques() {
  const c = S.place, ms = mosqueState;
  const lab = S.gps ? `${L("Near me")} · ${c.name}` : (ar() ? `بالقرب من ${c.name}` : F("Near {0}", c.name));
  let body = "";
  if (!net.online && !ms.list.length) body = notice("📴", "You are offline", "Finding mosques needs internet. Prayer times and Qibla keep working without it.");
  else if (ms.loading && !ms.list.length) body = `<div class="center muted pad">${L("Looking for mosques…")}</div>`;
  else if (ms.failed) body = notice("⚠️", "Couldn’t search", "Check your connection and tap refresh.");
  else if (!ms.list.length) body = notice("📍", "No mosques found nearby", "Try another city from the menu above.");
  else {
    const f = ms.list[0];
    body = `<div class="card sug">${mCard(f, true)}</div><div class="sect">${ar() ? "قريبة" : F("Nearby")}</div>` + ms.list.slice(1).map(m => `<div class="card mrow">${mCard(m)}</div>`).join("") +
      `<div class="foot">${ar() ? "المصدر: © مساهمو OpenStreetMap. المسافات بخط مستقيم من موقعك." : F("Source: © OpenStreetMap contributors. Distances are straight-line from your position.")}</div>`;
  }
  return `${title("Mosques", "المساجد")}
  <div class="row between gap"><button class="pill" data-act="mpicker">${I.pin}<span class="pn">${esc(lab)}</span>${I.chev}</button><button class="iconbtn" data-act="mrefresh">${I.refresh}</button></div>${body}`;
}
const notice = (ic, t, s) => `<div class="notice"><div class="ni">${ic}</div><b>${L(t)}</b><p>${L(s)}</p></div>`;
// One compact line per mosque: the name on one side; distance, walking time and a round directions button on the other.
function mCard(m, big) {
  return `<div class="mline"><div class="minfo">
     <div class="mname">${esc(m.name)}</div>
     ${m.address ? `<div class="muted sm maddr">${esc(m.address)}</div>` : ""}</div>
   <div class="mmeta"><span>${distTxt(m.d)}</span><span class="mwalk" aria-label="${L("walk")}">${I.walk}${Math.max(1, Math.round(m.d / 80))} ${L("min")}</span></div>
   <button class="dirbtn round" data-act="directions" data-lat="${m.lat}" data-lon="${m.lon}" data-name="${esc(m.name)}" aria-label="${L("Directions")}">${I.dir}</button></div>`;
}
let dirTarget = null;
function dirSheet() {
  const d = dirTarget, g = `https://www.google.com/maps/dir/?api=1&destination=${d.lat},${d.lon}&travelmode=walking`, w = `https://waze.com/ul?ll=${d.lat},${d.lon}&navigate=yes`;
  return `<div class="sheetbg" data-act="closeSheet"></div><div class="sheet dirsheet"><div class="grab"></div><h3>${esc(d.name)}</h3>
    <a class="dopt" href="${g}" target="_blank" rel="noopener"><span>🗺️</span><span>${L("Open in Google Maps")}</span></a>
    <a class="dopt" href="${w}" target="_blank" rel="noopener"><span>🚗</span><span>${L("Open in Waze")}</span></a>
    <button class="btn ghost big" data-act="closeSheet">${L("Cancel")}</button></div>`;
}
// fetch with a time limit, so a server that never answers cannot stall the search
async function getJSON(url, ms) {
  const ac = new AbortController(), t = setTimeout(() => ac.abort(), ms);
  try { const r = await fetch(url, { signal: ac.signal }); if (!r.ok) throw new Error(r.status); return await r.json(); }
  finally { clearTimeout(t); }
}
// resolves with the first non-empty list from the given promises, or null when all fail or the time is up
function firstOf(promises, ms) {
  return new Promise(done => {
    let left = promises.length; const timer = setTimeout(() => done(null), ms);
    for (const p of promises) p.then(l => { if (l && l.length) { clearTimeout(timer); done(l); } else if (!--left) { clearTimeout(timer); done(null); } },
                                     () => { if (!--left) { clearTimeout(timer); done(null); } });
  });
}
const mosqueItem = (c, la, lo, t) => ({ name: (ar() ? (t["name:ar"] || t.name) : (t["name:en"] || t.name)) || t["name:ar"] || L("Mosque"),
  address: [t["addr:street"] || t.street, t["addr:suburb"] || t["addr:city"] || t.district || t.city].filter(Boolean).join(", "),
  lat: la, lon: lo, d: haversine(c.lat, c.lon, la, lo) * 1000 });
function dedupe(items) { const seen = new Set(); return items.filter(m => { const k = m.lat.toFixed(4) + m.lon.toFixed(4); if (seen.has(k)) return false; seen.add(k); return true; }); }
function overpassMosques(c) {
  const ql = `[out:json][timeout:8];(node["amenity"="place_of_worship"]["religion"="muslim"](around:3000,${r2(c.lat)},${r2(c.lon)});way["amenity"="place_of_worship"]["religion"="muslim"](around:3000,${r2(c.lat)},${r2(c.lon)}););out center tags 60;`;
  const hosts = ["https://overpass-api.de", "https://lz4.overpass-api.de", "https://z.overpass-api.de", "https://overpass.private.coffee", "https://maps.mail.ru/osm/tools/overpass"];
  return hosts.map(h => getJSON(h + "/api/interpreter?data=" + encodeURIComponent(ql), 9000).then(j =>
    dedupe((j.elements || []).map(e => { const la = e.lat ?? e.center?.lat, lo = e.lon ?? e.center?.lon; return la == null ? null : mosqueItem(c, la, lo, e.tags || {}); }).filter(Boolean))));
}
function photonMosques(c) {
  const dLat = 0.04, dLon = 0.04 / Math.cos(c.lat * Math.PI / 180);   // about 4.5 km each way
  // rounded like the other look-ups, so the exact position never leaves the phone
  const la = +r2(c.lat), lo = +r2(c.lon);
  const bbox = [lo - dLon, la - dLat, lo + dLon, la + dLat].map(v => v.toFixed(2)).join(",");
  const one = q => getJSON(`https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&bbox=${bbox}&limit=50&osm_tag=amenity:place_of_worship`, 8000)
    .then(j => (j.features || []).map(f => mosqueItem(c, f.geometry.coordinates[1], f.geometry.coordinates[0], f.properties || {})));
  // both words, merged: some mosques are only named in one language
  return [Promise.allSettled([one("مسجد"), one("mosque")]).then(r => dedupe(r.flatMap(x => x.status === "fulfilled" ? x.value : [])).filter(m => m.d < 5000))];
}
async function loadMosques(force) {
  const c = S.place, key = c.lat.toFixed(2) + "," + c.lon.toFixed(2);
  if (!force && mosqueState.key === key) return;
  mosqueState = { loading: true, list: mosqueState.key === key ? mosqueState.list : [], failed: false, key };
  try { const cached = JSON.parse(localStorage.getItem("rafeeq_m_" + key) || "null"); if (cached && !mosqueState.list.length) mosqueState.list = cached; } catch (e) {}
  if (S.tab === 1) render();
  if (!net.online) { mosqueState.loading = false; if (S.tab === 1) render(); return; }
  // Ask several OpenStreetMap servers at once and take the first good answer; each gets at most 9 s.
  // If every Overpass server is down or busy, fall back to Photon search, so the list never hangs.
  const list = await firstOf(overpassMosques(c), 9000) || await firstOf(photonMosques(c), 8000);
  if (list) {
    list.sort((a, b) => a.d - b.d); mosqueState.list = list.slice(0, 40);
    try { localStorage.setItem("rafeeq_m_" + key, JSON.stringify(mosqueState.list)); } catch (e) {}
  } else mosqueState.failed = !mosqueState.list.length;
  mosqueState.loading = false; if (S.tab === 1) render();
  pushWidget();
}

/* ----- Azkhar tab ----- */
/* "Other azkar": 23 more sections of Hisn al-Muslim, opened from one card */
const MORE_T = { ar: "أذكار أخرى", en: "More azkar", tr: "Diğer zikirler", fr: "Autres adhkar", it: "Altri adhkar", de: "Weitere Adhkar", nl: "Meer adhkar", es: "Más adhkar", ur: "مزید اذکار", ta: "மேலும் திக்ர்கள்", ru: "Другие азкары" };
const moreT = () => MORE_T[S.lang] || MORE_T.en;
const gTitle = g => ar() ? g.ar : ((g.t && g.t[S.lang]) || g.en);
const isMore = () => typeof azkarCat === "string";
// a person in sujood on a prayer rug (no emoji shows a Muslim praying)
const MICON = { rug: '<svg class="msvg rug" viewBox="0 0 64 64" fill="none" stroke-linejoin="round"><path d="M16 58V20Q16 6 32 4Q48 6 48 20V58Z" fill="#B24A62" stroke="#E4BB68" stroke-width="2.4"/><path d="M22 52V24Q22 14 32 12Q42 14 42 24V52Z" stroke="#E4BB68" stroke-width="2.2"/><path d="M27 52V30Q27 25 32 22Q37 25 37 30V52Z" fill="#E4BB68" fill-opacity=".85"/><path d="M16 58H48" stroke="#E4BB68" stroke-width="3"/><path d="M19 62v-4M24 62v-4M29 62v-4M35 62v-4M40 62v-4M45 62v-4" stroke="#E4BB68" stroke-width="1.6" stroke-linecap="round"/></svg>', sujood: '<svg class="msvg" viewBox="0 0 64 64" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="50" width="58" height="5" rx="2" fill="currentColor" fill-opacity=".45" stroke="none"/><circle cx="13" cy="44.5" r="5" fill="currentColor" stroke="none"/><path d="M19 41 Q27 25 40 27 L45 46 L58 48" stroke-width="8"/><path d="M21 42 L25 49" stroke-width="5"/></svg>' };
const mIcon = ic => (ic.startsWith("svg:") ? MICON[ic.slice(4)] || "" : ic);
function viewMoreGrid() {
  const cards = MORE.map((g, i) => `<button class="acat sm" data-act="mcat" data-i="${i}"><span class="aci">${azIcon(g.id) || mIcon(g.icon)}</span><span class="act">${esc(gTitle(g))}</span>${ar() ? "" : `<span class="ar act2">${g.ar}</span>`}${progBadge(g.items)}</button>`).join("");
  return `<div class="ahead"><button class="iconbtn" data-act="back">${rtl() ? I.right : I.left}</button><div class="atitle">${moreT()}</div></div><div class="agrid">${cards}</div>
  <div class="foot">${ar() ? "الأذكار: حصن المسلم" : L("Quran: Tanzil · Adhkar: Hisn al-Muslim")}</div>`;
}
function viewAzkhar() {
  syncAzkarResets();
  if (azkarCat === "more") return viewMoreGrid();
  if (isMore()) { const g = MORE[+azkarCat.slice(2)]; return azkarList(gTitle(g), ar() ? "" : g.ar, g.items); }
  if (azkarCat != null) return viewAzkharDetail();
  const cards = CATS.map((c, i) => `<button class="acat" data-act="cat" data-i="${i}"><span class="aci ${i === 2 ? "" : ""}">${[azIcon("morning"), azIcon("evening"), I.dua, azIcon("sleep"), azIcon("travel")][i]}</span><span class="act">${catTitle(i)}</span>${ar() ? "" : `<span class="ar act2">${CAT_TITLES.ar[i]}</span>`}${progBadge(DATA.azkar[c])}</button>`).join("")
    + `<button class="acat" data-act="mcat" data-i="-1"><span class="aci">${azIcon("more")}</span><span class="act">${moreT()}</span>${ar() ? "" : `<span class="ar act2">${MORE_T.ar}</span>`}<small>${MORE.length}</small></button>`;
  return `${title("Azkhar", "الأذكار")}<div class="agrid">${cards}</div><div class="foot">${ar() ? "القرآن: تنزيل · الأذكار: حصن المسلم" : L("Quran: Tanzil · Adhkar: Hisn al-Muslim")}</div>`;
}
function transOf(d) { if (ar()) return ""; return d.tr ? (d.tr[S.lang] || d.tr.en || "") : ""; }   // Arabic app language: Arabic only (same as iPhone)
function viewAzkharDetail() { const i = azkarCat; return azkarList(catTitle(i), ar() ? "" : CAT_TITLES.ar[i], DATA.azkar[CATS[i]]); }
function azkarList(head, headAr, items) {
  const hint = { ar: "اضغط على البطاقة للعدّ. النصوص مضمّنة وتعمل بدون إنترنت.", tr: "Saymak için karta dokunun. Metinler çevrimdışı çalışır.", fr: "Touchez une carte pour compter. Les textes fonctionnent hors ligne.", it: "Tocca una scheda per contare. I testi funzionano offline.", de: "Karte antippen zum Zählen. Die Texte funktionieren offline.", nl: "Tik op een kaart om te tellen. De teksten werken offline.", es: "Toca una tarjeta para contar. Los textos funcionan sin conexión." }[S.lang] || (X[S.lang] && X[S.lang].hint) || "Tap a card to count. Texts work offline.";
  const done = { ar: "تم", tr: "Tamam", fr: "Terminé", it: "Fatto", de: "Fertig", nl: "Klaar", es: "Hecho" }[S.lang] || (X[S.lang] && X[S.lang].done) || "Done";
  return `<div class="ahead"><button class="iconbtn" data-act="back">${rtl() ? I.right : I.left}</button><div class="atitle">${esc(head)}</div>${headAr ? `<div class="atitle ar acc">${esc(headAr)}</div>` : ""}<button class="resetall" data-act="resetAll" aria-label="${azT("resetAll")}">↺</button></div>
  ${items.map(d => {
    const n = azkarCounts[d.id] || 0, fin = n >= d.n;
    return `${d.h ? `<div class="ahsub" dir="${ar() || S.lang === "ur" ? "rtl" : "ltr"}">${esc(ar() ? d.h : ((d.ht && d.ht[S.lang]) || d.h))}</div>` : ""}<div class="card dcard ${fin ? "fin" : ""}" data-act="count" data-id="${d.id}" data-n="${d.n}">
      <div class="dshort"><span class="dchk">✓</span><span>${esc(shortAr(d.ar))}</span><b>${d.n > 1 ? "×" + d.n : ""}</b></div>
      <div class="darb">${esc(d.ar)}</div>
      ${d.note ? `<div class="dnote">${esc(d.note)}</div>` : ""}
      ${d.kahf ? `<button class="kahfb" data-act="openKahf">📖 ${ar() ? "اقرأ سورة الكهف" : esc(L("Read Surat al-Kahf"))}</button>` : ""}
      ${transOf(d) ? `<hr><div class="dtr">${esc(transOf(d))}</div>` : ""}
      <div class="dref">${esc(d.ref)}</div>
      <div class="dfoot"><button class="dminus ${n ? "" : "hide"}" data-act="dec" data-id="${d.id}" aria-label="-1">−1</button><div class="dbar"><i style="width:${Math.min(100, n / d.n * 100)}%"></i></div><div class="dcnt" id="c-${d.id}">${fin ? done : `${n} / ${d.n}`}</div></div></div>`;
  }).join("")}<div class="foot">${hint} ${azT("hint2")}</div><div class="foot">${ar() ? "القرآن: تنزيل · الأذكار: حصن المسلم" : L("Quran: Tanzil · Adhkar: Hisn al-Muslim")}</div>`;
}

/* ----- Settings tab ----- */
const sel = (k, opts, cur) => `<select data-k="${k}">${opts.map(([v, t]) => `<option value="${v}" ${String(v) === String(cur) ? "selected" : ""}>${esc(t)}</option>`).join("")}</select>`;
const tog = (k, on) => `<label class="sw"><input type="checkbox" data-k="${k}" ${on ? "checked" : ""}><i></i></label>`;
const srow = (label, ctl, sub) => `<div class="srow"><div class="sl">${label}${sub ? `<small>${sub}</small>` : ""}</div>${ctl}</div>`;
const sect = (t, body, foot) => `<div class="shead">${L(t)}</div><div class="card sbox">${body}</div>${foot ? `<div class="sfoot">${foot}</div>` : ""}`;
/* Settings: same sections and order as the iPhone app */
const SI = (d, fill) => `<svg viewBox="0 0 24 24" fill="${fill ? "currentColor" : "none"}" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const SIC = {
  eye: SI('<path d="M2 12s3.6-6.5 10-6.5S22 12 22 12s-3.6 6.5-10 6.5S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
  palette: I.palette, compass: SI('<circle cx="12" cy="12" r="9"/><path d="M15.5 8.5l-2 5-5 2 2-5z"/>'),
  size: SI('<path d="M3 7V5h10v2M8 5v14M6 19h4M14 12v-1h7v1M17.5 11v8M16 19h3"/>'), book: I.book,
  bold: SI('<path d="M7 5h6a3.5 3.5 0 0 1 0 7H7zM7 12h7a3.5 3.5 0 0 1 0 7H7z"/>'),
  globe: SI('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>'),
  font: SI('<path d="M4 19l6.5-14h1L18 19M6.8 13.5h8.4"/>'), loc: PI.gps, pin: I.pin, clock: I.clock,
  fn: SI('<path d="M15 4h-1.5A2.5 2.5 0 0 0 11 6.5v11A2.5 2.5 0 0 1 8.5 20H7M8 11h7"/>'),
  pm: SI('<circle cx="12" cy="12" r="9"/><path d="M12 6.5v6M9 9.5h6M9 16h6"/>'), sun: PI.dhuhr, bell: I.bell,
  speaker: SI('<path d="M4 9.5h3.5L12 6v12l-4.5-3.5H4z"/><path d="M15.5 9.5a3.5 3.5 0 0 1 0 5M18 7a7 7 0 0 1 0 10"/>'),
  batt: SI('<rect x="3" y="7" width="16" height="10" rx="2"/><path d="M21 10.5v3M8 12.5l2-3v2h2l-2 3v-2H8z"/>'),
  remind: PI.alarm, sunrise: PI.sunrise, sunset: SI('<path d="M19.5 14.5A7.5 7.5 0 1 1 9.5 4.5a6 6 0 0 0 10 10z"/>'),
  dua: SI('<circle cx="12" cy="4.5" r="1.8"/><circle cx="17" cy="7" r="1.8"/><circle cx="18.2" cy="12.5" r="1.8"/><circle cx="7" cy="7" r="1.8"/><circle cx="5.8" cy="12.5" r="1.8"/><circle cx="12" cy="16" r="1.8"/><path d="M12 17.8V21"/>'), temp: SI('<path d="M10 14.2V5a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z"/><path d="M12 11v5"/>'),
  info: SI('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.6v.2"/>'),
  cam: SI('<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>'),
  lock: SI('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 7.5-2"/>'),
  play: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="currentColor"/><path d="M10 8l6 4-6 4z" fill="var(--card)"/></svg>',
};
const irow = (ic, label, ctl, sub, act) => `<${act ? `button class="srow irow lbtn" ${act}` : 'div class="srow irow"'}><span class="sic">${SIC[ic] || ""}</span><div class="sl">${label}${sub ? `<small>${sub}</small>` : ""}</div>${ctl || ""}</${act ? "button" : "div"}>`;
const seg = (k, opts, cur) => `<div class="seg">${opts.map(([v, t]) => `<button class="${String(v) === String(cur) ? "on" : ""}" data-act="seg" data-k="${k}" data-v="${v}">${esc(t)}</button>`).join("")}</div>`;
// A row whose explanation shows only when the row's title is tapped.
const hint = (row, text) => row.replace('<div class="sl">', '<div class="sl" data-act="hint">') + `<div class="shint">${esc(text)}</div>`;
const sgroup = (t, body) => `<div class="shead">${L(t)}</div><div class="card sbox">${body}</div>`;
const gmt = tz => { try { const p = new Intl.DateTimeFormat("en-GB", { timeZone: tz, timeZoneName: "shortOffset" }).formatToParts(new Date()).find(x => x.type === "timeZoneName"); return p ? p.value.replace("GMT", "GMT") : ""; } catch (e) { return ""; } };
let setSub = null;
let adhanAudio = null;
// Adhan sounds (files in res/raw, copied to www for the preview). The Fajr adhan ("as-salatu khayrun min an-nawm") is offered for Fajr only.
const SOUNDS = [["adhan", "adhan.wav", ""], ...[1, 2, 3].map(i => [`azan${i}`, `azan${i}.ogg`, "s"]), ...[4, 5, 6, 7, 8, 9, 10, 11].map(i => [`azan${i}`, `azan${i}.ogg`, "c"])];
const FAJR_SOUNDS = [["fajr1", "fajr1.ogg", "s"]];
const sndFile = k => ([...SOUNDS, ...FAJR_SOUNDS].find(x => x[0] === k) || SOUNDS[0])[1];
function sndLabel([k, , len]) {
  const n = k === "adhan" ? 0 : +k.replace(/\D/g, ""), arN = String(n).replace(/\d/g, d => "٠١٢٣٤٥٦٧٨٩"[d]);
  if (k === "adhan") return ar() ? "الافتراضي" : L("Default");
  const fj = k.startsWith("fajr");
  if (ar()) return `${fj ? "أذان الفجر" : "أذان " + arN} – ${len === "s" ? "قصير" : "كامل"}`;
  return `${fj ? L("Fajr azan") : "Azan " + n} – ${L(len === "s" ? "short" : "complete")}`;
}
let playing = null;
function playAdhan(k) {
  try {
    if (adhanAudio) { adhanAudio.pause(); const same = playing === k; adhanAudio = null; playing = null; if (same) return; }
    adhanAudio = new Audio(sndFile(k)); playing = k; adhanAudio.onended = () => { adhanAudio = null; playing = null; }; adhanAudio.play();
  } catch (e) {}
}
function viewOffsets() {
  const rows = PRAYERS.map(k => { const v = offs()[k] || 0; return `<div class="srow"><div class="sl"><b>${pName(k)}</b></div><span class="offv ${v ? "set" : ""}">${v > 0 ? "+" : ""}${v} ${L("min")}</span><div class="step"><button data-act="adj" data-k="${k}" data-d="-1">−</button><button data-act="adj" data-k="${k}" data-d="1">+</button></div></div>`; }).join("");
  return `<div class="ahead"><button class="iconbtn" data-act="setBack">${rtl() ? I.right : I.left}</button><div class="atitle">${L("Adjust times")}</div></div>
  <div class="sfoot" style="margin:0 6px 10px">${L("Add or subtract minutes to match your local mosque or official timetable.")}</div>
  <div class="card sbox">${rows}</div><button class="card resetb" data-act="resetOff">${ar() ? "إعادة الكل إلى 0" : L("Reset all to 0")}</button>`;
}
/* Settings: a short main page of big sections; each opens its own small page (easier for older users). */
const SECT = [
  ["loc", "pin", () => ar() ? "الموقع ومواقيت الصلاة" : L("Location & prayer times")],
  ["adhan", "bell", () => ar() ? "الأذان والتنبيهات" : L("Adhan & alerts")],
  ["fajr", "remind", () => ar() ? "منبّه الفجر" : L("Fajr alarm")],
  ["azkar", "dua", () => ar() ? "الأذكار" : L("Azkhar")],
  ["look", "palette", () => ar() ? "المظهر واللغة" : L("Appearance & language")],
  ["about", "info", () => ar() ? "حول التطبيق" : L("About")],
];
function setSummary(k) {
  const p = S.place, mt = METHODS.find(m => m.id === S.method);
  const on = v => v ? (ar() ? "مفعّل" : L("On")) : (ar() ? "متوقف" : L("Off"));
  if (k === "loc") return `${p.name} · ${mt ? L(mt.name) : ""}`;
  if (k === "adhan") return `${on(S.notif)} · ${sndLabel(SOUNDS.find(x => x[0] === S.adhanSound) || SOUNDS[0])}`;
  if (k === "fajr") { const st = (S.fajrStreak || {}).cur || 0, isOn = S.fajrOn && S.rugRef; return isOn ? `${on(true)} · ${ar() ? `${arN(st)} يومًا متتاليًا` : F("{0} days in a row", st)}` : on(false); }
  if (k === "azkar") { const n = ["azMorning", "azEvening", "azPrayer", "azFriday"].filter(x => S[x]).length; return ar() ? `${arN(n)} تذكيرات مفعّلة · حجم الخط` : F("{0} reminders on · text size", n); }
  if (k === "look") return `${(LANGS.find(x => x[0] === S.lang) || ["", ""])[1]} · ${(PALETTES.find(x => x.id === S.palette) || { title: "" }).title ? L((PALETTES.find(x => x.id === S.palette)).title) : ""}`;
  if (k === "about") return `${ar() ? "رحّال" : "Rihal"} 1.0${__BUILD__ ? ` (${__BUILD__})` : ""}`;
  return "";
}
const subHead = t => `<div class="ahead"><button class="iconbtn" data-act="setBack">${rtl() ? I.right : I.left}</button><div class="atitle">${esc(t)}</div></div>`;
const slab = t => `<div class="slab">${esc(t)}</div>`;
function viewSettings() {
  if (setSub === "offsets") return viewOffsets();
  const chevB = `<span class="schev">${rtl() ? I.left : I.right}</span>`;
  if (!setSub) {
    const big = ([k, ic, t]) => `<button class="bigrow" data-act="setGo" data-s="${k}"><span class="bic">${SIC[ic] || ""}</span><span class="bt"><b>${esc(t())}</b><small>${esc(setSummary(k))}</small></span>${chevB}</button>`;
    const sec = SECT.filter(x => x[0] !== "fajr" || NativeWidget || !nativeOK());
    return `${title("Settings", "الإعدادات")}
    <div class="card sbox">${sec.filter(x => ["loc", "adhan", "fajr"].includes(x[0])).map(big).join("")}</div>
    <div class="card sbox sgap">${sec.filter(x => ["azkar", "look"].includes(x[0])).map(big).join("")}</div>
    <div class="card sbox sgap">${big(SECT[5])}</div>`;
  }
  const head = subHead(SECT.find(x => x[0] === setSub)[2]());
  const tsizes = [["1", L("Standard")], ["1.15", L("Large")], ["1.3", L("Larger")], ["1.5", L("Largest")]];
  const asizes = [["1", L("Standard")], ["1.2", L("Large")], ["1.4", L("Larger")], ["1.7", L("Largest")]];
  const p = S.place, chk = `<span class="sck">${I.check}</span>`, chev = chevB;
  const shortM = n => ({ "Muslim World League": "MWL", "Egyptian General Authority": "Egypt", "Karachi (UIS)": "Karachi", "ISNA (North America)": "ISNA", "Umm al-Qura (Makkah)": "Umm al-Qura" }[n] || n);
  const remind = [[0, L("Off")], ...[5, 10, 15, 20, 30].map(m => [m, m + " " + L("min")])];
  const box = x => `<div class="card sbox">${x}</div>`;
  if (setSub === "loc") return head + box(irow("loc", L("Current location"), S.gps ? chk : "", esc(S.gps ? p.name : L("Use my location")), 'data-act="gps"')
    + irow("pin", L("Choose a city"), (S.gps ? "" : chk) + chev, S.gps ? "" : esc(p.name), 'data-act="picker"')
    + hint(irow("clock", L("Local time"), `<b class="muted tnum">${tf(p.tz).format(new Date())} · ${gmt(p.tz)}</b>`), ar() ? `الصلاة والقبلة والمساجد والطقس كلها تعتمد على هذا الموقع. المنطقة الزمنية: ${p.tz}` : F("Prayer times, Qibla, mosques and weather all use this location. Time zone: {0}", p.tz)))
    + slab(ar() ? "الحساب" : L("Calculation"))
    + box(irow("fn", L("Method"), sel("method", METHODS.map(m => [m.id, shortM(L(m.name))]), S.method))
    + irow("sun", L("Hanafi Asr"), tog("hanafi", S.hanafi))
    + irow("pm", L("Adjust times"), `<span class="muted">${L("minutes")}</span>` + chev, "", 'data-act="setOffsets"'));
  if (setSub === "adhan") return head + box(hint(irow("bell", L("Adhan alerts"), tog("notif", S.notif)), ar() ? "بجانب كل صلاة: زر المنبّه يشغّل الأذان، وزر الجرس يرسل تنبيهًا بدون أذان." : L("Next to each prayer: the alarm button plays the adhan, the bell sends a notification without it."))
    + (S.notif && alertsDenied ? `<div class="snote">${ar() ? "التنبيهات مغلقة لهذا التطبيق في إعدادات الجهاز. فعّلها من إعدادات الهاتف ← التطبيقات ← رحّال ← الإشعارات." : esc(F("Notifications are off for this app in device settings. ")) + esc(L("Turn them on in phone Settings → Apps → Rihal → Notifications."))}</div>` : "")
    + irow("speaker", ar() ? "الأذان" : L("Adhan"), `<div class="sndrow">${sel("adhanSound", SOUNDS.map(x => [x[0], sndLabel(x)]), S.adhanSound)}<button class="playb" data-act="playAdhan" data-k="adhanSound" aria-label="${ar() ? "استماع" : "Play"}">${SIC.play}</button></div>`)
    + irow("sunrise", ar() ? "أذان الفجر" : L("Fajr adhan"), `<div class="sndrow">${sel("fajrSound", [SOUNDS[0], ...FAJR_SOUNDS, ...SOUNDS.slice(1)].map(x => [x[0], sndLabel(x)]), S.fajrSound)}<button class="playb" data-act="playAdhan" data-k="fajrSound" aria-label="${ar() ? "استماع" : "Play"}">${SIC.play}</button></div>`)
    + irow("remind", L("Remind me before"), sel("remind", remind, S.remind))
    + irow("sunrise", L("Sunrise alert"), tog("sunriseAlert", S.sunriseAlert)))
    + (NativeWidget ? slab(ar() ? "المزيد" : L("More")) + box(hint(irow("batt", ar() ? "التنبيهات في وقتها" : L("Alerts on time"), battOK && exactOK ? `<span class="okb">✓ ${ar() ? "مفعّل" : L("On")}</span>` : `<button class="fixb" data-act="fixAlerts">${ar() ? "السماح" : L("Allow")}</button>`),
        ar() ? "يمنع الهاتف من تأخير الأذان والتذكيرات لتوفير البطارية، فتصل في الدقيقة نفسها." : L("Stops the phone from holding back the adhan and reminders to save battery, so they arrive on the minute."))) : "");
  if (setSub === "fajr") {
    const st = streakOf(S);
    return head + box(hint(irow("remind", FJ.title(), tog("fajrOn", S.fajrOn && !!S.rugRef)), FJ.hint())
      + irow("cam", FJ.rug(), `<button class="fixb" data-act="rugShot">${S.rugRef ? FJ.retake() : FJ.take()}</button>`)
      + irow("lock", FJ.emer(), sel("fajrEmer", [[5, FJ.after(5)], [10, FJ.after(10)], [15, FJ.after(15)], [0, FJ.none()]], S.fajrEmer)))
      + `<div class="card sbox fjsum"><div><b>${arN(st.cur)}</b><span>${ar() ? "أيام متتالية" : L("Days in a row")}</span></div><div><b>${arN(st.best)}</b><span>${ar() ? "أفضل سلسلة" : L("Best streak")}</span></div></div>`;
  }
  if (setSub === "azkar") return head + box(hint(irow("sunrise", ar() ? "تذكير أذكار الصباح" : L("Morning azkar reminder"), tog("azMorning", S.azMorning)), ar() ? "بعد الفجر بـ١٥ دقيقة، ثم كل ساعتين حتى الظهر. يتوقف عند إكمال أذكار الصباح." : L("15 min after Fajr, then every 2 hours until Dhuhr. Stops once you finish the morning azkar."))
    + hint(irow("sunset", ar() ? "تذكير أذكار المساء" : L("Evening azkar reminder"), tog("azEvening", S.azEvening)), ar() ? "بعد العصر بـ١٥ دقيقة، ثم كل ساعتين حتى العشاء. يتوقف عند إكمال أذكار المساء." : L("15 min after Asr, then every 2 hours until Isha. Stops once you finish the evening azkar."))
    + hint(irow("dua", ar() ? "تذكير أذكار بعد الصلاة" : L("After-prayer azkar reminder"), tog("azPrayer", S.azPrayer)), ar() ? "بعد كل صلاة بـ١٥ دقيقة، إذا لم تكمل أذكار بعد الصلاة." : L("15 min after each prayer, if you haven't finished the after-prayer azkar."))
    + hint(irow("book", ar() ? "تذكير يوم الجمعة" : L("Friday reminder"), tog("azFriday", S.azFriday)), ar() ? "سورة الكهف قبل الظهر بساعتين ونصف، وساعة الإجابة قبل المغرب بساعة." : L("Surat al-Kahf 2½ hours before Dhuhr, and the hour of dua 1 hour before Maghrib.")))
    + slab(ar() ? "القراءة" : L("Reading"))
    + box(irow("size", L("Azkhar text size"), sel("azkarSize", asizes, S.azkarSize))
    + (NativeWidget ? hint(irow("speaker", ar() ? "العدّ بأزرار الصوت" : L("Count with volume buttons"), tog("volKeys", S.volKeys)), ar() ? "عند فتح قائمة الأذكار، زرّا الصوت يعدّان الذكر التالي." : L("While an azkar list is open, the volume buttons count the next dhikr.")) : ""));
  if (setSub === "look") {
    const sw = PALETTES.map(q => `<button class="sw2 ${q.id === S.palette ? "sel" : ""}" data-act="pal" data-id="${q.id}" aria-label="${q.title}"><i style="background:${H(q.c.accent[0])}">${q.id === S.palette ? I.check : ""}</i></button>`).join("");
    return head + box(`<div class="fsample" dir="rtl">لَا إِلَٰهَ إِلَّا اللَّهُ مُحَمَّدٌ رَسُولُ اللَّهِ</div>` + irow("globe", L("Application language"), sel("lang", LANGS, S.lang))
      + irow("size", L("Text size"), sel("textSize", tsizes, S.textSize)) + irow("bold", L("Bold text"), tog("bold", S.bold)))
      + slab(ar() ? "الألوان" : L("Colours")) + `<div class="card sbox spad"><div class="swatches2">${sw}</div>${seg("appearance", [["auto", L("Auto")], ["light", L("Light")], ["dark", L("Dark")]], S.appearance)}<div style="height:10px"></div></div>`
      + slab(ar() ? "المزيد" : L("More"))
      + box(irow("font", L("App font"), sel("fontID", FONTS.map(([v, t]) => [v, v === "system" ? (S.lang === "en" ? "System" : L("System default")) : t]), S.fontID))
      + irow("eye", L("Show current prayer (Now)"), tog("showNow", S.showNow !== false))
      + irow("compass", L("Compass style"), sel("compass", [["classic", L("Classic")], ["rings", L("Rings")]], S.compass === "rings" ? "rings" : "classic"))
      + irow("temp", L("Temperature"), sel("temp", [["c", "°C"], ["f", "°F"]], S.temp)));
  }
  return head + `<div class="card sbox">${irow("info", ar() ? "الإصدار" : L("Version"), `<span class="muted">Rihal 1.0${__BUILD__ ? ` (${__BUILD__})` : ""}</span>`)}<a class="srow irow" href="${PRIVACY_URL}" target="_blank" rel="noopener"><span class="sic"></span><div class="sl">${PRIVACY_LABEL[S.lang] || "Privacy policy"}</div><span aria-hidden="true">↗</span></a></div>
  <div class="sfoot" style="margin:12px 8px">${L("Qibla and prayer times are calculated on this device. Your approximate location is sent only when you look up mosques, weather or cities.")}</div>`;
}

/* ----- place picker sheet ----- */
function viewPicker() {
  const q = pickerQuery.trim().toLowerCase();
  let list = CITIES;
  if (q) list = CITIES.filter(c => (c.name + " " + c.country + " " + c.iso + " " + iso3(c.iso)).toLowerCase().includes(q));
  list = list.slice(0, 60);
  const remote = pickerRemote.map(c => `<button class="crow" data-act="pick" data-r="${pickerRemote.indexOf(c)}"><span><b>${esc(c.name)}</b><small>${esc(c.country)}</small></span>${badge(c.iso)}</button>`).join("");
  const rows = list.map(c => `<button class="crow" data-act="pick" data-i="${CITIES.indexOf(c)}"><span><b>${esc(c.name)}</b><small>${esc(c.country)}</small></span>${badge(c.iso)}</button>`).join("");
  return `<div class="sheetbg" data-act="closeSheet"></div><div class="sheet"><div class="grab"></div>
   <div class="row between"><b class="shtitle">${pickerOpen === "m" ? L("Find mosques in") : L("City")}</b><button class="iconbtn sm" data-act="closeSheet">✕</button></div>
   <input id="cq" class="search" placeholder="${esc(L("Search city, country or code"))}" value="${esc(pickerQuery)}" autocomplete="off">
   <div class="clist">
    ${pickerOpen === "m" ? `<button class="crow gps" data-act="pickme"><span><b>${L("Near me")}</b><small>${esc(S.place.name)}</small></span>${I.pin}</button>` : `<button class="crow gps" data-act="gps"><span><b>${L("Detect location automatically")}</b><small>${gpsState === "finding" ? L("Finding your location…") : gpsState === "denied" ? (ar() ? "الموقع مغلق لهذا التطبيق. فعّله من الإعدادات أو اختر مدينة." : "Location is off for this app. Turn it on in settings, or choose a city.") : ""}</small></span>${I.pin}</button>`}
    ${rows}${remote ? `<div class="sect">${L("More results")}</div>${remote}` : ""}
    ${!rows && !remote ? `<div class="center muted pad">${net.online ? L("No city found. Try another spelling.") : L("No match offline. Connect to the internet to search more cities.")}</div>` : ""}
   </div></div>`;
}
let searchTimer = null;
function remoteSearch(q) {
  clearTimeout(searchTimer); pickerRemote = [];
  if (q.trim().length < 3 || !net.online) return;
  searchTimer = setTimeout(async () => {
    try {
      const r = await fetch(`https://geocoding-api.open-meteo.com/v1/search?count=8&language=${ar() ? "ar" : S.lang === "ru" ? "ru" : "en"}&name=${encodeURIComponent(q.trim())}`);
      const j = await r.json();
      pickerRemote = (j.results || []).map(x => ({ name: x.name, country: [x.admin1, x.country].filter(Boolean).join(", "), lat: x.latitude, lon: x.longitude, tz: x.timezone, iso: (x.country_code || "--").toUpperCase() }));
      if (pickerOpen) { const keep = $("#cq")?.selectionStart; renderSheet(); const el = $("#cq"); if (el) { el.focus(); el.setSelectionRange(keep, keep); } }
    } catch (e) {}
  }, 450);
}
function renderSheet() { const el = $("#sheet"); el.innerHTML = dirTarget ? dirSheet() : pickerOpen ? viewPicker() : ""; }
function choose(c) {
  S.place = { ...c, tz: safeTz(c.tz) }; S.gps = false; save(); pushLocation(); weather = null; pickerOpen = null; renderSheet(); loadWeather(); scheduleAlerts(); render(); if (S.tab === 1 || NativeWidget) loadMosques();
}

/* ---------- render & events ---------- */
const TABS = [["Prayer Times", "clock"], ["Mosques", "mosque"], ["Azkhar", "dua"], ["Mushaf", "book"], ["Settings", "gear"]];
function render() {
  applyTheme();
  const v = $("#view"), st = v.scrollTop;
  document.body.classList.toggle("inmush", S.tab === 3);
  v.innerHTML = [viewHome, viewMosques, viewAzkhar, () => mushafHTML(ar()), viewSettings][S.tab]();
  $("#tabs").innerHTML = TABS.map((t, i) => `<button class="tab ${i === S.tab ? "sel" : ""}" data-act="tab" data-i="${i}">${I[t[1]]}<span>${L(t[0])}</span></button>`).join("");
  if (S.tab === 0) afterHome(); else { dialEls = null; stopCompass(); }
  if (S.tab === 3) mushafAfter(ar(), L);
  if (S.tab === 1) loadMosques();
  if (S.tab === 4) fitSettings();
  v.scrollTop = st;
  if (tasbihId && S.tab !== 2) closeTasbih();
  syncVolKeys();
  pushWidget();
}
/* ----- Back (Android button or swipe): previous page inside the app; never on the Mushaf, where swipes turn pages ----- */
let tabHist = [], lastBack = 0;
function goBack() {
  if (fajrUI === "alarm") return;                                  // the Fajr alarm can't be swiped away
  if (fajrUI) { ACT[fajrUI === "done" ? "fjClose" : "fjCamClose"](); return; }
  const cb = $("#cbox.on"); if (cb) { cb.classList.remove("on"); return; }
  if (tasbihId) { closeTasbih(); return; }
  if (pickerOpen || dirTarget) { pickerOpen = null; dirTarget = null; renderSheet(); return; }
  if (S.tab === 3) return;
  if (setSub) { ACT.setBack(); return; }
  if (azkarCat != null) { ACT.back(); return; }
  if (tabHist.length) { S.tab = tabHist.pop(); setSub = null; save(); render(); $("#view").scrollTop = 0; return; }
  if (S.tab !== 0) { S.tab = 0; save(); render(); return; }
  if (Date.now() - lastBack < 2000) { try { NativeWidget.exitApp(); } catch (e) {} return; }
  lastBack = Date.now(); toast(ar() ? "اسحب مرة أخرى للخروج" : L("Swipe back again to exit"));
}
function toast(t) {
  let el = $("#toast"); if (!el) { el = document.createElement("div"); el.id = "toast"; document.body.appendChild(el); }
  el.textContent = t; el.classList.add("on"); clearTimeout(el._t); el._t = setTimeout(() => el.classList.remove("on"), 1800);
}
// Settings: keep every title and every chosen value on one line by shrinking the text a little when needed.
function fitSettings() {
  const fit = (el, w, max, min) => { let f = max; el.style.fontSize = f + "rem"; while (w() && f > min) { f -= 0.03; el.style.fontSize = f + "rem"; } };
  document.querySelectorAll("#view .irow .sl").forEach(e => fit(e, () => e.scrollWidth > e.clientWidth + 1, 0.95, 0.7));
  const c = document.createElement("canvas").getContext("2d");
  document.querySelectorAll("#view .irow select").forEach(s => {
    const t = s.options[s.selectedIndex] ? s.options[s.selectedIndex].text : "";
    fit(s, () => { c.font = getComputedStyle(s).font; return c.measureText(t).width + 26 > s.clientWidth; }, 0.88, 0.7);
  });
}
try { document.fonts.addEventListener("loadingdone", () => fitRing()); } catch (e) {}
// Keep the countdown text inside the circle whatever the font and text size: each line must fit the circle's width
// at its height; shrink the text step by step until it does.
function fitRing() {
  const box = $(".hrg"), t = box && $(".hrt", box); if (!t) return;
  const R = box.clientWidth / 2 * 0.80;              // inside of the ring, with a small margin
  let k = 1; t.style.setProperty("--rk", k);
  const bad = () => {
    const c = box.getBoundingClientRect(), cy = c.top + c.height / 2;
    const kids = [...t.children], h = kids.reduce((v, e) => v + e.getBoundingClientRect().height, 0);
    if (h > R * 2) return true;
    for (const ln of t.children) {
      const b = ln.getBoundingClientRect(), dy = Math.max(Math.abs(b.top - cy), Math.abs(b.bottom - cy));
      if (dy >= R) return true;
      if (ln.scrollWidth > 2 * Math.sqrt(R * R - dy * dy)) return true;
    }
    return false;
  };
  while (bad() && k > 0.5) { k -= 0.04; t.style.setProperty("--rk", k); }
}
function vibr(p = 12) { try { navigator.vibrate && navigator.vibrate(p); } catch (e) {} }

/* ----- azkar counting: finish and move on, big counter, undo, long-press reset, volume keys ----- */
const AZT = {
  resetAll: { ar: "إعادة الكل؟", en: "Reset all?" }, tapAny: { ar: "اضغط في أي مكان للعدّ", en: "Tap anywhere to count" },
  hint2: { ar: "اضغط مطوّلًا على البطاقة لتصفيرها.", en: "Long-press a card to reset it." },
};
const azT = k => (ar() ? AZT[k].ar : L(AZT[k].en));
const doneWord = () => ({ ar: "تم", tr: "Tamam", fr: "Terminé", it: "Fatto", de: "Fertig", nl: "Klaar", es: "Hecho" }[S.lang] || (X[S.lang] && X[S.lang].done) || "Done");
const shortAr = t => { const w = t.replace(/[﴿﴾()\[\]]/g, "").replace(/\s+/g, " ").trim().split(" "); return w.slice(0, 6).join(" ") + (w.length > 6 ? " …" : ""); };
let lpFired = false, tasbihId = null, volOn = null;
function addCount(id, step) {
  const d = findDhikr(id); if (!d) return;
  const c = azkarCounts[id] || 0, v = Math.max(0, Math.min(d.n, c + step)); if (v === c) return;
  if (v) azkarCounts[id] = v; else delete azkarCounts[id];
  saveCounts();
  const fin = v >= d.n;
  vibr(fin && step > 0 ? [40, 60, 140] : 12);
  const el = document.querySelector(`.dcard[data-id="${id}"]`);
  if (el) {
    $("#c-" + id).textContent = fin ? doneWord() : `${v} / ${d.n}`;
    el.querySelector(".dbar i").style.width = Math.min(100, v / d.n * 100) + "%";
    el.querySelector(".dminus").classList.toggle("hide", !v);
    el.classList.remove("open"); el.classList.toggle("fin", fin);
    if (fin && step > 0) setTimeout(() => nextCard(el), 380);
  }
  if (fin !== (c >= d.n)) scheduleAlerts();                     // finished or reopened: refresh today's reminders
}
function nextCard(el) {
  let n = el.nextElementSibling;
  while (n && !(n.classList.contains("dcard") && !n.classList.contains("fin"))) n = n.nextElementSibling;
  if (n) n.scrollIntoView({ behavior: "smooth", block: "center" });
}
function openTasbih(id) {
  tasbihId = id;
  let o = $("#tasbih"); if (!o) { o = document.createElement("div"); o.id = "tasbih"; document.body.appendChild(o); }
  o.innerHTML = `<div class="tbtop"><button class="iconbtn" data-act="tclose" aria-label="close">✕</button></div>
    <div class="tbtext" dir="rtl"></div><div class="tbring"><svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="52" fill="none" stroke="var(--tile)" stroke-width="9"/><circle class="tbarc" cx="60" cy="60" r="52" fill="none" stroke="var(--accent)" stroke-width="9" stroke-linecap="round" transform="rotate(-90 60 60)"/></svg><div class="tbnum"></div></div>
    <div class="tbhint">${azT("tapAny")}</div><div class="tbbot"><button class="dminus" data-act="tdec">−1</button></div>`;
  o.classList.add("on"); paintTasbih();
  o.onclick = e => { if (e.target.closest("button")) return; addCount(tasbihId, 1); paintTasbih(); };
}
function paintTasbih() {
  const o = $("#tasbih"), d = tasbihId && findDhikr(tasbihId); if (!o || !d) return;
  const v = azkarCounts[d.id] || 0, C = 2 * Math.PI * 52;
  o.querySelector(".tbtext").textContent = d.ar;
  o.querySelector(".tbnum").innerHTML = `${v}<small>/ ${d.n}</small>`;
  const a = o.querySelector(".tbarc"); a.setAttribute("stroke-dasharray", `${C * v / d.n} ${C}`);
  if (v >= d.n) setTimeout(closeTasbih, 650);
}
function closeTasbih() {
  const o = $("#tasbih"); if (o) o.classList.remove("on");
  const id = tasbihId; tasbihId = null;
  const el = id && document.querySelector(`.dcard[data-id="${id}"]`);
  if (el && el.classList.contains("fin")) setTimeout(() => nextCard(el), 200);
}
// Long-press a card (one dhikr) or a category tile (all its azkar) to reset it, after a yes/no question.
function confirmBox(text, onYes, o2 = {}) {
  let o = $("#cbox"); if (!o) { o = document.createElement("div"); o.id = "cbox"; document.body.appendChild(o); }
  o.innerHTML = `<div class="cbg"></div><div class="cpanel">${o2.title ? `<h3>${esc(o2.title)}</h3>` : ""}<p>${esc(text)}</p><div class="cbtns"><button class="cno">${esc(o2.no || (ar() ? "لا" : L("No")))}</button><button class="cyes ${o2.good ? "good" : ""}">${esc(o2.yes || (ar() ? "نعم" : L("Yes")))}</button></div></div>`;
  o.classList.add("on");
  const close = () => o.classList.remove("on");
  o.querySelector(".cno").onclick = close; o.querySelector(".cbg").onclick = close;
  o.querySelector(".cyes").onclick = () => { close(); onYes(); };
}
const resetQ = name => ar() ? `هل تريد تصفير عدّاد «${name}»؟` : F("Do you want to reset the counter for “{0}”?", name);
function tileItems(el) {
  if (el.dataset.act === "cat") { const i = +el.dataset.i; return { name: catTitle(i), items: DATA.azkar[CATS[i]] }; }
  const i = +el.dataset.i; if (i < 0) return null; const g = MORE[i]; return { name: gTitle(g), items: g.items };
}
(() => {
  let t = null, x = 0, y = 0;
  const stop = () => { clearTimeout(t); t = null; };
  document.addEventListener("pointerdown", e => {
    const card = e.target.closest(".dcard"), tile = !card && e.target.closest(".acat");
    if ((!card && !tile) || (card && e.target.closest("button"))) return;
    x = e.clientX; y = e.clientY; stop();
    t = setTimeout(() => {
      if (card) {
        const id = card.dataset.id, d = findDhikr(id); if (!azkarCounts[id] || !d) return;
        lpFired = true; addCount(id, -(azkarCounts[id] || 0)); vibr(50);      // one dhikr: reset straight away
      } else {
        const g = tileItems(tile); if (!g || !g.items.some(d => azkarCounts[d.id])) return;
        lpFired = true; vibr(30);
        confirmBox(resetQ(g.name), () => { g.items.forEach(d => delete azkarCounts[d.id]); saveCounts(); vibr(50); render(); scheduleAlerts(); });
      }
    }, 650);
  });
  document.addEventListener("pointermove", e => { if (t && (Math.abs(e.clientX - x) > 10 || Math.abs(e.clientY - y) > 10)) stop(); });
  ["pointerup", "pointercancel"].forEach(n => document.addEventListener(n, stop));
  document.addEventListener("contextmenu", e => { if (e.target.closest(".dcard, .acat")) e.preventDefault(); });
})();
// Android volume keys count the first unfinished dhikr (or the open big counter).
function volCount() {
  if (tasbihId) { addCount(tasbihId, 1); paintTasbih(); return; }
  const el = [...document.querySelectorAll(".dcard")].find(c => !c.classList.contains("fin")); if (!el) return;
  addCount(el.dataset.id, 1); el.scrollIntoView({ behavior: "smooth", block: "center" });
}
function syncVolKeys() {
  const on = !!(NativeWidget && S.volKeys && S.tab === 2 && listItems());
  if (on === volOn) return; volOn = on;
  try { NativeWidget.setVolumeKeys({ on }); } catch (e) {}
}
const ACT = {
  tab(el) { const t = +el.dataset.i; if (t !== S.tab) { tabHist.push(S.tab); if (tabHist.length > 20) tabHist.shift(); } setSub = null; S.tab = t; azkarCat = null; save(); render(); $("#view").scrollTop = 0; },
  picker() { pickerOpen = "p"; pickerQuery = ""; pickerRemote = []; renderSheet(); },
  mpicker() { pickerOpen = "p"; pickerQuery = ""; pickerRemote = []; renderSheet(); },
  closeSheet() { pickerOpen = null; dirTarget = null; renderSheet(); },
  directions(el) { dirTarget = { lat: el.dataset.lat, lon: el.dataset.lon, name: el.dataset.name }; renderSheet(); },
  pick(el) { choose(el.dataset.r != null ? pickerRemote[+el.dataset.r] : CITIES[+el.dataset.i]); },
  pickme() { mosqueAround = null; mosqueState.key = ""; pickerOpen = null; renderSheet(); loadMosques(true); },
  gps() { useGPS().then(() => { if (gpsState === "ok") { pickerOpen = null; renderSheet(); } else renderSheet(); }); renderSheet(); },
  refreshGPS() { useGPS(); },
  mrefresh() { loadMosques(true); },
  compass() { startCompass().then(render); },
  day(el) { prayDay += +el.dataset.d; render(); },
  mute(el) { const k = el.dataset.k; S.muted[k] = !S.muted[k]; save(); scheduleAlerts(); render(); },
  cat(el) { if (lpFired) { lpFired = false; return; } azkarCat = +el.dataset.i; render(); $("#view").scrollTop = 0; },
  mcat(el) { if (lpFired) { lpFired = false; return; } const i = +el.dataset.i; azkarCat = i < 0 ? "more" : "m:" + i; render(); $("#view").scrollTop = 0; },
  back() { azkarCat = isMore() && azkarCat !== "more" ? "more" : null; render(); $("#view").scrollTop = 0; },
  count(el) {
    if (lpFired) { lpFired = false; return; }
    const id = el.dataset.id, n = +el.dataset.n, c = azkarCounts[id] || 0;
    if (c >= n) { el.classList.toggle("open"); return; }      // finished card: tap shows or folds the text
    if (n >= 33) { openTasbih(id); return; }                  // long counts: full-screen counter
    addCount(id, 1);
  },
  dec(el) { addCount(el.dataset.id, -1); },
  hint(el) { const h = el.closest(".srow").nextElementSibling; if (h && h.classList.contains("shint")) h.classList.toggle("on"); },
  openKahf() { S.tab = 3; save(); mushafSetPage(293); render(); },
  resetAll(el) {
    if (!el.classList.contains("sure")) { el.classList.add("sure"); el.textContent = azT("resetAll"); clearTimeout(el._t); el._t = setTimeout(() => { el.classList.remove("sure"); el.textContent = "↺"; }, 3000); return; }
    (listItems() || []).forEach(d => delete azkarCounts[d.id]); saveCounts(); vibr(30); render(); scheduleAlerts();
  },
  tclose() { closeTasbih(); },
  tdec() { if (tasbihId) { addCount(tasbihId, -1); paintTasbih(); } },
  alarm(el) { const k = el.dataset.k; S.alarm = { ...(S.alarm || {}), [k]: !alarmOn(k) }; save(); scheduleAlerts(); render(); },
  mclose() { S.tab = 0; save(); render(); },
  mindex() { mushafIndexToggle(ar(), L); },
  mgo(el) { mushafSetPage(+el.dataset.p); render(); },
  mseg(el) { mushafBy(el.dataset.v === "1"); },
  pal(el) { S.palette = el.dataset.id; save(); render(); },
  seg(el) { S[el.dataset.k] = el.dataset.v; save(); render(); },
  setOffsets() { setSub = "offsets"; render(); $("#view").scrollTop = 0; },
  setBack() { setSub = setSub === "offsets" ? "loc" : null; render(); $("#view").scrollTop = 0; },
  setGo(el) { setSub = el.dataset.s; render(); $("#view").scrollTop = 0; },
  resetOff() { S.off = {}; save(); scheduleAlerts(); render(); },
  playAdhan(el) { playAdhan(S[el.dataset.k]); },
  askExact() { askExact(); },
  async fixAlerts() { if (!battOK) explainBattery(); else await askExact(); },
  adj(el) { const k = el.dataset.k; S.off = { ...offs(), [k]: Math.max(-60, Math.min(60, (offs()[k] || 0) + +el.dataset.d)) }; save(); scheduleAlerts(); render(); },
};
document.addEventListener("click", e => { const el = e.target.closest("[data-act]"); if (el && ACT[el.dataset.act]) { if (el.tagName === "A") return; ACT[el.dataset.act](el); } });
document.addEventListener("change", e => {
  const el = e.target.closest("[data-k]"); if (!el || el.dataset.act) return;
  const k = el.dataset.k; let v = el.type === "checkbox" ? el.checked : el.value;
  if (k === "remind") v = +v;
  if (k === "notif") { setAlerts(v); return; }
  if (["azMorning", "azEvening", "azPrayer", "azFriday"].includes(k)) { S[k] = v; save(); if (v) azkarPermission(); else scheduleAlerts(); render(); return; }
  S[k] = v; save();
  if (["lang", "method", "hanafi", "remind", "sunriseAlert", "adhanSound", "fajrSound"].includes(k)) scheduleAlerts();
  if (k === "lang") { mosqueState.key = ""; weather = weather; }
  render();
});
document.addEventListener("input", e => { if (e.target.id === "cq") { pickerQuery = e.target.value; const pos = e.target.selectionStart; renderSheet(); const el = $("#cq"); el.focus(); el.setSelectionRange(pos, pos); remoteSearch(pickerQuery); } });
// swipe right inside an azkar page goes back to the cards
let sx = null, sy = null;
document.addEventListener("touchstart", e => { sx = e.touches[0].clientX; sy = e.touches[0].clientY; }, { passive: true });
document.addEventListener("touchend", e => {
  if (sx == null || S.tab !== 2 || azkarCat == null) return;
  const dx = e.changedTouches[0].clientX - sx, dy = e.changedTouches[0].clientY - sy; sx = null;
  if (Math.abs(dx) > 80 && Math.abs(dx) > Math.abs(dy) * 1.5 && (rtl() ? dx < 0 : dx > 0)) ACT.back();
}, { passive: true });

/* ---------- boot ---------- */
function welcome() {
  const el = $("#sheet");
  el.innerHTML = `<div class="sheetbg"></div><div class="sheet welcome"><img src="icon.png" class="wlogo" alt=""><h1>Rihal</h1>
   <p>${ar() ? "القبلة ومواقيت الصلاة والأذكار في أي مكان — يعمل دون إنترنت." : F("Qibla, prayer times and Azkhar, anywhere. Works offline.")}</p>
   <ul><li>${ar() ? "بلا حساب ولا تتبع ولا إعلانات" : F("No account, no tracking, no ads")}</li><li>${ar() ? "الحسابات تتم على هاتفك" : F("Calculated on your phone")}</li></ul>
   <button class="btn big" id="wgps">${L("Allow location while using the app")}</button><button class="btn ghost big" id="wcity">${L("Choose a city instead")}</button></div>`;
  $("#wgps").onclick = () => { S.welcomed = true; save(); el.innerHTML = ""; useGPS(); setTimeout(ensureAlertPermission, 4000); };
  $("#wcity").onclick = () => { S.welcomed = true; save(); el.innerHTML = ""; pickerOpen = "p"; pickerQuery = ""; renderSheet(); setTimeout(ensureAlertPermission, 1500); };
}
function boot() {
  render(); loadWeather();
  setInterval(() => { if (S.tab === 0 && !document.hidden) tickHome(); }, 1000);
  setInterval(() => { if (S.tab === 0 && !document.hidden) { const p = S.place; $("#sunlayer") && ($("#sunlayer").innerHTML = sunLayerSVG(sunInfo(p.lat, p.lon, new Date()))); } }, 60000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) { checkBattery().then(() => { scheduleAlerts(); render(); }); } });
  if (!S.welcomed) welcome(); else { setTimeout(ensureAlertPermission, 1500); if (S.gps) useGPS(true); else if (NativeWidget) loadMosques(); }
  if (NativeWidget) {
    // a tap on the widget opens Prayer Times (0) or Mosques (1)
    const go = t => { if (t == null || t < 0) return; S.tab = t; azkarCat = null; save(); render(); };
    NativeWidget.addListener("openTab", o => go(o.tab));
    NativeWidget.getLaunchTab().then(o => go(o.tab)).catch(() => {});
    NativeWidget.addListener("volumeKey", () => volCount());
    NativeWidget.addListener("backButton", () => goBack());
  }
  if (nativeOK()) {
    // a tap on an azkar reminder opens that azkar list
    LocalNotifications.addListener("localNotificationActionPerformed", a => {
      const c = a && a.notification && a.notification.extra && a.notification.extra.azcat;
      if (c == null) return; setSub = null; S.tab = 2; azkarCat = typeof c === "string" && c.startsWith("m:") ? c : +c; save(); render(); $("#view").scrollTop = 0;
    });
  }
  if ("serviceWorker" in navigator && !nativeOK() && location.protocol.startsWith("http")) navigator.serviceWorker.register("sw.js").catch(() => {});
}

/* ---------- Fajr rug alarm (screens; the ringing itself is native) ---------- */
const FJ = {
  title: () => ar() ? "منبّه الفجر" : L("Fajr alarm"),
  hint: () => ar() ? "عند الفجر يرنّ الأذان ولا يتوقف حتى تصوّر سجادة صلاتك، ويعدّ الأيام التي تصلي فيها الفجر متتالية." : L("At Fajr the adhan rings and won't stop until you photograph your prayer rug. It also counts the days you pray Fajr in a row."),
  rug: () => ar() ? "تصوير السجادة" : L("Prayer rug photo"),
  take: () => ar() ? "التقاط صورة" : L("Take photo"),
  retake: () => ar() ? "إعادة التصوير" : L("Retake"),
  emer: () => ar() ? "الإيقاف الطارئ" : L("Emergency stop"),
  after: n => ar() ? `بعد ${String(n).replace(/\d/g, d => "٠١٢٣٤٥٦٧٨٩"[d])} دقائق` : F("After {0} min", n),
  none: () => ar() ? "بدون" : L("None"),
};
let fajrUI = null;          // null | "alarm" | "camera" | "setup" | "done"
let fajrSince = 0, fajrCam = null, fajrMsg = "", fajrResult = null, fajrHoldT = null;
const fajrTz = () => S.place.tz;
function nextFajrs(n = 7) {
  const p = S.place, now = Date.now();
  return prayerEvents(now, p.lat, p.lon, p.tz, method(), S.hanafi, offs(), 10).all.filter(e => e.prayer === "fajr" && e.date > now).slice(0, n).map(e => e.date);
}
function sunriseAfter(t) {
  const p = S.place, e = prayerEvents(t, p.lat, p.lon, p.tz, method(), S.hanafi, offs(), 1).all.find(x => x.prayer === "sunrise" && x.date > t);
  return e ? e.date : t + 90 * 60000;
}
/** Sends the next Fajr times to Android, which sets them as real alarms. */
function pushFajr() {
  if (!NativeWidget) return;
  const sound = S.fajrSound === "adhan" ? "adhan" : S.fajrSound;
  NativeWidget.setFajrAlarm({ on: !!(S.fajrOn && S.rugRef), times: nextFajrs().join(","), sound, max: 60 }).catch(() => {});
}
/** On start and on return: is it ringing? Which past alarms got no rug photo (streak back to 0)? */
async function fajrSync() {
  if (!NativeWidget) return;
  let st; try { st = await NativeWidget.fajrState(); } catch (e) { return; }
  const now = Date.now(), days = streakOf(S).days;
  for (const s of String(st.rang || "").split(",")) {
    const t = +s; if (!t) continue;
    const k = dayKey(t, fajrTz());
    if (!days[k] && !(st.ringing && now - t < 3 * 3600000) && now > sunriseAfter(t)) markDay(S, k, "miss");
  }
  save();
  if (st.ringing) { fajrSince = st.since || now; if (!fajrUI || fajrUI === "done") showFajr("alarm"); }
  else if (fajrUI === "alarm" || fajrUI === "camera") hideFajr();
}
function fajrStop() { if (NativeWidget) NativeWidget.stopFajrAlarm().catch(() => {}); }
const todayFajrKey = () => dayKey(fajrSince || Date.now(), fajrTz());

function showFajr(mode) {
  fajrUI = mode; fajrMsg = "";
  let o = $("#fajr"); if (!o) { o = document.createElement("div"); o.id = "fajr"; document.body.appendChild(o); }
  o.className = "on " + mode;
  if (mode === "camera" || mode === "setup") startCam(); else stopCam();
  paintFajr();
}
function hideFajr() { fajrUI = null; stopCam(); clearInterval(fajrHoldT); const o = $("#fajr"); if (o) o.className = ""; }
const FI = {
  moon: SI('<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>'),
  spk: SI('<path d="M4 9.5h3l5-4v13l-5-4H4z"/><path d="M16 9a4 4 0 0 1 0 6M18.5 6.5a7.5 7.5 0 0 1 0 11"/>'),
  cam: SI('<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>'),
  lock: SI('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>'),
  open: SI('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 7.5-2"/>'),
  flash: SI('<path d="M13 3 5 14h6l-1 7 8-11h-6z"/>'),
  chk: SI('<path d="M5 12.5 10 17 19 7.5"/>'),
  x: SI('<path d="M6 6l12 12M18 6 6 18"/>'),
};
const arN = n => ar() ? String(n).replace(/\d/g, d => "٠١٢٣٤٥٦٧٨٩"[d]) : String(n);
function paintFajr() {
  const o = $("#fajr"); if (!o || !fajrUI) return;
  const p = S.place;
  if (fajrUI === "alarm") {
    const t = fmtT(fajrSince || Date.now()), emer = +S.fajrEmer;
    o.innerHTML = `<div class="fjal">
      <div class="fjmoon">${FI.moon}</div><div class="fjname">${ar() ? "صلاة الفجر" : esc(pName("fajr"))}</div><div class="fjtime">${t}</div>
      <div class="fjq">${ar() ? "الصلاة خير من النوم" : L("Prayer is better than sleep")}</div>
      <div class="fjring"><div>${FI.spk}</div></div>
      <button class="fjcam" data-act="fjCam">${FI.cam}<span>${ar() ? "صوّر السجادة" : L("Photograph the rug")}</span></button>
      <button class="fjskip" data-act="fjSkip">${ar() ? "لا أصلي اليوم" : L("Not praying today")}</button>
      ${emer ? `<button class="fjemer" id="fjemer"><span class="fjhold"></span><span class="fjic"></span><span class="fjtx"></span></button>` : ""}
    </div>`;
    tickEmer(); clearInterval(fajrHoldT); fajrHoldT = setInterval(tickEmer, 1000);
  } else if (fajrUI === "camera" || fajrUI === "setup") {
    const setup = fajrUI === "setup";
    o.innerHTML = `<div class="fjcm"><video id="fjv" playsinline muted autoplay poster="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"></video><div class="fjframe"></div>
      <button class="fjflash" data-act="fjTorch" aria-label="flash">${FI.flash}</button>
      <button class="fjclose" data-act="fjCamClose" aria-label="close">${FI.x}</button>
      <div class="fjtop">${setup ? (ar() ? "صوّر سجادة صلاتك داخل الإطار" : L("Photograph your prayer rug inside the frame")) : (ar() ? "ضع السجادة داخل الإطار" : L("Fit the rug inside the frame"))}
        <small>${setup ? (ar() ? "ستُقارن بها كل صباح، وتبقى على هاتفك فقط" : L("It's compared every morning and stays on your phone")) : (ar() ? "الفلاش يعمل تلقائيًا في الظلام" : L("The flash turns on by itself in the dark"))}</small></div>
      <div class="fjbad ${fajrMsg ? "on" : ""}">${esc(fajrMsg)}</div>
      <button class="fjshut" data-act="fjShoot" aria-label="photo"><i></i></button></div>`;
    const v = $("#fjv"); if (v) { v.onplaying = () => v.classList.add("live"); if (fajrCam) { v.srcObject = fajrCam; v.play().catch(() => {}); } }
  } else if (fajrUI === "done") {
    const st = streakOf(S), r = fajrResult || {};
    const keys = []; const d0 = new Date(fajrSince || Date.now());
    for (let i = 6; i >= 0; i--) keys.push(dayKey(+d0 - i * 86400000, p.tz));
    const dots = keys.map((k, i) => { const v = st.days[k]; return `<i class="${v === "ok" ? "ok" : v === "skip" ? "sk" : v === "miss" ? "ms" : "no"}${i === 6 ? " t" : ""}">${v === "ok" ? "✓" : v === "skip" ? "–" : ""}</i>`; }).join("");
    o.innerHTML = `<div class="fjok">
      <div class="fjchk">${FI.chk}</div><div class="fjtq">${ar() ? "تقبّل الله" : L("May Allah accept it")}</div>
      <div class="fjst">${r.late ? `<div class="fjnew">${ar() ? "بعد الشروق، بدأت سلسلة جديدة" : L("After sunrise: a new streak begins")}</div>` : ""}
        <div class="fjn">${arN(st.cur)}</div><div class="fjd">${ar() ? "يومًا متتاليًا في صلاة الفجر" : L("days in a row praying Fajr")}</div>
        <div class="fjdots">${dots}</div>
        <div class="fjbest">${ar() ? `أفضل سلسلة: ${arN(st.best)} يومًا` : F("Best streak: {0} days", st.best)}</div></div>
      <div class="fjdoa">«مَن صلَّى الصُّبحَ فهو في ذمَّةِ اللهِ»</div>
      <button class="fjgo" data-act="fjAzkar">${ar() ? "أذكار الصباح" : L("Morning azkar")}</button>
      <button class="fjskip dark" data-act="fjClose">${ar() ? "إغلاق" : L("Close")}</button>
    </div>`;
  }
}
const fmtT = t => new Intl.DateTimeFormat("en-GB", { timeZone: S.place.tz, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(t));
/** Emergency stop: locked for the chosen minutes, then press and hold 5 seconds. */
function tickEmer() {
  const b = $("#fjemer"); if (!b) return;
  const left = (fajrSince || Date.now()) + (+S.fajrEmer) * 60000 - Date.now();
  const tx = b.querySelector(".fjtx"), ic = b.querySelector(".fjic");
  if (left > 0) {
    const m = Math.floor(left / 60000), s = Math.floor(left / 1000) % 60, mm = `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
    b.classList.remove("open"); ic.innerHTML = FI.lock;
    tx.textContent = ar() ? `إيقاف طارئ · بعد ${mm}` : F("Emergency stop in {0}", mm);
  } else if (!b.classList.contains("open")) {
    b.classList.add("open"); ic.innerHTML = FI.open;
    tx.textContent = ar() ? "إيقاف طارئ · اضغط مطوّلًا ٥ ثوانٍ" : L("Emergency stop · hold 5 seconds");
    let ht = null;
    const up = () => { clearTimeout(ht); b.classList.remove("holding"); };
    b.onpointerdown = e => { e.preventDefault(); b.classList.add("holding"); ht = setTimeout(() => { up(); fajrEmergency(); }, 5000); };
    b.onpointerup = b.onpointerleave = b.onpointercancel = up;
  }
}
function fajrEmergency() {
  markDay(S, todayFajrKey(), "miss"); save(); fajrStop(); hideFajr();
  toast(ar() ? "لم تُصوَّر السجادة اليوم" : L("No rug photo today"));
}
async function startCam() {
  stopCam();
  try {
    fajrCam = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 } }, audio: false });
    const v = $("#fjv"); if (v) { v.onplaying = () => v.classList.add("live"); v.srcObject = fajrCam; await v.play().catch(() => {}); }
    // in the dark, turn the flash on by itself
    setTimeout(() => { const v2 = $("#fjv"); if (!v2 || !fajrCam) return; try { if (rugFeatures(v2).lum < 45) setTorch(true); } catch (e) {} }, 1200);
  } catch (e) {
    fajrMsg = ar() ? "تعذّر فتح الكاميرا. اسمح لرحّال باستخدام الكاميرا من إعدادات الهاتف." : L("Can't open the camera. Allow Rihal to use the camera in phone settings.");
    paintFajr();
  }
}
let torchOn = false;
function setTorch(on) {
  const tr = fajrCam && fajrCam.getVideoTracks()[0]; if (!tr) return;
  torchOn = on; tr.applyConstraints({ advanced: [{ torch: on }] }).catch(() => {});
  const f = $(".fjflash"); if (f) f.classList.toggle("on", on);
}
function stopCam() { if (fajrCam) { fajrCam.getTracks().forEach(t => t.stop()); fajrCam = null; } torchOn = false; }
function fajrShoot() {
  const v = $("#fjv"); if (!v || !v.videoWidth) return;
  const f = rugFeatures(v);
  if (f.lum < 18 || !f.ok) { fajrMsg = ar() ? "المكان مظلم، شغّل الفلاش" : L("Too dark. Turn on the flash"); vibr(80); paintFajr(); return; }
  if (fajrUI === "setup") {
    S.rugRef = f; S.fajrOn = true; save(); hideFajr(); pushFajr(); render();
    toast(ar() ? "تم حفظ صورة السجادة" : L("Rug photo saved")); return;
  }
  const score = rugScore(S.rugRef, f);
  if (score < RUG_MATCH) { fajrMsg = ar() ? "هذه ليست سجادتك، حاول مرة أخرى" : L("That's not your rug. Try again"); vibr([60, 60, 60]); paintFajr(); return; }
  const t = fajrSince || Date.now(), late = Date.now() > sunriseAfter(t - 60000);
  markDay(S, dayKey(t, fajrTz()), late ? "miss" : "ok"); save();
  fajrResult = { late }; fajrStop(); vibr(120); showFajr("done");
}
/** Turning the alarm on: rug photo first, then the Android permissions it needs. */
async function fajrEnable(on) {
  if (!on) { S.fajrOn = false; save(); pushFajr(); render(); return; }
  if (NativeWidget) {
    try {
      const p = await NativeWidget.fajrPermissions();
      if (!p.fullScreen || !p.exact) {
        confirmBox(ar() ? "اسمح لرحّال بعرض المنبّه فوق شاشة القفل وفي وقته تمامًا، ثم ارجع وفعّل المنبّه." : L("Allow Rihal to show the alarm over the lock screen and exactly on time, then come back and turn the alarm on."),
          () => NativeWidget.openFajrPermission({ which: p.fullScreen ? "exact" : "fullScreen" }),
          { title: ar() ? "لكي يظهر المنبّه فوق شاشة القفل" : L("So the alarm can show over the lock screen"), yes: ar() ? "متابعة" : L("Continue"), no: ar() ? "لاحقًا" : L("Later"), good: true });
        render(); return;
      }
    } catch (e) {}
  }
  if (!S.rugRef) { showFajr("setup"); render(); return; }
  S.fajrOn = true; save(); pushFajr(); render();
}
Object.assign(ACT, {
  fjCam() { showFajr("camera"); },
  fjCamClose() { if (fajrUI === "setup") { hideFajr(); render(); } else showFajr("alarm"); },
  fjShoot() { fajrShoot(); },
  fjTorch() { setTorch(!torchOn); },
  fjSkip() {
    if (fajrUI === "done") return;
    markDay(S, todayFajrKey(), "skip"); save(); fajrStop(); hideFajr();
    toast(ar() ? "تقبّل الله منك، السلسلة محفوظة" : L("Your streak is kept"));
  },
  fjAzkar() { hideFajr(); setSub = null; S.tab = 2; azkarCat = 0; save(); render(); $("#view").scrollTop = 0; },
  fjClose() { hideFajr(); },
  rugShot() { showFajr("setup"); },
});
document.addEventListener("change", e => {
  const k = e.target && e.target.dataset && e.target.dataset.k;
  if (k === "fajrOn") { e.stopImmediatePropagation(); fajrEnable(e.target.checked); }
  if (k === "fajrEmer") { S.fajrEmer = +e.target.value; save(); }
}, true);
if (NativeWidget) {
  NativeWidget.addListener("fajrAlarm", o => { if (o && o.ringing) fajrSync(); else if (fajrUI === "alarm" || fajrUI === "camera") { hideFajr(); fajrSync(); } });
  NativeWidget.getLaunchTab().then(o => { if (o && o.fajr) fajrSync(); }).catch(() => {});
  fajrSync(); pushFajr();
  document.addEventListener("visibilitychange", () => { if (!document.hidden) fajrSync(); });
}
// Browser preview: ?fajr=alarm|camera|done shows a screen with sample data.
try {
  const q = new URLSearchParams(location.search).get("fajr");
  if (q && !nativeOK()) { fajrSince = Date.now() - 18000; S.fajrEmer = S.fajrEmer ?? 10; if (q === "done") { const st = streakOf(S); if (!st.cur) { st.cur = 13; st.best = 30; } } showFajr(q); }
} catch (e) {}
boot();
