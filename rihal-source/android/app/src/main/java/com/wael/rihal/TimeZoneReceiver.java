package com.wael.rihal;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import org.json.JSONObject;

import java.util.TimeZone;

/**
 * Android tells us when the phone's time zone changes (landing in another country), even while the app is closed.
 * We refresh the widgets and send one notification asking to open Rihal so prayer times and alerts follow the new place.
 * No location is used here.
 */
public class TimeZoneReceiver extends BroadcastReceiver {
    private static final String KEY_TZ = "last_tz";
    private static final String CHANNEL = "rihal_info";

    @Override
    public void onReceive(Context c, Intent intent) {
        if (!Intent.ACTION_TIMEZONE_CHANGED.equals(intent.getAction())) return;
        RihalWidgets.updateAll(c);

        String now = TimeZone.getDefault().getID();
        SharedPreferences p = c.getSharedPreferences(RihalWidgets.PREFS, Context.MODE_PRIVATE);
        String before = p.getString(KEY_TZ, null);
        p.edit().putString(KEY_TZ, now).apply();
        if (before == null || before.equals(now)) return;

        // Texts in the app's language, saved by the app together with the widget data.
        String title = "Rihal", body = "You are in a new time zone. Open Rihal to update your prayer times.";
        try {
            JSONObject d = new JSONObject(p.getString(RihalWidgets.KEY, "{}"));
            JSONObject m = d.optJSONObject("tzMsg");
            if (m != null) { title = m.optString("t", title); body = m.optString("b", body); }
        } catch (Exception ignored) {}

        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && nm != null && nm.getNotificationChannel(CHANNEL) == null)
            nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Rihal", NotificationManager.IMPORTANCE_DEFAULT));

        Intent open = new Intent(c, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi = PendingIntent.getActivity(c, 7301, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pi)
            .setAutoCancel(true);
        try { NotificationManagerCompat.from(c).notify(7301, b.build()); } catch (SecurityException ignored) {}
    }
}
