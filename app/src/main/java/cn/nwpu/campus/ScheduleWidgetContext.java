package cn.nwpu.campus;

import android.content.Context;

final class ScheduleWidgetContext {
    private static Context context;

    private ScheduleWidgetContext() {}

    static Context get() {
        return context;
    }

    static void set(Context value) {
        context = value.getApplicationContext();
    }
}
