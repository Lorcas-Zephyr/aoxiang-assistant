package cn.nwpu.campus;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

public class BackgroundSyncService extends Service {
    private static final String EDUCATION_SSO = "https://jwxt.nwpu.edu.cn/student/sso-login";
    private static final String STUDENT_PORTRAIT =
            "https://jwxt.nwpu.edu.cn/student/for-std/student-portrait";
    private static final String ELECTRICITY_HOME = "https://yktapp.nwpu.edu.cn/plat/shouyeUser";
    private static final String ELECTRICITY_SSO = "https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/supwisdom?targetUrl=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat";
    private static final String CREDENTIAL_KEY = "campus_login_credentials";
    private static final String CREDENTIAL_FAILURE_COUNT = "credential_failure_count";
    private static final String INTERACTIVE_AUTH_REQUIRED = "interactive_auth_required";
    private static final String INTERACTIVE_AUTH_TARGET = "interactive_auth_target";
    private static final String PORTRAIT_GPA = "portrait_gpa";
    private static final String SERVICE_CHANNEL = "background_sync";
    private static final String GRADE_CHANNEL = "grade_updates";
    private static final String SCHEDULE_CHANNEL = "schedule_updates";
    private static final String ELECTRICITY_CHANNEL = "electricity_alerts";
    private static final String AUTHENTICATION_CHANNEL = "authentication";
    private static final int SERVICE_NOTIFICATION_ID = 1004;
    private static final long RETRY_DELAY_MS = 5 * 60_000L;
    private static final long PORTRAIT_TIMEOUT_MS = 15_000L;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final UnifiedAuthTracker unifiedAuthTracker = new UnifiedAuthTracker();
    private SharedPreferences store;
    private WebView web;
    private String script;
    private String target;
    private Runnable collectTask;
    private boolean running;
    private PowerManager.WakeLock wakeLock;

    @Override public void onCreate() {
        super.onCreate();
        store = getSharedPreferences("campus_private", MODE_PRIVATE);
        createChannels();
        startForeground(SERVICE_NOTIFICATION_ID, serviceNotification("正在准备自动更新"));
        PowerManager power = (PowerManager) getSystemService(POWER_SERVICE);
        if (power != null) {
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AoxiangAssistant:BackgroundSync");
            wakeLock.acquire(4 * 60_000L);
        }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (running) return START_REDELIVER_INTENT;
        if (MainActivity.isActivityVisible()) {
            BackgroundSyncScheduler.schedule(this, 60_000L);
            finishService();
            return START_NOT_STICKY;
        }
        BackgroundSyncScheduler.NextUpdate next = BackgroundSyncScheduler.nextUpdate(store, System.currentTimeMillis());
        if (next == null) {
            BackgroundSyncScheduler.cancel(this);
            finishService();
            return START_NOT_STICKY;
        }
        long now = System.currentTimeMillis();
        if (next.dueAt > now + 15_000L) {
            BackgroundSyncScheduler.schedule(this);
            finishService();
            return START_NOT_STICKY;
        }
        target = next.target;
        if ("electricity".equals(target) && SyncTimePolicy.isElectricitySettlementTime(now)) {
            BackgroundSyncScheduler.schedule(this);
            finishService();
            return START_NOT_STICKY;
        }
        running = true;
        // Preserve a retry wake if the process is killed during network collection.
        BackgroundSyncScheduler.schedule(this, RETRY_DELAY_MS);
        startForeground(SERVICE_NOTIFICATION_ID, serviceNotification("正在更新" + label(target)));
        beginCollection();
        return START_REDELIVER_INTENT;
    }

