/* Fajr rug alarm (Android): at Fajr the adhan rings on a loop over the lock screen and stops only when a photo of the
   user's own prayer rug matches the one saved in Settings (or "not praying today", or the emergency stop after a wait).
   It also counts the days in a row the rug was photographed before sunrise. Everything stays on the phone. */

// ---------- picture comparison (on the phone, no internet) ----------
// A photo becomes a small "fingerprint": the mix of colours with brightness taken out (so lamp light or the flash
// matter less), plus the hue spread and how busy the pattern is. Two photos of the same rug give close fingerprints.
const N = 96;
export function rugFeatures(src) {
  const cv = document.createElement("canvas"); cv.width = cv.height = N;
  const g = cv.getContext("2d", { willReadFrequently: true });
  const w = src.videoWidth || src.naturalWidth || src.width, h = src.videoHeight || src.naturalHeight || src.height;
  const s = Math.min(w, h) * 0.7;                                  // the centre of the frame, where the rug is
  g.drawImage(src, (w - s) / 2, (h - s) / 2, s, s, 0, 0, N, N);
  const px = g.getImageData(0, 0, N, N).data;
  const rg = new Float32Array(64), hue = new Float32Array(12), gray = new Float32Array(N * N);
  let lum = 0, cnt = 0;
  for (let i = 0, k = 0; i < px.length; i += 4, k++) {
    const r = px[i], gg = px[i + 1], b = px[i + 2], sum = r + gg + b;
    gray[k] = sum / 3; lum += sum / 3;
    if (sum < 40 || sum > 735) continue;                           // too dark or burnt out: no colour to read
    const cr = r / sum, cg = gg / sum;
    rg[Math.min(7, cr * 16 | 0) * 8 + Math.min(7, cg * 16 | 0)] += 1; cnt++;
    const mx = Math.max(r, gg, b), mn = Math.min(r, gg, b), d = mx - mn;
    if (d > 18) {
      let H = mx === r ? ((gg - b) / d) % 6 : mx === gg ? (b - r) / d + 2 : (r - gg) / d + 4;
      hue[((H * 2 + 12) % 12) | 0] += d / mx;
    }
  }
  let edge = 0;
  for (let y = 1; y < N - 1; y++) for (let x = 1; x < N - 1; x++) {
    const k = y * N + x; edge += Math.abs(gray[k + 1] - gray[k - 1]) + Math.abs(gray[k + N] - gray[k - N]);
  }
  const norm = a => { const t = a.reduce((x, y) => x + y, 0) || 1; return Array.from(a, v => +(v / t).toFixed(4)); };
  return { rg: norm(rg), hue: norm(hue), edge: +(edge / (N * N)).toFixed(2), lum: +(lum / (N * N)).toFixed(1), ok: cnt > N * N * 0.25 };
}
const bhatt = (a, b) => a.reduce((s, v, i) => s + Math.sqrt(v * (b[i] || 0)), 0);
/** 0..1: how alike two fingerprints are. */
export function rugScore(a, b) {
  if (!a || !b) return 0;
  const c = bhatt(a.rg, b.rg), h = bhatt(a.hue, b.hue);
  const e = Math.min(a.edge, b.edge) / Math.max(a.edge, b.edge, 0.01);
  if (e < 0.35) return Math.min(0.5, 0.6 * c + 0.3 * h);          // a plain surface (sofa, wall) has none of the rug's pattern
  return 0.6 * c + 0.3 * h + 0.1 * Math.min(1, e * 1.4);
}
export const RUG_MATCH = 0.8;

// ---------- streak ----------
/** Day of a Fajr time in the place's own calendar, e.g. "2026-11-05". */
export const dayKey = (t, tz) => new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(t));
export function streakOf(S) { return S.fajrStreak || (S.fajrStreak = { cur: 0, best: 0, days: {} }); }
/** Records a day: "ok" (+1), "skip" (pause), "miss" (back to 0). */
export function markDay(S, key, v) {
  const st = streakOf(S);
  if (st.days[key] === "ok" || st.days[key] === v) return;
  st.days[key] = v;
  if (v === "ok") { st.cur += 1; st.best = Math.max(st.best, st.cur); }
  if (v === "miss") st.cur = 0;
  const keys = Object.keys(st.days).sort();                        // keep two months
  keys.slice(0, Math.max(0, keys.length - 60)).forEach(k => delete st.days[k]);
}
