package com.wael.rihal;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

/**
 * Fajr rug alarm: the page sends the next Fajr times; the earliest future one is set as a real alarm clock.
 * When it goes off, FajrAlarmService plays the adhan on a loop and opens the alarm screen, until the page
 * (after the rug photo matches) stops it. Times survive a reboot or an app update.
 */
final class FajrAlarm {
    static final String PREFS = "rihal_fajr";
    static final String EXTRA = "fajrAlarm";
    static final String ACTION_RING = "com.wael.rihal.FAJR_RING";

    private FajrAlarm() {}

    static SharedPreferences prefs(Context c) { return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE); }

    /** Saves the settings from the page and sets the next alarm (or cancels it when off). */
    static void save(Context c, boolean on, String times, String sound, int maxMinutes) {
        prefs(c).edit().putBoolean("on", on).putString("times", times == null ? "" : times)
                .putString("sound", sound == null ? "fajr1" : sound).putInt("max", maxMinutes).apply();
        schedule(c);
    }

    /** The earliest saved Fajr time that is still ahead (more than 5 seconds away), or 0. */
    static long next(Context c) {
        long now = System.currentTimeMillis(), best = 0;
        for (String s : prefs(c).getString("times", "").split(",")) {
            try {
                long t = Long.parseLong(s.trim());
                if (t > now + 5000 && (best == 0 || t < best)) best = t;
            } catch (NumberFormatException ignored) {}
        }
        return best;
    }

    static void schedule(Context c) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        PendingIntent ring = ringIntent(c);
        am.cancel(ring);
        if (!prefs(c).getBoolean("on", false)) return;
        long t = next(c);
        if (t == 0) return;
        prefs(c).edit().putLong("scheduled", t).apply();
        boolean exact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms();
        try {
            if (exact) {
                // An alarm clock: rings on time even in Doze, and shows the alarm icon in the status bar.
                Intent open = new Intent(c, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                PendingIntent show = PendingIntent.getActivity(c, 71, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
                am.setAlarmClock(new AlarmManager.AlarmClockInfo(t, show), ring);
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, t, ring);
            }
        } catch (SecurityException e) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, t, ring);
        }
    }

    private static PendingIntent ringIntent(Context c) {
        Intent i = new Intent(c, FajrAlarmReceiver.class).setAction(ACTION_RING);
        return PendingIntent.getBroadcast(c, 70, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    /** Remembers each time the alarm actually rang, so a day with no rug photo breaks the streak. */
    static void logRang(Context c, long fajrTime) {
        SharedPreferences p = prefs(c);
        String old = p.getString("rang", "");
        String[] parts = old.isEmpty() ? new String[0] : old.split(",");
        StringBuilder b = new StringBuilder();
        int start = Math.max(0, parts.length - 30);              // keep the last 30
        for (int i = start; i < parts.length; i++) b.append(parts[i]).append(',');
        b.append(fajrTime);
        p.edit().putString("rang", b.toString()).apply();
    }
}
