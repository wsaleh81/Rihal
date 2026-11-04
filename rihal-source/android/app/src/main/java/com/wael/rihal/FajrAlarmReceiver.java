package com.wael.rihal;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** Fajr time: start the ringing service. After a reboot or an app update: set the next alarm again. */
public class FajrAlarmReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent intent) {
        String a = intent.getAction();
        if (FajrAlarm.ACTION_RING.equals(a)) {
            if (!FajrAlarm.prefs(c).getBoolean("on", false)) return;
            long t = FajrAlarm.prefs(c).getLong("scheduled", System.currentTimeMillis());
            FajrAlarm.logRang(c, t);
            Intent s = new Intent(c, FajrAlarmService.class).putExtra("fajrTime", t);
            try {
                if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(s); else c.startService(s);
            } catch (Exception ignored) {}
            FajrAlarm.schedule(c);                                   // tomorrow's alarm
        } else {
            FajrAlarm.schedule(c);                                   // boot, update, time change
        }
    }
}
