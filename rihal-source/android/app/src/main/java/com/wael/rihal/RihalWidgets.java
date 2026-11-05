package com.wael.rihal;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.SweepGradient;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Shared code for the two home-screen widgets (square countdown ring, rectangle prayer + nearest mosque).
 * The app writes the coming prayer times and the nearest mosque (RihalWidgetPlugin); the widgets read
 * them here, so they keep working offline and while the app is closed.
 */
final class RihalWidgets {
    static final String PREFS = "rihal_widget";
    static final String KEY = "data";
    static final String ACTION_TICK = "com.wael.rihal.WIDGET_TICK";
    static final String EXTRA_TAB = "rihal_tab";

    // navy and gold, same as the iPhone widget
    static final int GOLD_300 = 0xFFF1D9A2;
    static final int GOLD_DEEP = 0xFFC99A45;

    static final class Ev { long t; String ar, name, hm; }

    /** Widget colours: the app's chosen palette, light or dark (default: Ocean dark, the original navy and gold). */
    static final class Look {
        int bg = 0xFF12224D, line = 0xFF2B4080, accent = 0xFFE4BB68, deep = 0xFFF1D9A2, ink = 0xFFF5F0E4, muted = 0xFFA9B2CC;
        boolean dark = true;
    }

    static final class Data {
        Look look = new Look();
        String lang = "en";
        String city = "";
        final List<Ev> events = new ArrayList<>();
        String mosque;
        int meters = -1;
        boolean ar() { return "ar".equals(lang); }
    }

    private RihalWidgets() {}

    static void save(Context c, String json) {
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply();
    }

    private static int col(JSONObject o, String k, int def) {
        try { return 0xFF000000 | Integer.parseInt(o.getString(k).replace("#", ""), 16); } catch (Exception e) { return def; }
    }

    /** Background, glow, card and text colours for the chosen look. */
    private static void paint(RemoteViews v, Look l, int... muted) {
        v.setInt(R.id.w_bg, "setColorFilter", l.bg);
        v.setImageViewResource(R.id.w_glow, l.dark ? R.drawable.widget_glow_dark : R.drawable.widget_glow_light);
        v.setTextColor(R.id.w_ar, l.deep);
        v.setTextColor(R.id.w_chrono, l.ink);
        for (int id : muted) v.setTextColor(id, l.muted);
    }

