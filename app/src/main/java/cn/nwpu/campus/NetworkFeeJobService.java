package cn.nwpu.campus;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

/** 网费的普通后台任务，供无法精确定时唤醒前台服务时使用。 */
public final class NetworkFeeJobService extends JobService {
    private static final int JOB_ID = 1006;
    private static final int NOTIFICATION_ID = 1006;
    private static final String CHANNEL = "background_sync";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private JobParameters activeJob;

    static void schedule(Context context, long dueAt) {
        JobScheduler scheduler = context.getSystemService(JobScheduler.class);
        if (scheduler == null) return;
        long delay = Math.max(1000L, dueAt - System.currentTimeMillis());
        JobInfo.Builder job = new JobInfo.Builder(JOB_ID,
                new ComponentName(context, NetworkFeeJobService.class))
                .setMinimumLatency(delay).setOverrideDeadline(delay + 60_000L)
                .setPersisted(true);
        if (Build.VERSION.SDK_INT >= 28) {
            // Campus-only connections can reach this site without passing the
            // system's public-internet validation probe.
            job.setRequiredNetwork(new NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build());
        } else {
            job.setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY);
        }
        scheduler.schedule(job.build());
    }

    static void cancel(Context context) {
        JobScheduler scheduler = context.getSystemService(JobScheduler.class);
        if (scheduler != null) scheduler.cancel(JOB_ID);
    }

    @Override public boolean onStartJob(JobParameters params) {
        SharedPreferences store = getSharedPreferences("campus_private", MODE_PRIVATE);
        if (!store.getBoolean(NetworkFeeSync.KEY_READY, false)
                || !store.getBoolean("auto_network_fee_enabled", true)) return false;
        activeJob = params;
        showProgress();
        new Thread(() -> {
            NetworkFeeSync.Result result = NetworkFeeSync.fetch();
            handler.post(() -> {
                if (activeJob != params) return;
                activeJob = null;
                if (!store.getBoolean(NetworkFeeSync.KEY_READY, false)) {
                    hideProgress();
                    jobFinished(params, false);
                    return;
                }
                if (result.success()) NetworkFeeSync.save(this, store, result.balance);
                else if (result.loginRequired) {
                    store.edit().putBoolean(NetworkFeeSync.KEY_READY, false).apply();
                }
                store.edit().putLong("auto_last_" + NetworkFeeSync.TARGET,
                        System.currentTimeMillis()).apply();
                hideProgress();
                jobFinished(params, false);
                BackgroundSyncScheduler.schedule(this);
            });
        }, "AoxiangNetworkFeeJob").start();
        return true;
    }

    @Override public boolean onStopJob(JobParameters params) {
        activeJob = null;
        hideProgress();
        return true;
    }

    private void showProgress() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) return;
        NotificationChannel channel = new NotificationChannel(CHANNEL, "后台同步",
                NotificationManager.IMPORTANCE_LOW);
        channel.setShowBadge(false);
        manager.createNotificationChannel(channel);
        PendingIntent open = PendingIntent.getActivity(this, NOTIFICATION_ID,
                new Intent(this, MainActivity.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        manager.notify(NOTIFICATION_ID, new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_launcher).setContentTitle("翱翔助手")
                .setContentText("正在更新网费").setCategory(Notification.CATEGORY_SERVICE)
                .setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false)
                .setContentIntent(open).build());
    }

    private void hideProgress() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager != null) manager.cancel(NOTIFICATION_ID);
    }
}
