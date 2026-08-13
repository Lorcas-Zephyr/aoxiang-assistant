package cn.nwpu.campus;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent received) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(received.getAction())) return;
        boolean enabled = context.getSharedPreferences("campus_private", Context.MODE_PRIVATE)
                .getBoolean("boot_auto_start", false);
        if (!enabled) return;
        Intent launch = new Intent(context, MainActivity.class)
                .putExtra("silent_boot", true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        context.startActivity(launch);
    }
}
