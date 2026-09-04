package cn.nwpu.campus;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

public final class DataUpdateSignal {
    public static final String ACTION_DATA_UPDATED = "cn.nwpu.campus.action.DATA_UPDATED";
    public static final String EXTRA_TARGET = "target";
    public static final String TARGET_GRADES = "grades";
    public static final String TARGET_SCHEDULE = "schedule";
    public static final String TARGET_ELECTRICITY = "electricity";

    private static final String PREFERENCES = "campus_private";
    private static final String REVISION_PREFIX = "data_revision_";

    private DataUpdateSignal() {}

    public static synchronized void publish(Context context, String target) {
        if (!isValidTarget(target)) return;
        SharedPreferences store = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
        long nextRevision = store.getLong(revisionKey(target), 0L) + 1L;
        store.edit().putLong(revisionKey(target), nextRevision).apply();
        Intent update = new Intent(ACTION_DATA_UPDATED)
                .setPackage(context.getPackageName())
                .putExtra(EXTRA_TARGET, target);
        context.sendBroadcast(update);
    }

    public static long revision(SharedPreferences store, String target) {
        if (!isValidTarget(target)) return 0L;
        return store.getLong(revisionKey(target), 0L);
    }

    public static boolean isValidTarget(String target) {
        return TARGET_GRADES.equals(target)
                || TARGET_SCHEDULE.equals(target)
                || TARGET_ELECTRICITY.equals(target);
    }

    private static String revisionKey(String target) {
        return REVISION_PREFIX + target;
    }
}
