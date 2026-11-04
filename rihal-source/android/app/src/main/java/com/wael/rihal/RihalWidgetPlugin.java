package com.wael.rihal;

import android.app.AlarmManager;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/** Bridge between the app and the home-screen widgets: receives widget data, reports widget taps. */
@CapacitorPlugin(name = "RihalWidget")
public class RihalWidgetPlugin extends Plugin {
    private int launchTab = -1;
    /** Set while an azkar list is open and "count with volume buttons" is on. */
    static volatile boolean volumeKeys = false;
    static RihalWidgetPlugin instance;

    @Override
    public void load() {
        instance = this;
        if (getActivity() != null) launchTab = tabFrom(getActivity().getIntent());
    }

    // ---- Fajr rug alarm ----

    /** Settings from the page: on/off, the next Fajr times (ms, comma separated), the sound and the longest ringing time. */
    @PluginMethod
    public void setFajrAlarm(PluginCall call) {
        FajrAlarm.save(getContext(), Boolean.TRUE.equals(call.getBoolean("on", false)), call.getString("times", ""),
                call.getString("sound", "fajr1"), call.getInt("max", 60));
        call.resolve();
    }

    /** Is it ringing now, since when, and the Fajr times it rang (for the streak). */
    @PluginMethod
    public void fajrState(PluginCall call) {
        JSObject r = new JSObject();
        r.put("ringing", FajrAlarmService.ringing);
        r.put("since", FajrAlarmService.ringingSince);
        r.put("rang", FajrAlarm.prefs(getContext()).getString("rang", ""));
        call.resolve(r);
    }

    /** Rug photo matched, "not praying today", or the emergency stop: silence the alarm. */
    @PluginMethod
    public void stopFajrAlarm(PluginCall call) {
        Context c = getContext();
        c.stopService(new Intent(c, FajrAlarmService.class));
        if (getActivity() != null) getActivity().runOnUiThread(() -> MainActivity.alarmMode(getActivity(), false));
        call.resolve();
    }

    /** Android 14+: may the alarm screen open over the lock screen? Exact alarms allowed? */
    @PluginMethod
    public void fajrPermissions(PluginCall call) {
        Context c = getContext();
        boolean full = true;
        if (Build.VERSION.SDK_INT >= 34) {
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            full = nm == null || nm.canUseFullScreenIntent();
        }
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        JSObject r = new JSObject();
        r.put("fullScreen", full);
        r.put("exact", Build.VERSION.SDK_INT < 31 || (am != null && am.canScheduleExactAlarms()));
        call.resolve(r);
    }

    /** Opens the Android page where the user allows full-screen alarms (or exact alarms). */
    @PluginMethod
    public void openFajrPermission(PluginCall call) {
        Context c = getContext();
        String which = call.getString("which", "fullScreen");
        try {
            Intent i;
            if ("exact".equals(which) && Build.VERSION.SDK_INT >= 31)
                i = new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + c.getPackageName()));
            else if (Build.VERSION.SDK_INT >= 34)
                i = new Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:" + c.getPackageName()));
            else { call.resolve(); return; }
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(i);
        } catch (Exception ignored) {}
        call.resolve();
    }

    static void fajrRinging() {
        RihalWidgetPlugin p = instance;
        if (p == null) return;
        JSObject o = new JSObject();
        o.put("ringing", true);
        p.notifyListeners("fajrAlarm", o, true);
    }

    static void fajrStopped() {
        RihalWidgetPlugin p = instance;
        if (p == null) return;
        JSObject o = new JSObject();
        o.put("ringing", false);
        p.notifyListeners("fajrAlarm", o, false);
    }

    @PluginMethod
    public void setVolumeKeys(PluginCall call) {
        volumeKeys = Boolean.TRUE.equals(call.getBoolean("on", false));
        call.resolve();
    }

    /** Is the app free from battery optimization, and may it set exact alarms? (Alerts on time.) */
    @PluginMethod
    public void batteryStatus(PluginCall call) {
        Context c = getContext();
        PowerManager pm = (PowerManager) c.getSystemService(Context.POWER_SERVICE);
        boolean ignoring = Build.VERSION.SDK_INT < 23 || (pm != null && pm.isIgnoringBatteryOptimizations(c.getPackageName()));
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        boolean exact = Build.VERSION.SDK_INT < 31 || (am != null && am.canScheduleExactAlarms());
        JSObject r = new JSObject();
        r.put("ignoring", ignoring);
        r.put("exact", exact);
        call.resolve(r);
    }

    /** Ask Android (system Allow / Deny dialog) to stop putting Rihal's alerts to sleep. */
    @PluginMethod
    public void requestBattery(PluginCall call) {
        Context c = getContext();
        try {
            Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + c.getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(i);
        } catch (Exception e) {
            try {
                Intent i = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                c.startActivity(i);
            } catch (Exception ignored) {}
        }
        call.resolve();
    }

    /** Back gesture: hand it to the page if it is listening. Returns false when nobody listens. */
    boolean backPressed() {
        if (!hasListeners("backButton")) return false;
        notifyListeners("backButton", new JSObject());
        return true;
    }

    /** The page has nothing left to go back to: leave the app (it stays in recent apps). */
    @PluginMethod
    public void exitApp(PluginCall call) {
        call.resolve();
        if (getActivity() != null) getActivity().runOnUiThread(() -> getActivity().moveTaskToBack(true));
    }

    /** Called by MainActivity when a volume key is pressed while counting azkar. */
    void volumePressed() {
        notifyListeners("volumeKey", new JSObject());
    }

    private static int tabFrom(Intent i) {
        if (i == null) return -1;
        int t = i.getIntExtra(RihalWidgets.EXTRA_TAB, -1);
        if (t >= 0) i.removeExtra(RihalWidgets.EXTRA_TAB);
        return t;
    }

    @PluginMethod
    public void update(PluginCall call) {
        String data = call.getString("data");
        if (data != null) RihalWidgets.save(getContext(), data);
        RihalWidgets.updateAll(getContext());
        call.resolve();
    }

    @PluginMethod
    public void getLaunchTab(PluginCall call) {
        JSObject r = new JSObject();
        r.put("tab", launchTab);
        r.put("fajr", FajrAlarmService.ringing);
        launchTab = -1;
        call.resolve(r);
    }

    @Override
    protected void handleOnNewIntent(Intent intent) {
        super.handleOnNewIntent(intent);
        if (intent != null && intent.getBooleanExtra(FajrAlarm.EXTRA, false)) {
            JSObject f = new JSObject();
            f.put("ringing", FajrAlarmService.ringing);
            notifyListeners("fajrAlarm", f, true);
        }
        int t = tabFrom(intent);
        if (t >= 0) {
            JSObject o = new JSObject();
            o.put("tab", t);
            notifyListeners("openTab", o, true);
        }
    }
}
