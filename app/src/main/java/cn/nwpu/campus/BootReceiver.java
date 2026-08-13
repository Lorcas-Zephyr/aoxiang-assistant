package cn.nwpu.campus;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent received) {
        String action = received.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                && !Intent.ACTION_TIME_CHANGED.equals(action)
                && !Intent.ACTION_TIMEZONE_CHANGED.equals(action)) return;
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)) {
            boolean enabled = context.getSharedPreferences("campus_private", Context.MODE_PRIVATE)
                    .getBoolean("boot_auto_start", true);
            if (!enabled) return;
        }
        BackgroundSyncScheduler.schedule(context);
    }
}
