package cn.nwpu.campus;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

public class UpdateAlarmReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        if (!BackgroundSyncScheduler.ACTION_WAKE.equals(intent.getAction())) return;
        if (MainActivity.isActivityVisible()) {
            SharedPreferences store = context.getSharedPreferences(
                    "campus_private", Context.MODE_PRIVATE);
            BusNotifications.notifyDueDepartures(
                    context, store, BusStorage.load(store), System.currentTimeMillis());
            BackgroundSyncScheduler.schedule(context);
            return;
        }
        Intent service = new Intent(context, BackgroundSyncService.class)
                .setAction(BackgroundSyncScheduler.ACTION_WAKE);
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service);
            else context.startService(service);
        } catch (IllegalStateException | SecurityException denied) {
            // A permission can be revoked after the alarm was scheduled.
            // Re-evaluate scheduling instead of crashing the receiver process.
            BackgroundSyncScheduler.schedule(context, 5 * 60_000L);
        }
    }
}
