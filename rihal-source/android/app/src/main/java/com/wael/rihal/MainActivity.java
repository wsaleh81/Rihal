package com.wael.rihal;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.webkit.WebView;

import androidx.activity.EdgeToEdge;
import androidx.activity.OnBackPressedCallback;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    /** Close the app completely after it has been in the background this long. */
    private static final long IDLE_CLOSE_MS = 5 * 60 * 1000L;
    private final Handler idle = new Handler(Looper.getMainLooper());
    private final Runnable closeApp = this::finishAndRemoveTask;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(CompassPlugin.class);
        registerPlugin(RihalWidgetPlugin.class);
        // Draw behind the status and navigation bars on every Android version (as Android 15+ already does),
        // so the page's safe-area padding is not added on top of the system's own space (gap under the tab bar).
        EdgeToEdge.enable(this);
        super.onCreate(savedInstanceState);
        // Back (button or swipe) goes to the previous page inside the app instead of closing it; the page decides.
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (RihalWidgetPlugin.instance != null && RihalWidgetPlugin.instance.backPressed()) return;
                moveTaskToBack(true);
            }
        });
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
        idle.postDelayed(closeApp, IDLE_CLOSE_MS);
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
