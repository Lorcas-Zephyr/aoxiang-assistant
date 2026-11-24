package cn.nwpu.campus;

import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.webkit.CookieManager;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.LinkedHashMap;
import java.util.Map;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** 只保存网费站验证成功的会话；不保存密码，也不修改服务端有效期。 */
final class NetworkFeeSession {
    private static final String KEY = "net_fee_session_encrypted";
    private static final String IV = "net_fee_session_iv";
    private static final String ALIAS = "campus_network_fee_session";
    private static final String EPOCH = "net_fee_session_epoch";

    private NetworkFeeSession() {}

    static synchronized void save(SharedPreferences store) {
        String cookie = sessionCookie(CookieManager.getInstance().getCookie(NetworkFeeSync.HOME));
        if (cookie.isEmpty()) return;
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key());
            store.edit().putString(KEY, Base64.encodeToString(
                    cipher.doFinal(cookie.getBytes(StandardCharsets.UTF_8)), Base64.NO_WRAP))
                    .putString(IV, Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP)).commit();
        } catch (Exception ignored) {
            // 当前会话仍可继续使用；密钥不可用时不降级为明文保存。
        }
    }

    /** 启动时仅补回丢失的会话；失效回退时可恢复上次已验证的会话。 */
    static synchronized boolean restore(SharedPreferences store, boolean replace) {
        String saved = read(store);
        String current = sessionCookie(CookieManager.getInstance().getCookie(NetworkFeeSync.HOME));
        if (saved.isEmpty() || saved.equals(current) || (!replace && !current.isEmpty())) return false;
        for (String part : saved.split("; ")) {
            CookieManager.getInstance().setCookie(NetworkFeeSync.HOME,
                    part + "; Path=/; Secure; HttpOnly; SameSite=Lax");
        }
        CookieManager.getInstance().flush();
        return true;
    }

    static synchronized void clear(SharedPreferences store) {
        store.edit().remove(KEY).remove(IV).putLong(EPOCH, generation(store) + 1).commit();
    }

    static long generation(SharedPreferences store) {
        return store.getLong(EPOCH, 0L);
    }

    private static String read(SharedPreferences store) {
        try {
            String encrypted = store.getString(KEY, "");
            String iv = store.getString(IV, "");
            if (encrypted == null || encrypted.isEmpty() || iv == null || iv.isEmpty()) return "";
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(),
                    new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
            return sessionCookie(new String(cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)),
                    StandardCharsets.UTF_8));
        } catch (Exception ignored) {
            return "";
        }
    }

    /** 白名单和换行检查，避免恢复其他站点或不可信 Cookie 属性。 */
    static String sessionCookie(String value) {
        if (value == null || value.indexOf('\r') >= 0 || value.indexOf('\n') >= 0) return "";
        Map<String, String> cookies = new LinkedHashMap<>();
        for (String part : value.split(";")) {
            int separator = part.indexOf('=');
            if (separator <= 0) continue;
            String name = part.substring(0, separator).trim();
            String content = part.substring(separator + 1).trim();
            if (("PHPSESSID_8800".equals(name) || "_csrf-8800".equals(name))
                    && !content.isEmpty()) cookies.put(name, content);
        }
        if (!cookies.containsKey("PHPSESSID_8800")) return "";
        StringBuilder result = new StringBuilder();
        for (Map.Entry<String, String> cookie : cookies.entrySet()) {
            if (result.length() > 0) result.append("; ");
            result.append(cookie.getKey()).append('=').append(cookie.getValue());
        }
        return result.toString();
    }

    private static SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (!store.containsAlias(ALIAS)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,
                    "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            generator.generateKey();
        }
        return ((KeyStore.SecretKeyEntry) store.getEntry(ALIAS, null)).getSecretKey();
    }
}