    static Data load(Context c) {
        Data d = new Data();
        SharedPreferences p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String s = p.getString(KEY, null);
        if (s == null) return d;
        try {
            JSONObject o = new JSONObject(s);
            d.lang = o.optString("lang", "en");
            d.city = o.optString("city", "");
            JSONArray a = o.optJSONArray("events");
            if (a != null) {
                for (int i = 0; i < a.length(); i++) {
                    JSONObject e = a.getJSONObject(i);
                    Ev v = new Ev();
                    v.t = e.getLong("t");
                    v.ar = e.optString("ar", "");
                    v.name = e.optString("name", "");
                    v.hm = e.optString("hm", "");
                    d.events.add(v);
                }
            }
            JSONObject th = o.optJSONObject("theme");
            if (th != null) {
                String mode = th.optString("mode", "auto");
                boolean night = (c.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
                boolean dark = "dark".equals(mode) || ("auto".equals(mode) && night);
                JSONObject t = th.optJSONObject(dark ? "dark" : "light");
                if (t != null) {
                    Look l = new Look();
                    l.dark = dark;
                    l.bg = col(t, "bg", l.bg); l.line = col(t, "line", l.line); l.accent = col(t, "accent", l.accent);
                    l.deep = col(t, "deep", l.deep); l.ink = col(t, "ink", l.ink); l.muted = col(t, "muted", l.muted);
                    d.look = l;
                }
            }
            JSONObject m = o.optJSONObject("mosque");
            if (m != null) {
                d.mosque = m.optString("name", null);
                d.meters = m.optInt("d", -1);
            }
        } catch (Exception ignored) {
        }
        return d;
    }

    static void updateAll(Context c) {
        AppWidgetManager m = AppWidgetManager.getInstance(c);
        Data d = load(c);
        long now = System.currentTimeMillis();
        int[] sq = m.getAppWidgetIds(new ComponentName(c, RihalSquareWidget.class));
        int[] rc = m.getAppWidgetIds(new ComponentName(c, RihalRectWidget.class));
        for (int id : sq) m.updateAppWidget(id, fitInsideRing(c, square(c, d, now), m.getAppWidgetOptions(id), progress(d, now), d.look));
        for (int id : rc) m.updateAppWidget(id, rect(c, d, now));
        schedule(c, d, now, sq.length + rc.length > 0);
    }

    // ---- next / previous prayer ----

    private static Ev next(Data d, long now) {
        for (Ev e : d.events) if (e.t > now) return e;
        return null;
    }

    private static Ev prev(Data d, long now) {
        Ev p = null;
        for (Ev e : d.events) if (e.t <= now) p = e;
        return p;
    }

    private static float progress(Data d, long now) {
        Ev n = next(d, now), p = prev(d, now);
        if (n == null || p == null || n.t <= p.t) return 0f;
        return Math.max(0f, Math.min(1f, (now - p.t) / (float) (n.t - p.t)));
    }

    // ---- views ----

    private static PendingIntent open(Context c, int tab) {
        Intent i = new Intent(c, MainActivity.class);
        i.setAction("com.wael.rihal.OPEN_TAB_" + tab);
        i.putExtra(EXTRA_TAB, tab);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(c, 100 + tab, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static void countdown(RemoteViews v, int id, Ev n, long now, String format) {
        long base = SystemClock.elapsedRealtime() + (n.t - now);
        v.setChronometer(id, base, format, true);
        v.setChronometerCountDown(id, true);
        v.setViewVisibility(id, View.VISIBLE);
    }

    static RemoteViews square(Context c, Data d, long now) {
        RemoteViews v = new RemoteViews(c.getPackageName(), R.layout.widget_square);
        Ev n = next(d, now);
        v.setTextViewText(R.id.w_label, d.ar() ? "التالية" : "NEXT");
        if (n != null) {
            v.setTextViewText(R.id.w_ar, n.ar);
            countdown(v, R.id.w_chrono, n, now, null);
            v.setTextViewText(R.id.w_sub, n.hm); // time only, so the line stays inside the ring
        } else {
            v.setTextViewText(R.id.w_ar, "رحّال");
            v.setViewVisibility(R.id.w_chrono, View.GONE);
            v.setTextViewText(R.id.w_sub, d.ar() ? "افتح التطبيق" : "Open Rihal");
        }
        paint(v, d.look, R.id.w_label, R.id.w_sub);
        v.setOnClickPendingIntent(R.id.w_root, open(c, 0));
        return v;
    }

    /** Keep the text block inside the ring whatever size the widget is resized to. */
    static RemoteViews fitInsideRing(Context c, RemoteViews v, Bundle o, float progress, Look l) {
        int wDp = o != null ? o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) : 0;
        int hDp = o != null ? o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0) : 0;
        if (wDp <= 0 || hDp <= 0) { v.setImageViewBitmap(R.id.w_ring, ring(progress, 240, l)); return v; }
        float dp = c.getResources().getDisplayMetrics().density;
        float w = (wDp - 16) * dp, h = (hDp - 16) * dp, side = Math.min(w, h);
        int inset = Math.round(side * 0.2f);
        int px = Math.round((w - side) / 2f) + inset, py = Math.round((h - side) / 2f) + inset;
        v.setViewPadding(R.id.w_inner, px, py, px, py);
        v.setImageViewBitmap(R.id.w_ring, ring(progress, Math.round(Math.max(160, Math.min(360, side))), l)); // sharp at any size
        return v;
    }

    static RemoteViews rect(Context c, Data d, long now) {
        RemoteViews v = new RemoteViews(c.getPackageName(), R.layout.widget_rect);
        Ev n = next(d, now);
        if (n != null) {
            v.setTextViewText(R.id.w_ar, n.ar);
            v.setTextViewText(R.id.w_time, n.hm);
            countdown(v, R.id.w_chrono, n, now, n.name + " · %s");
        } else {
            v.setTextViewText(R.id.w_ar, "رحّال");
            v.setTextViewText(R.id.w_time, "--:--");
            v.setChronometer(R.id.w_chrono, SystemClock.elapsedRealtime(), d.ar() ? "افتح التطبيق" : "Open Rihal", false);
        }
        v.setTextViewText(R.id.w_mlabel, d.ar() ? "أقرب مسجد" : "NEAREST");
        if (d.mosque != null && !d.mosque.isEmpty()) {
            v.setTextViewText(R.id.w_mname, d.mosque);
            v.setTextViewText(R.id.w_mdist, d.meters >= 0 ? distance(d.meters, d.ar()) : "");
        } else {
            v.setTextViewText(R.id.w_mname, d.city.isEmpty() ? "—" : d.city);
            v.setTextViewText(R.id.w_mdist, d.ar() ? "لا يوجد مسجد قريب" : "No mosque found yet");
        }
        paint(v, d.look, R.id.w_mlabel, R.id.w_mdist);
        v.setTextColor(R.id.w_chrono, d.look.muted);
        v.setTextColor(R.id.w_time, d.look.ink);
        v.setTextColor(R.id.w_mname, d.look.ink);
        v.setInt(R.id.w_card, "setBackgroundResource", d.look.dark ? R.drawable.widget_card : R.drawable.widget_card_light);
        v.setOnClickPendingIntent(R.id.w_left, open(c, 0));
        v.setOnClickPendingIntent(R.id.w_card, open(c, 1));
        return v;
    }

    private static String distance(int meters, boolean ar) {
        int walk = Math.max(1, Math.round(meters / 80f));
        if (ar) {
            String d = meters >= 1000 ? String.format(Locale.US, "%.1f كم", meters / 1000f) : meters + " م";
            return d + " · " + walk + " د مشيًا";
        }
        String d = meters >= 1000 ? String.format(Locale.US, "%.1f km", meters / 1000f) : meters + " m";
        return d + " · " + walk + " min walk";
    }

    /** Countdown ring: faint track plus an arc in the app's colour from the top, clockwise. */
    static Bitmap ring(float progress, int size, Look l) {
        float stroke = size * 0.055f;
        Bitmap b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas cv = new Canvas(b);
        RectF r = new RectF(stroke, stroke, size - stroke, size - stroke);
        Paint track = new Paint(Paint.ANTI_ALIAS_FLAG);
        track.setStyle(Paint.Style.STROKE);
        track.setStrokeWidth(stroke);
        track.setColor(l.dark ? Color.argb(26, 255, 255, 255) : (l.line & 0x00FFFFFF) | 0xB0000000);
        cv.drawOval(r, track);
        Paint arc = new Paint(Paint.ANTI_ALIAS_FLAG);
        arc.setStyle(Paint.Style.STROKE);
        arc.setStrokeWidth(stroke);
        arc.setStrokeCap(Paint.Cap.ROUND);
        SweepGradient g = new SweepGradient(size / 2f, size / 2f, l.dark ? new int[]{l.deep, l.accent, l.deep} : new int[]{l.accent, l.deep, l.accent}, null);
        Matrix mx = new Matrix();
        mx.setRotate(-90, size / 2f, size / 2f);
        g.setLocalMatrix(mx);
        arc.setShader(g);
        cv.drawArc(r, -90, Math.max(progress, 0.005f) * 360f, false, arc);
        return b;
    }

    // ---- refresh: at the next prayer, and every 10 minutes for the ring ----

    static void schedule(Context c, Data d, long now, boolean any) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        Intent i = new Intent(c, RihalSquareWidget.class).setAction(ACTION_TICK);
        PendingIntent pi = PendingIntent.getBroadcast(c, 7, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        am.cancel(pi);
        if (!any) return;
        long at = now + 10 * 60_000L;
        Ev n = next(d, now);
        if (n != null && n.t + 1000 < at) at = n.t + 1000;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setWindow(AlarmManager.RTC, at, 60_000L, pi);
            } else {
                am.setExact(AlarmManager.RTC, at, pi);
            }
        } catch (SecurityException e) {
            am.set(AlarmManager.RTC, at, pi);
        }
    }
}
