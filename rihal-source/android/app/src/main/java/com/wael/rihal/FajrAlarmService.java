package com.wael.rihal;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;

import androidx.core.app.NotificationCompat;

/**
 * Plays the Fajr adhan on a loop at alarm volume and keeps the alarm screen up, until the page stops it
 * (rug photo matched, "not praying today", or the emergency stop) or after the longest ringing time.
 */
public class FajrAlarmService extends Service {
    static volatile boolean ringing = false;
    static volatile long ringingSince = 0;
    private static final String CHANNEL = "fajr_alarm";
    private static final int NOTIF_ID = 7070;
    private MediaPlayer player;
    private PowerManager.WakeLock wake;
    private int oldVolume = -1;
    private final Handler h = new Handler(Looper.getMainLooper());
    private final Runnable timeUp = this::stopSelf;

    static Intent alarmScreen(Context c) {
        return new Intent(c, MainActivity.class).putExtra(FajrAlarm.EXTRA, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (ringing) return START_NOT_STICKY;
        ringing = true;
        ringingSince = System.currentTimeMillis();
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && nm != null && nm.getNotificationChannel(CHANNEL) == null) {
            NotificationChannel ch = new NotificationChannel(CHANNEL, "منبّه الفجر", NotificationManager.IMPORTANCE_HIGH);
            ch.setSound(null, null);                       // the service plays the adhan itself, on a loop
            ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(ch);
        }
        PendingIntent open = PendingIntent.getActivity(this, 72, alarmScreen(this),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification n = new NotificationCompat.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_icon)
                .setContentTitle("صلاة الفجر")
                .setContentText("صوّر السجادة لإيقاف المنبّه")
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setOngoing(true)
                .setContentIntent(open)
                .setFullScreenIntent(open, true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build();
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        else startForeground(NOTIF_ID, n);

        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        if (pm != null) {
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "rihal:fajr");
            wake.acquire(65 * 60 * 1000L);
        }
        play(FajrAlarm.prefs(this).getString("sound", "fajr1"));
        vibrate();
        // On an unlocked phone the full-screen intent only shows a banner; try to open the alarm screen anyway.
        try { startActivity(alarmScreen(this)); } catch (Exception ignored) {}
        int max = FajrAlarm.prefs(this).getInt("max", 60);
        h.postDelayed(timeUp, Math.max(5, max) * 60 * 1000L);
        RihalWidgetPlugin.fajrRinging();
        return START_NOT_STICKY;
    }

    private void play(String key) {
        AudioManager am = (AudioManager) getSystemService(AUDIO_SERVICE);
        if (am != null) {
            // The alarm volume of a phone left on "mute" can be very low: raise it to at least 80% while ringing.
            int maxV = am.getStreamMaxVolume(AudioManager.STREAM_ALARM);
            int cur = am.getStreamVolume(AudioManager.STREAM_ALARM);
            int want = (int) Math.ceil(maxV * 0.8);
            if (cur < want) { oldVolume = cur; try { am.setStreamVolume(AudioManager.STREAM_ALARM, want, 0); } catch (Exception ignored) {} }
        }
        int res = getResources().getIdentifier(key == null || key.equals("adhan") ? "adhan" : key, "raw", getPackageName());
        if (res == 0) res = getResources().getIdentifier("fajr1", "raw", getPackageName());
        try {
            player = new MediaPlayer();
            player.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
            player.setDataSource(this, Uri.parse("android.resource://" + getPackageName() + "/" + res));
            player.setLooping(true);
            player.prepare();
            player.start();
        } catch (Exception e) {
            player = null;
        }
    }

    private void vibrate() {
        Vibrator v = (Vibrator) getSystemService(VIBRATOR_SERVICE);
        if (v == null) return;
        long[] p = {0, 600, 900};
        if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(p, 0));
        else v.vibrate(p, 0);
    }

    @Override
    public void onDestroy() {
        h.removeCallbacks(timeUp);
        ringing = false;
        if (player != null) { try { player.stop(); player.release(); } catch (Exception ignored) {} player = null; }
        Vibrator v = (Vibrator) getSystemService(VIBRATOR_SERVICE);
        if (v != null) v.cancel();
        AudioManager am = (AudioManager) getSystemService(AUDIO_SERVICE);
        if (am != null && oldVolume >= 0) { try { am.setStreamVolume(AudioManager.STREAM_ALARM, oldVolume, 0); } catch (Exception ignored) {} }
        if (wake != null && wake.isHeld()) wake.release();
        RihalWidgetPlugin.fajrStopped();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
