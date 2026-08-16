package cn.nwpu.campus;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class VersionUtils {
    private static final Pattern VERSION = Pattern.compile("(?i)(?:^|[^0-9])v?([0-9]+(?:\\.[0-9]+)*)");
    private static final String GITCODE_DOWNLOAD_BASE =
            "https://gitcode.com/lorcas/aoxiang-assistant/releases/download/";

    private VersionUtils() {}

    static String extractVersion(String value) {
        if (value == null) return "";
        Matcher matcher = VERSION.matcher(value.trim());
        return matcher.find() ? matcher.group(1) : "";
    }

    static boolean isNewer(String candidate, String current) {
        List<Integer> next = parts(candidate);
        List<Integer> installed = parts(current);
        if (next.isEmpty() || installed.isEmpty()) return false;
        int size = Math.max(next.size(), installed.size());
        for (int i = 0; i < size; i++) {
            int left = i < next.size() ? next.get(i) : 0;
            int right = i < installed.size() ? installed.get(i) : 0;
            if (left != right) return left > right;
        }
        return false;
    }

    static String gitCodeApkDownloadUrl(String value) {
        String version = extractVersion(value);
        if (version.isEmpty()) return "";
        String release = "v" + version;
        return GITCODE_DOWNLOAD_BASE + release + "/aoxiang-assistant-" + release + ".apk";
    }

    private static List<Integer> parts(String value) {
        String version = extractVersion(value);
        List<Integer> parts = new ArrayList<>();
        if (version.isEmpty()) return parts;
        for (String part : version.split("\\.")) {
            try {
                parts.add(Integer.parseInt(part));
            } catch (NumberFormatException ignored) {
                return new ArrayList<>();
            }
        }
        return parts;
    }
}
