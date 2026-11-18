package cn.nwpu.campus;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import java.util.Locale;

/** Small, dependency-free helpers for Huawei/Honor (HarmonyOS) reminder reliability. */
public final class DeviceCompat {
    private DeviceCompat() {}

    public static boolean isHuaweiFamily() {
        String manufacturer = safe(Build.MANUFACTURER);
        String brand = safe(Build.BRAND);
        return manufacturer.contains("huawei") || manufacturer.contains("honor")
                || brand.contains("huawei") || brand.contains("honor");
    }

    public static void openNotificationSettings(Activity activity) {
        if (activity == null) return;
        try {
            Intent intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, activity.getPackageName());
            activity.startActivity(intent);
        } catch (Exception ignored) {
            openAppSettings(activity);
        }
    }

    public static void openAppSettings(Activity activity) {
        if (activity == null) return;
        try {
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + activity.getPackageName()));
            activity.startActivity(intent);
        } catch (Exception ignored) {}
    }

    private static String safe(String value) {
        return value == null ? "" : value.toLowerCase(Locale.ROOT);
    }
}
