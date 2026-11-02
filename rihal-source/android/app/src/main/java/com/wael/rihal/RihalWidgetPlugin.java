package com.wael.rihal;

import android.content.Intent;

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
