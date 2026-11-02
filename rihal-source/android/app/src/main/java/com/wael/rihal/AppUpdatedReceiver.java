package com.wael.rihal;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import com.capacitorjs.plugins.localnotifications.LocalNotificationRestoreReceiver;

/**
 * Android cancels an app's scheduled alarms when the app is updated. Right after an update (before the user opens
 * the app) we put back the adhan and azkar alerts that were already planned for the user's last city, and refresh
 * the widgets, so nothing falls back to defaults.
 */
public class AppUpdatedReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent intent) {
        if (!Intent.ACTION_MY_PACKAGE_REPLACED.equals(intent.getAction())) return;
        try { new LocalNotificationRestoreReceiver().onReceive(c, intent); } catch (Exception ignored) {}
        try { RihalWidgets.updateAll(c); } catch (Exception ignored) {}
    }
}