    @Override public void onDestroy() {
        destroyWebView();
        releaseWakeLock();
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) {
        return null;
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void beginCollection() {
        unifiedAuthTracker.reset();
        String[] credentials = readCredentials();
        if (credentials[0].isEmpty() || credentials[1].isEmpty()) {
            finishAttempt();
            return;
        }
        script = loadAsset("auto_collect.js");
        web = new WebView(this);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        CookieManager.getInstance().setAcceptCookie(true);
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageStarted(WebView view, String url, Bitmap favicon) {
                unifiedAuthTracker.record(url);
                super.onPageStarted(view, url, favicon);
            }

            @Override public void onPageFinished(WebView view, String url) {
                unifiedAuthTracker.record(url);
                super.onPageFinished(view, url);
            }

            @Override public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
                unifiedAuthTracker.record(url);
                super.doUpdateVisitedHistory(view, url, isReload);
            }

            @Override public boolean shouldOverrideUrlLoading(WebView view, String url) {
                unifiedAuthTracker.record(url);
                try {
                    String host = Uri.parse(url).getHost();
                    return host == null || !(host.equals("nwpu.edu.cn") || host.endsWith(".nwpu.edu.cn"));
                } catch (Exception ignored) {
                    return true;
                }
            }
        });
        startCollector(credentials);
        web.loadUrl("electricity".equals(target) ? ELECTRICITY_SSO : EDUCATION_SSO);
    }

    private void startCollector(String[] credentials) {
        final int[] attempts = {0};
        final long[] gradeReadyAt = {0L};
        final long[] portraitStartedAt = {0L};
        final long[] navigationCooldownUntil = {0L};
        final long[] credentialsSubmittedAt = {0L};
        final boolean[] credentialsSubmitted = {false};
        final JSONArray[] collectedGradeRows = {null};
        collectTask = new Runnable() {
            @Override public void run() {
                if (!running || web == null) return;
                unifiedAuthTracker.record(web.getUrl());
                if (collectedGradeRows[0] != null && portraitStartedAt[0] > 0L
                        && System.currentTimeMillis() - portraitStartedAt[0] >= PORTRAIT_TIMEOUT_MS) {
                    saveGrades(collectedGradeRows[0], Double.NaN);
                    return;
                }
                if (++attempts[0] > 180) {
                    finishAttempt();
                    return;
                }
                if (web.getProgress() < 60) {
                    handler.postDelayed(this, 1000L);
                    return;
                }
                String source = script.replace("__MODE__", target)
                        .replace("__ALLOW_NAV__", Boolean.toString(System.currentTimeMillis() >= navigationCooldownUntil[0]))
                        .replace("__AUTH_EXITED__", Boolean.toString(unifiedAuthTracker.hasExited()))
                        .replace("__USERNAME__", JSONObject.quote(credentials[0]))
                        .replace("__PASSWORD__", JSONObject.quote(credentials[1]))
                        .replace("__SMS_CODE__", JSONObject.quote(""))
                        .replace("__CAN_AUTOFILL__", Boolean.toString(!credentialsSubmitted[0]))
                        .replace("__CAN_FILL_SMS__", "false");
                web.evaluateJavascript(source, result -> {
                    if (!running) return;
                    try {
                        String raw = new JSONArray("[" + result + "]").getString(0);
                        JSONObject payload = new JSONObject(raw);
                        String phase = payload.optString("phase");
                        if ("credentials_pending".equals(phase)) {
                            if (AuthenticationPolicy.shouldWaitForCredentialRedirect(
                                    phase, credentialsSubmittedAt[0], System.currentTimeMillis())) {
                                if (running) handler.postDelayed(this, 1000L);
                                return;
                            }
                            phase = "credentials_required";
                        }
                        if (AuthenticationPolicy.requiresInteractiveCollectionLogin(target, phase)) {
                            requireInteractiveLogin();
                            return;
                        }
                        if ("credentials_submitting".equals(phase)) {
                            credentialsSubmitted[0] = true;
                            credentialsSubmittedAt[0] = System.currentTimeMillis();
                        } else if ("clicked".equals(phase)) {
                            navigationCooldownUntil[0] = System.currentTimeMillis() + 2500L;
                        } else if ("page".equals(phase)) {
                            navigationCooldownUntil[0] = System.currentTimeMillis() + 1500L;
                        } else if ("target_error".equals(phase)) {
                            finishAttempt();
                            return;
                        } else if ("data".equals(phase) && "grades".equals(target)) {
                            if (gradeReadyAt[0] == 0L) gradeReadyAt[0] = System.currentTimeMillis() + 5000L;
                            if (System.currentTimeMillis() >= gradeReadyAt[0]
                                    && collectedGradeRows[0] == null) {
                                JSONArray rows = payload.optJSONArray("rows");
                                if (rows != null && rows.length() > 0) {
                                    collectedGradeRows[0] = rows;
                                    navigationCooldownUntil[0] = System.currentTimeMillis() + 2000L;
                                    portraitStartedAt[0] = System.currentTimeMillis();
                                    web.loadUrl(STUDENT_PORTRAIT);
                                }
                            }
                        } else if ("portrait_data".equals(phase) && "grades".equals(target)
                                && collectedGradeRows[0] != null) {
                            double gpa = payload.optDouble("gpa", Double.NaN);
                            if (!Double.isNaN(gpa)) {
                                saveGrades(collectedGradeRows[0], gpa);
                                return;
                            }
                        } else if ("schedule_data".equals(phase) && "schedule".equals(target)) {
                            saveSchedule(payload.optJSONObject("payload"));
                            return;
                        } else if ("electricity_data".equals(phase) && "electricity".equals(target)) {
                            saveElectricity(payload.optDouble("balance", Double.NaN));
                            return;
                        }
                    } catch (Exception ignored) {}
                    if (running) handler.postDelayed(this, 1000L);
                });
            }
        };
        handler.postDelayed(collectTask, 700L);
    }

    private void saveGrades(JSONArray rows, double gpa) {
        if (rows == null) {
            finishAttempt();
            return;
        }
        List<GradeRecord> records = new ArrayList<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONArray row = rows.optJSONArray(i);
            if (row == null || row.length() < 4) continue;
            records.add(GradeRecord.from(row));
        }
        records = GradeRecord.keepHighest(records);
        JSONArray updated = new JSONArray();
        for (GradeRecord record : records) updated.put(record.json());
        if (updated.length() == 0) {
            finishAttempt();
            return;
        }
        String previous = store.getString("grades", "");
        List<String> changedCourses = previous != null && !previous.isEmpty()
                ? UpdateDiff.changedNames(gradeDiffItems(previous), gradeDiffItems(updated.toString()))
                : Collections.emptyList();
        SharedPreferences.Editor editor = store.edit().putString("grades", updated.toString());
        if (!Double.isNaN(gpa)) editor.putString(PORTRAIT_GPA, Double.toString(gpa));
        editor.apply();
        markCredentialsVerified();
        if (!changedCourses.isEmpty() && store.getBoolean("grade_update_notification_enabled", true)) {
            sendChangeNotification(true, changedCourses);
        }
        finishAttempt();
    }

    private void saveSchedule(JSONObject payload) {
        if (payload == null) {
            finishAttempt();
            return;
        }
        ScheduleImport.ParsedData parsed = ScheduleImport.parsePayload(payload);
        List<ScheduleModels.Semester> semesters = ScheduleStorage.loadSemesters(store);
        List<ScheduleModels.Course> courses = ScheduleStorage.loadCourses(store);
        boolean hadPrevious = !courses.isEmpty();
        List<UpdateDiff.Item> previousItems = UpdateDiff.scheduleItems(courses);
        int importedCount = 0;
        String firstImportedId = "";

        for (ScheduleImport.RawSemester rawSemester : parsed.semesters) {
            List<ScheduleModels.Course> imported = ScheduleImport.convertToCourses(
                    parsed.courses, "", rawSemester.dataSemester);
            if (imported.isEmpty()) continue;
            int index = findSemesterIndex(semesters, rawSemester.name);
            ScheduleModels.Semester semester;
            if (index >= 0) {
                semester = semesters.get(index);
                ScheduleModels.Semester replacement = ScheduleImport.createImportedSemester(rawSemester, imported);
                semester.name = replacement.name;
                semester.weekCount = replacement.weekCount;
                semester.sectionCount = replacement.sectionCount;
                semester.sectionTimes = replacement.sectionTimes;
                semester.startDate = replacement.startDate;
                semester.endDate = replacement.endDate;
            } else {
                semester = ScheduleImport.createImportedSemester(rawSemester, imported);
                semesters.add(semester);
            }
            replaceCourses(courses, semester.id, imported);
            if (firstImportedId.isEmpty()) firstImportedId = semester.id;
            importedCount += imported.size();
        }
        if (importedCount == 0 && !parsed.courses.isEmpty()) {
            ScheduleModels.Semester semester = ScheduleImport.createImportedSemester(parsed.semesters.get(0), new ArrayList<>());
            List<ScheduleModels.Course> imported = ScheduleImport.convertToCourses(parsed.courses, semester.id, "");
            if (!imported.isEmpty()) {
                semesters.add(semester);
                courses.addAll(imported);
                firstImportedId = semester.id;
                importedCount = imported.size();
            }
        }
        if (importedCount > 0) {
            List<String> changedCourses = hadPrevious
                    ? UpdateDiff.changedNames(previousItems, UpdateDiff.scheduleItems(courses))
                    : Collections.emptyList();
            ScheduleStorage.saveSemesters(store, semesters);
            ScheduleStorage.saveCourses(store, courses);
            if (!firstImportedId.isEmpty()) ScheduleStorage.saveSelectedSemester(store, firstImportedId);
            ScheduleWidgetUpdater.updateAll(this);
            if (!changedCourses.isEmpty() && store.getBoolean("schedule_update_notification_enabled", true)) {
                sendChangeNotification(false, changedCourses);
            }
            markCredentialsVerified();
        }
        finishAttempt();
    }

    private void normalizeSemesterDates(ScheduleModels.Semester semester) {
        try {
            java.time.LocalDate start = ScheduleUtils.mondayOnOrBefore(
                    java.time.LocalDate.parse(semester.startDate));
            semester.startDate = start.toString();
            semester.endDate = start.plusWeeks(Math.max(1, semester.weekCount))
                    .minusDays(1).toString();
        } catch (Exception ignored) {
            java.time.LocalDate start = ScheduleUtils.mondayOnOrBefore(java.time.LocalDate.now());
            semester.startDate = start.toString();
            semester.endDate = start.plusWeeks(Math.max(1, semester.weekCount))
                    .minusDays(1).toString();
        }
    }

    private void saveElectricity(double balance) {
        if (!Double.isNaN(balance) && balance >= 0.0) {
            store.edit().putString("electricity_balance", Double.toString(balance))
                    .putString("electricity_balance_source", ELECTRICITY_HOME).apply();
            updateElectricityAlert(balance);
            markCredentialsVerified();
        }
        finishAttempt();
    }

    private void finishAttempt() {
        if (!running) return;
        store.edit().putLong("auto_last_" + target, System.currentTimeMillis()).apply();
        BackgroundSyncScheduler.schedule(this);
        finishService();
    }

    private void finishService() {
        running = false;
        destroyWebView();
        releaseWakeLock();
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        wakeLock = null;
    }

    private void destroyWebView() {
        if (collectTask != null) handler.removeCallbacks(collectTask);
        collectTask = null;
        if (web != null) {
            web.stopLoading();
            web.destroy();
            web = null;
        }
        unifiedAuthTracker.reset();
    }

    private void replaceCourses(List<ScheduleModels.Course> courses, String semesterId,
                                List<ScheduleModels.Course> imported) {
        List<ScheduleModels.Course> kept = new ArrayList<>();
        for (ScheduleModels.Course course : courses) {
            if (!course.semesterId.equals(semesterId)) kept.add(course);
        }
        for (ScheduleModels.Course course : imported) {
            course.semesterId = semesterId;
            kept.add(course);
        }
        courses.clear();
        courses.addAll(kept);
    }

    private int findSemesterIndex(List<ScheduleModels.Semester> semesters, String name) {
        for (int i = 0; i < semesters.size(); i++) {
            if (semesters.get(i).name.equals(name)) return i;
        }
        return -1;
    }

    private List<UpdateDiff.Item> gradeDiffItems(String raw) {
        List<UpdateDiff.Item> items = new ArrayList<>();
        try {
            JSONArray grades = new JSONArray(raw);
            for (int i = 0; i < grades.length(); i++) {
                JSONObject grade = grades.optJSONObject(i);
                if (grade == null) continue;
                String course = grade.optString("course");
                String signature = course + "|" + grade.optDouble("credits") + "|" + grade.opt("point")
                        + "|" + grade.opt("score") + "|" + grade.optString("detail");
                items.add(new UpdateDiff.Item(course, course, signature));
            }
        } catch (Exception ignored) {}
        return items;
    }

    private void sendChangeNotification(boolean grades, List<String> changedCourses) {
        Intent intent = new Intent(this, MainActivity.class).putExtra("start_tab", grades ? 2 : 1);
        PendingIntent pending = PendingIntent.getActivity(this, grades ? 0 : 1, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        String channel = grades ? GRADE_CHANNEL : SCHEDULE_CHANNEL;
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, channel) : new Notification.Builder(this);
        builder.setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(grades ? "成绩有更新" : "课表有更新")
                .setContentText(UpdateDiff.notificationText(changedCourses, grades))
                .setAutoCancel(true).setContentIntent(pending);
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager != null) manager.notify(grades ? 1001 : 1003, builder.build());
    }

    private void sendAuthenticationNotification(String message) {
        Intent intent = new Intent(this, MainActivity.class).putExtra("start_tab", 4);
        PendingIntent pending = PendingIntent.getActivity(this, 6, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, AUTHENTICATION_CHANNEL) : new Notification.Builder(this);
        builder.setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle("登录验证失败")
                .setContentText(message)
                .setAutoCancel(true)
                .setContentIntent(pending);
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager != null) manager.notify(1006, builder.build());
    }

    private void requireInteractiveLogin() {
        store.edit()
                .putBoolean("credentials_verified", false)
                .putBoolean(INTERACTIVE_AUTH_REQUIRED, true)
                .putString(INTERACTIVE_AUTH_TARGET, target == null ? "validate" : target)
                .apply();
        sendAuthenticationNotification("自动更新需要统一认证，请打开翱翔助手完成登录");
        finishAttempt();
    }

    private void markCredentialsVerified() {
        CookieManager.getInstance().flush();
        store.edit().putBoolean("credentials_verified", true)
                .putInt(CREDENTIAL_FAILURE_COUNT, 0)
                .remove(INTERACTIVE_AUTH_REQUIRED)
                .remove(INTERACTIVE_AUTH_TARGET)
                .apply();
    }

    private void updateElectricityAlert(double balance) {
        boolean enabled = store.getBoolean("electricity_alert_enabled", true);
        double threshold = parseNumber(store.getString("electricity_alert_threshold", "20"), 20.0);
        boolean active = store.getBoolean("electricity_alert_active", false);
        boolean low = enabled && balance < threshold;
        if (low && !active) {
            Intent intent = new Intent(this, MainActivity.class);
            PendingIntent pending = PendingIntent.getActivity(this, 2, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(this, ELECTRICITY_CHANNEL) : new Notification.Builder(this);
            builder.setSmallIcon(R.drawable.ic_launcher).setContentTitle("电费余额不足")
                    .setContentText("剩余 " + new DecimalFormat("0.00").format(balance)
                            + " 元，低于 " + new DecimalFormat("0.00").format(threshold) + " 元")
                    .setAutoCancel(true).setContentIntent(pending);
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) manager.notify(1002, builder.build());
        }
        store.edit().putBoolean("electricity_alert_active", low).apply();
    }

    private void createChannels() {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) return;
        NotificationChannel service = new NotificationChannel(SERVICE_CHANNEL, "后台同步", NotificationManager.IMPORTANCE_LOW);
        service.setDescription("数据更新期间显示同步状态");
        service.setShowBadge(false);
        manager.createNotificationChannel(service);
        manager.createNotificationChannel(channel(GRADE_CHANNEL, "成绩更新", "检测到成绩变化时通知"));
        manager.createNotificationChannel(channel(SCHEDULE_CHANNEL, "课表更新", "检测到课表变化时通知"));
        manager.createNotificationChannel(channel(ELECTRICITY_CHANNEL, "电费提醒", "剩余电费低于设定余量时通知"));
        manager.createNotificationChannel(channel(AUTHENTICATION_CHANNEL, "登录验证", "登录密码或验证码需要重新验证时通知"));
    }

    private NotificationChannel channel(String id, String name, String description) {
        NotificationChannel channel = new NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription(description);
        return channel;
    }

    private Notification serviceNotification(String status) {
        Intent intent = new Intent(this, MainActivity.class);
        PendingIntent pending = PendingIntent.getActivity(this, 4, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, SERVICE_CHANNEL) : new Notification.Builder(this);
        return builder.setSmallIcon(R.drawable.ic_launcher).setContentTitle("翱翔助手")
                .setContentText(status).setCategory(Notification.CATEGORY_SERVICE)
                .setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false).setContentIntent(pending).build();
    }

    private String[] readCredentials() {
        try {
            String value = store.getString("login_credentials", "");
            if (value == null || value.isEmpty()) return new String[]{"", ""};
            String[] parts = value.split(":", 2);
            if (parts.length != 2) return new String[]{"", ""};
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, credentialKey(),
                    new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
            String decoded = new String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), StandardCharsets.UTF_8);
            String[] account = decoded.split("\n", 2);
            return account.length == 2 ? account : new String[]{"", ""};
        } catch (Exception ignored) {
            return new String[]{"", ""};
        }
    }

    private SecretKey credentialKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (!keyStore.containsAlias(CREDENTIAL_KEY)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(CREDENTIAL_KEY,
                    KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            generator.generateKey();
        }
        return ((KeyStore.SecretKeyEntry) keyStore.getEntry(CREDENTIAL_KEY, null)).getSecretKey();
    }

    private String loadAsset(String name) {
        try (InputStream input = getAssets().open(name); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int read;
            while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
            return output.toString(StandardCharsets.UTF_8.name());
        } catch (Exception error) {
            return "";
        }
    }

    private void putNullableNumber(JSONObject object, String key, String raw) throws Exception {
        double value = parseNumber(raw, Double.NaN);
        object.put(key, Double.isNaN(value) ? JSONObject.NULL : value);
    }

    private double parseNumber(String raw, double fallback) {
        try {
            if (raw == null) return fallback;
            String cleaned = raw.replaceAll("[^0-9.\\-]", "");
            return cleaned.isEmpty() ? fallback : Double.parseDouble(cleaned);
        } catch (Exception ignored) {
            return fallback;
        }
    }

    private String label(String value) {
        if ("schedule".equals(value)) return "课表";
        if ("electricity".equals(value)) return "电费";
        return "成绩";
    }
}
