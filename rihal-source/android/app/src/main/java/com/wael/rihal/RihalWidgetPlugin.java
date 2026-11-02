package com.wael.rihal;

import android.app.AlarmManager;
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
        launchTab = -1;
        call.resolve(r);
    }

    @Override
    protected void handleOnNewIntent(Intent intent) {
        super.handleOnNewIntent(intent);
        int t = tabFrom(intent);
        if (t >= 0) {
            JSObject o = new JSObject();
            o.put("tab", t);
            notifyListeners("openTab", o, true);
        }
    }
}
