package com.wael.rihal;

import android.app.Activity;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.WindowManager;
import android.webkit.WebView;

import androidx.activity.EdgeToEdge;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.IntentSenderRequest;
import androidx.activity.result.contract.ActivityResultContracts;

import com.google.android.play.core.appupdate.AppUpdateManager;
import com.google.android.play.core.appupdate.AppUpdateManagerFactory;
import com.google.android.play.core.appupdate.AppUpdateOptions;
import com.google.android.play.core.install.model.AppUpdateType;
import com.google.android.play.core.install.model.UpdateAvailability;
import androidx.activity.OnBackPressedCallback;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    /** Close the app completely after it has been in the background this long. */
    private static final long IDLE_CLOSE_MS = 5 * 60 * 1000L;
    private final Handler idle = new Handler(Looper.getMainLooper());
    private final Runnable closeApp = this::finishAndRemoveTask;
    private AppUpdateManager updates;
    private ActivityResultLauncher<IntentSenderRequest> updateLauncher;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(CompassPlugin.class);
        registerPlugin(RihalWidgetPlugin.class);
        super.onCreate(savedInstanceState);
        // Draw behind the status and navigation bars on every Android version (as Android 15+ already does),
        // so the page's safe-area padding is not added on top of the system's own space (gap under the tab bar).
        // Must run after super.onCreate: Capacitor switches from the splash theme to the no-title-bar theme there;
        // enabling it earlier created the window with the splash theme (a "Rihal" title bar with the splash picture).
        EdgeToEdge.enable(this);
        // Back (button or swipe) goes to the previous page inside the app instead of closing it; the page decides.
        alarmMode(this, isAlarm(getIntent()));
        // Forced update: when Google Play has a newer version for this user, its full-screen update page opens.
        // Closing it without updating brings it straight back (the check runs again on resume).
        updates = AppUpdateManagerFactory.create(this);
        updateLauncher = registerForActivityResult(new ActivityResultContracts.StartIntentSenderForResult(), r -> {});
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (RihalWidgetPlugin.instance != null && RihalWidgetPlugin.instance.backPressed()) return;
                moveTaskToBack(true);
            }
        });
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (isAlarm(intent)) alarmMode(this, true);
    }

    private static boolean isAlarm(Intent i) {
        return i != null && i.getBooleanExtra(FajrAlarm.EXTRA, false) && FajrAlarmService.ringing;
    }

    /** Fajr alarm: show over the lock screen, turn the screen on and keep it on; undone when the alarm stops. */
    static void alarmMode(Activity a, boolean on) {
        if (Build.VERSION.SDK_INT >= 27) {
            a.setShowWhenLocked(on);
            a.setTurnScreenOn(on);
        } else {
            int f = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON;
            if (on) a.getWindow().addFlags(f); else a.getWindow().clearFlags(f);
        }
        if (on) a.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else a.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    @Override
    public void onResume() {
        super.onResume();
        checkForUpdate();
    }

    private void checkForUpdate() {
        if (updates == null || FajrAlarmService.ringing) return;     // never cover the Fajr alarm
        try {
            updates.getAppUpdateInfo().addOnSuccessListener(info -> {
                int a = info.updateAvailability();
                boolean ready = (a == UpdateAvailability.UPDATE_AVAILABLE && info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE))
                        || a == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS;
                if (!ready) return;
                try {
                    updates.startUpdateFlowForResult(info, updateLauncher, AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build());
                } catch (Exception ignored) {}
            });
        } catch (Exception ignored) {}
    }

    @Override
    public void onStart() {
        super.onStart();
        idle.removeCallbacks(closeApp);
        WebView w = webView();
        if (w != null) {
            w.resumeTimers();
            w.onResume();
        }
    }

    @Override
    public void onStop() {
        super.onStop();
        // Nothing runs while the app is not on screen: stop the page's clocks and timers.
        // Adhan alerts and widgets keep working (they are scheduled by the system, not the page).
        WebView w = webView();
        if (w != null) {
            w.onPause();
            w.pauseTimers();
        }
        idle.removeCallbacks(closeApp);
        if (!FajrAlarmService.ringing) idle.postDelayed(closeApp, IDLE_CLOSE_MS);
    }

    @Override
    public void onDestroy() {
        idle.removeCallbacks(closeApp);
        super.onDestroy();
    }

    /** While an azkar list is open, the volume keys count the next dhikr instead of changing the volume. */
    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
        int k = e.getKeyCode();
        // While the Fajr alarm rings, the volume keys cannot silence it.
        if (FajrAlarmService.ringing && (k == KeyEvent.KEYCODE_VOLUME_UP || k == KeyEvent.KEYCODE_VOLUME_DOWN)) return true;
        if (RihalWidgetPlugin.volumeKeys && RihalWidgetPlugin.instance != null
                && (k == KeyEvent.KEYCODE_VOLUME_UP || k == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (e.getAction() == KeyEvent.ACTION_DOWN && e.getRepeatCount() == 0) RihalWidgetPlugin.instance.volumePressed();
            return true;
        }
        return super.dispatchKeyEvent(e);
    }

    private WebView webView() {
        return getBridge() != null ? getBridge().getWebView() : null;
    }
}
