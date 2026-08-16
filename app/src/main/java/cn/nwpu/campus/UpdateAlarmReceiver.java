package cn.nwpu.campus;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

public class UpdateAlarmReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        if (!BackgroundSyncScheduler.ACTION_WAKE.equals(intent.getAction())) return;
        if (MainActivity.isActivityVisible()) {
            BackgroundSyncScheduler.schedule(context, 60_000L);
            return;
        }
        Intent service = new Intent(context, BackgroundSyncService.class)
                .setAction(BackgroundSyncScheduler.ACTION_WAKE);
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service);
        else context.startService(service);
    }
}
