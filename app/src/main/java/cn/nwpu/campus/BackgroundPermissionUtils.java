package cn.nwpu.campus;

import android.app.AlarmManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class BackgroundPermissionUtils {
    private BackgroundPermissionUtils() {}

    static boolean canScheduleExactAlarms(Context context) {
        if (Build.VERSION.SDK_INT < 31) return true;
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        return manager != null && manager.canScheduleExactAlarms();
    }

    static boolean isIgnoringBatteryOptimizations(Context context) {
        if (Build.VERSION.SDK_INT < 23) return true;
        PowerManager manager = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        return manager != null && manager.isIgnoringBatteryOptimizations(context.getPackageName());
    }

    static Intent exactAlarmPermissionIntent(Context context) {
        return new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                Uri.parse("package:" + context.getPackageName()));
    }

    static Intent batteryOptimizationPermissionIntent(Context context) {
        return new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:" + context.getPackageName()));
    }

    static Intent applicationDetailsIntent(Context context) {
        return new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:" + context.getPackageName()));
    }

    static Intent autostartSettingsIntent(Context context) {
        PackageManager packages = context.getPackageManager();
        for (ComponentName component : autostartComponents()) {
            Intent intent = new Intent().setComponent(component);
            if (packages.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) return intent;
        }
        return applicationDetailsIntent(context);
    }

    static boolean hasDedicatedAutostartSettings(Context context) {
        PackageManager packages = context.getPackageManager();
        for (ComponentName component : autostartComponents()) {
            if (packages.resolveActivity(new Intent().setComponent(component),
                    PackageManager.MATCH_DEFAULT_ONLY) != null) return true;
        }
        return false;
    }

    static Intent backgroundPowerSettingsIntent(Context context) {
        PackageManager packages = context.getPackageManager();
        for (ComponentName component : backgroundPowerComponents()) {
            Intent intent = new Intent().setComponent(component);
            if (packages.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) return intent;
        }
        return applicationDetailsIntent(context);
    }

    static boolean hasDedicatedBackgroundPowerSettings(Context context) {
        PackageManager packages = context.getPackageManager();
        for (ComponentName component : backgroundPowerComponents()) {
            if (packages.resolveActivity(new Intent().setComponent(component),
                    PackageManager.MATCH_DEFAULT_ONLY) != null) return true;
        }
        return false;
    }

    private static List<ComponentName> autostartComponents() {
        String manufacturer = Build.MANUFACTURER == null ? ""
                : Build.MANUFACTURER.toLowerCase(Locale.ROOT);
        List<ComponentName> components = new ArrayList<>();
        if (manufacturer.contains("xiaomi") || manufacturer.contains("redmi")) {
            components.add(new ComponentName("com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"));
        } else if (manufacturer.contains("huawei")) {
            components.add(new ComponentName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"));
        } else if (manufacturer.contains("honor")) {
            components.add(new ComponentName("com.hihonor.systemmanager",
                    "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"));
        } else if (manufacturer.contains("oppo") || manufacturer.contains("oneplus")
                || manufacturer.contains("realme")) {
            components.add(new ComponentName("com.oplus.safecenter",
                    "com.oplus.safecenter.permission.startup.StartupAppListActivity"));
            components.add(new ComponentName("com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"));
        } else if (manufacturer.contains("vivo") || manufacturer.contains("iqoo")) {
            components.add(new ComponentName("com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"));
        } else if (manufacturer.contains("meizu")) {
            components.add(new ComponentName("com.meizu.safe",
                    "com.meizu.safe.permission.SmartBGActivity"));
        } else if (manufacturer.contains("samsung")) {
            components.add(new ComponentName("com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity"));
        }
        return components;
    }

    private static List<ComponentName> backgroundPowerComponents() {
        String manufacturer = Build.MANUFACTURER == null ? ""
                : Build.MANUFACTURER.toLowerCase(Locale.ROOT);
        List<ComponentName> components = new ArrayList<>();
        if (manufacturer.contains("vivo") || manufacturer.contains("iqoo")) {
            components.add(new ComponentName("com.iqoo.powersaving",
                    "com.iqoo.powersaving.BackgroundHighUsageActivity"));
        }
        return components;
    }
}
