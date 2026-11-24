package cn.nwpu.campus;

import android.content.Context;
import android.content.SharedPreferences;
import android.webkit.CookieManager;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** 网费使用自己的 Cookie；前台刷新和定时后台刷新共用此实现。 */
final class NetworkFeeSync {
    static final String TARGET = "network_fee";
    static final String HOME = "https://zizhu.nwpu.edu.cn:8900/home";
    static final String KEY_READY = "net_fee_session_ready";
    static final String KEY_BALANCE = "net_fee_balance";
    static final String KEY_UPDATED = "net_fee_updated";
    private static final Pattern BALANCE = Pattern.compile(
            "(?:账户总余额|帐户总余额|账户余额|账户金额|可用余额|剩余金额|余额)"
                    + "[\\s:：￥¥元]*(-?\\d+(?:\\.\\d+)?)");

    private NetworkFeeSync() {}

    static String parseBalance(String value) {
        if (value == null || value.isEmpty()) return null;
        String text = value.replaceAll("(?is)<!--.*?-->|<script\\b[^>]*>.*?</script>|<style\\b[^>]*>.*?</style>", " ")
                .replaceAll("<[^>]+>", " ")
                .replaceAll("(?i)&(?:nbsp|#160|#xa0);", " ")
                .replace("&yen;", "¥").replace('\u00a0', ' ');
        Matcher match = BALANCE.matcher(text);
        return match.find() ? match.group(1) : null;
    }

    /** 只允许同一个 HTTPS 网费站接收网费 Cookie，包括重定向。 */
    private static boolean isNetworkFeeUrl(URL url) {
        return "https".equalsIgnoreCase(url.getProtocol())
                && "zizhu.nwpu.edu.cn".equalsIgnoreCase(url.getHost())
                && url.getPort() == 8900;
    }

    static Result fetch() {
        try {
            CookieManager cookies = CookieManager.getInstance();
            URL url = new URL(HOME);
            for (int redirect = 0; redirect < 5; redirect++) {
                if (!isNetworkFeeUrl(url)) return Result.expired();
                String cookie = cookies.getCookie(url.toString());
                if (cookie == null || cookie.trim().isEmpty()) return Result.expired();
                HttpURLConnection connection = (HttpURLConnection) url.openConnection();
                try {
                    connection.setConnectTimeout(12_000);
                    connection.setReadTimeout(15_000);
                    connection.setInstanceFollowRedirects(false);
                    connection.setRequestProperty("Cookie", cookie);
                    connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 12)");
                    connection.setRequestProperty("Accept", "text/html,application/xhtml+xml");
                    int status = connection.getResponseCode();
                    for (Map.Entry<String, List<String>> header : connection.getHeaderFields().entrySet()) {
                        if ("Set-Cookie".equalsIgnoreCase(header.getKey()) && header.getValue() != null) {
                            for (String updatedCookie : header.getValue()) {
                                cookies.setCookie(url.toString(), updatedCookie);
                            }
                        }
                    }
                    if (status >= 300 && status < 400) {
                        String location = connection.getHeaderField("Location");
                        if (location == null) return Result.failed();
                        url = new URL(url, location);
                        if (url.getPath().toLowerCase(Locale.ROOT).contains("login")) return Result.expired();
                        continue;
                    }
                    if (status == 401 || status == 403) return Result.expired();
                    if (status != 200) return Result.failed();
                    StringBuilder html = new StringBuilder();
                    try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                            connection.getInputStream(), StandardCharsets.UTF_8))) {
                        String line;
                        while ((line = reader.readLine()) != null) {
                            html.append(line).append('\n');
                            if (html.length() > 2_000_000) return Result.failed();
                        }
                    }
                    String balance = parseBalance(html.toString());
                    if (balance != null) return new Result(balance, false);
                    if (Pattern.compile("(?is)<input[^>]+type\\s*=\\s*['\"]?password")
                            .matcher(html).find()) return Result.expired();
                    return Result.failed();
                } finally {
                    connection.disconnect();
                }
            }
        } catch (Exception ignored) {
        }
        return Result.failed();
    }

    static void save(Context context, SharedPreferences store, String balance) {
        long now = System.currentTimeMillis();
        store.edit().putString(KEY_BALANCE, balance).putLong(KEY_UPDATED, now)
                .putBoolean(KEY_READY, true).putLong("auto_last_" + TARGET, now).apply();
        CookieManager.getInstance().flush();
        DataUpdateSignal.publish(context, TARGET);
    }

    static final class Result {
        final String balance;
        final boolean loginRequired;

        Result(String balance, boolean loginRequired) {
            this.balance = balance;
            this.loginRequired = loginRequired;
        }

        boolean success() { return balance != null; }
        static Result expired() { return new Result(null, true); }
        static Result failed() { return new Result(null, false); }
    }
}
