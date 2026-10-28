package cn.nwpu.campus;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.CompletionService;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.ExecutorCompletionService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * 长期统一会话：西工大 App 的业务 token 有效期约 30 天。
 *
 * 这层负责 token.nwpu.edu.cn 的长期会话与 axxt 课表接口；成绩、电费和校车
 * 仍使用各自采集链路，但会复用同一个 x-cas-token（服务端不接受时回退网页）。
 * token 使用 Android Keystore 加密后落盘。
 */
final class AxxtSession {
    static final String TOKEN_KEY = "axxt_id_token";
    private static final String TOKEN_IV_KEY = "axxt_id_token_iv";
    private static final String TOKEN_ALIAS = "campus_axxt_session";
    private static final String AUTH = "https://token.nwpu.edu.cn";
    private static final String ATTEST = "https://uis.nwpu.edu.cn/attest";
    private static final String DATA = "https://axxt.nwpu.edu.cn";
    private static final String APP_ID = "com.lantu.MobileCampus.nwpu";
    private static final String DEVICE_ID = "f7a3c2e1b8d94a5c6f0e1d2c3b4a5f6e";
    private static final String CLIENT_ID = "aoxiang-assistant";
    private static final String BROWSER_UA = "Mozilla/5.0 (Linux; Android 13; M2012K11AC) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 "
            + "Chrome/108.0.5359.128 Mobile Safari/537.36";
    private static final int TIMEOUT_MS = 15000;
    private static final DateTimeFormatter API_DATE_TIME =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss", Locale.ROOT);

    private AxxtSession() {}

    interface ScheduleProgress {
        void onProgress(int completedWeeks, int totalWeeks);
    }

    static final class LoginStart {
        final String state;
        final String gid;
        final String securePhone;
        final boolean needMfa;

        LoginStart(String state, String gid, String securePhone, boolean needMfa) {
            this.state = state;
            this.gid = gid;
            this.securePhone = securePhone;
            this.needMfa = needMfa;
        }
    }

    static final class LoginResult {
        final String token;
        final LoginStart pending;
        final String error;

        private LoginResult(String token, LoginStart pending, String error) {
            this.token = token;
            this.pending = pending;
            this.error = error == null ? "" : error;
        }

        static LoginResult token(String value) {
            return new LoginResult(value, null, "");
        }

        static LoginResult pending(LoginStart value) {
            return new LoginResult("", value, "");
        }

        static LoginResult error(String message) {
            return new LoginResult("", null, message);
        }

        boolean success() { return token != null && !token.isEmpty(); }
        boolean needsMfa() { return pending != null; }
    }

    static final class ScheduleResult {
        final JSONObject payload;
        final String error;

        ScheduleResult(JSONObject payload, String error) {
            this.payload = payload;
            this.error = error == null ? "" : error;
        }

        boolean success() { return payload != null; }
    }

    static final class SemesterWeeks {
        final List<Integer> weeks;
        final LocalDate startDate;
        final LocalDate endDate;

        SemesterWeeks(List<Integer> weeks, LocalDate startDate, LocalDate endDate) {
            this.weeks = weeks;
            this.startDate = startDate;
            this.endDate = endDate;
        }
    }

    static LoginResult startPasswordLogin(String username, String password) {
        try {
            JSONObject response = requestJson(AUTH + "/mfa/detect?username=" + enc(username)
                    + "&deviceId=" + enc(DEVICE_ID) + "&password=" + enc(password),
                    "POST", null, null);
            JSONObject data = response.optJSONObject("data");
            String state = data == null ? "" : data.optString("state", "");
            if (state.isEmpty()) return LoginResult.error(responseMessage(response, "账号或密码错误"));
            boolean need = data.optBoolean("need", false);
            if (!need) return LoginResult.token(passwordLogin(username, password, state));
            JSONObject init = requestJson(AUTH + "/mfa/initByType/securephone?state=" + enc(state),
                    "GET", null, null);
            JSONObject initData = init.optJSONObject("data");
            String gid = initData == null ? "" : initData.optString("gid", "");
            if (gid.isEmpty()) return LoginResult.error(responseMessage(init, "无法初始化短信验证"));
            requestJson(ATTEST + "/api/guard/securephone/send", "POST",
                    "application/json; charset=utf-8", new JSONObject().put("gid", gid).toString());
            return LoginResult.pending(new LoginStart(state, gid,
                    initData.optString("securePhone", ""), true));
        } catch (Exception error) {
            return LoginResult.error(errorMessage(error));
        }
    }

    static LoginResult finishPasswordLogin(String username, String password,
                                           LoginStart pending, String code) {
        if (pending == null || pending.state.isEmpty() || pending.gid.isEmpty()) {
            return LoginResult.error("短信登录状态已失效，请重新开始登录");
        }
        try {
            JSONObject valid = requestJson(ATTEST + "/api/guard/securephone/valid", "POST",
                    "application/json; charset=utf-8",
                    new JSONObject().put("code", code).put("gid", pending.gid).toString());
            JSONObject validData = valid.optJSONObject("data");
            if (validData == null || !"ok".equalsIgnoreCase(validData.optString("result", ""))) {
                return LoginResult.error(responseMessage(valid, "验证码错误或已失效"));
            }
            return LoginResult.token(passwordLogin(username, password, pending.state));
        } catch (Exception error) {
            return LoginResult.error(errorMessage(error));
        }
    }

    static boolean hasUsableToken(Context context, SharedPreferences store) {
        String token = readToken(context, store);
        if (token.isEmpty()) return false;
        long exp = tokenExpiry(token);
        return exp > System.currentTimeMillis() / 1000L + 60L;
    }

    static boolean probe(Context context, SharedPreferences store) {
        String token = readToken(context, store);
        if (token.isEmpty()) return false;
        try {
            JSONObject response = requestJson(DATA + "/third-api/v1/learn-space/semester/list",
                    "GET", null, null, token);
            boolean success = response.optBoolean("success", false);
            if (isAuthFailure(response)) clearToken(context, store);
            return success;
        } catch (Exception error) {
            return false;
        }
    }

    static ScheduleResult fetchSchedule(Context context, SharedPreferences store,
                                        ScheduleModels.Semester localSemester) {
        return fetchSchedule(context, store, localSemester, null);
    }

    static ScheduleResult fetchSchedule(Context context, SharedPreferences store,
                                        ScheduleModels.Semester localSemester,
                                        ScheduleProgress progress) {
        String token = readToken(context, store);
        if (token.isEmpty()) return new ScheduleResult(null, "长期课表会话不存在");
        try {
            JSONObject semestersResponse = requestJson(
                    DATA + "/third-api/v1/learn-space/semester/list", "GET", null, null, token);
            if (!semestersResponse.optBoolean("success", false)) {
                if (isAuthFailure(semestersResponse)) clearToken(context, store);
                return new ScheduleResult(null, responseMessage(semestersResponse, "长期课表会话已失效"));
            }
            JSONObject data = semestersResponse.optJSONObject("data");
            String current = data == null ? "" : data.optString("current_semester", "");
            JSONArray available = data == null ? null : data.optJSONArray("semester_list");
            String semesterName = localSemester == null ? "" : localSemester.name;
            boolean localSemesterMatches = !semesterName.isEmpty() && contains(available, semesterName);
            if (!localSemesterMatches) semesterName = current;
            if (semesterName.isEmpty()) return new ScheduleResult(null, "未找到当前学期");

            LocalDate startDate = localSemesterMatches
                    ? parseDate(localSemester == null ? "" : localSemester.startDate) : null;
            if (startDate == null) startDate = semesterStartFromName(semesterName);
            int weekCount = localSemester == null ? 17 : Math.max(2, localSemester.weekCount);
            SemesterWeeks semesterWeeks = loadSemesterWeeks(semesterName, token);
            if (semesterWeeks.startDate != null) startDate = semesterWeeks.startDate;
            JSONArray courses = new JSONArray();
            LocalDate lastDate = semesterWeeks.endDate == null
                    ? startDate.plusWeeks(2).minusDays(1) : semesterWeeks.endDate;
            LocalDate firstCourseDate = null;
            int firstCourseWeek = Integer.MAX_VALUE;
            int successfulWeeks = 0;
            List<Integer> weeks = semesterWeeks.weeks;
            if (weeks.isEmpty()) {
                weeks = new ArrayList<>();
                for (int week = 1; week <= Math.max(17, weekCount); week++) weeks.add(week);
            }
            List<JSONObject> weekResponses = fetchScheduleWeeks(
                    semesterName, weeks, token, progress);
            for (int index = 0; index < weeks.size(); index++) {
                int week = weeks.get(index);
                JSONObject response = weekResponses.get(index);
                if (!response.optBoolean("success", false)) {
                    return new ScheduleResult(null, responseMessage(response, "读取第" + week + "周课表失败"));
                }
                JSONArray list = response.optJSONArray("data");
                if (list == null) return new ScheduleResult(null, "第" + week + "周课表格式异常");
                successfulWeeks++;
                for (int i = 0; i < list.length(); i++) {
                    JSONObject item = list.optJSONObject(i);
                    JSONObject course = coursePayload(item, week, semesterName, localSemester);
                    if (course != null) {
                        courses.put(course);
                        LocalDate courseDate = parseDateTime(firstNonEmpty(
                                item.optString("course_begin"), item.optString("courseBegin")));
                        if (courseDate != null && (firstCourseDate == null
                                || courseDate.isBefore(firstCourseDate))) {
                            firstCourseDate = courseDate;
                            firstCourseWeek = week;
                        }
                        LocalDate end = parseDateTime(item.optString("course_end", ""));
                        if (end != null && end.isAfter(lastDate)) lastDate = end;
                    } else if (item != null) {
                        return new ScheduleResult(null, "第" + week + "周有课程无法识别，已保留原课表");
                    }
                }
            }
            if (successfulWeeks == 0) return new ScheduleResult(null, "课表接口没有返回有效周次");
            if (firstCourseDate != null && firstCourseWeek != Integer.MAX_VALUE) {
                startDate = ScheduleUtils.mondayOnOrBefore(firstCourseDate)
                        .minusWeeks(Math.max(0, firstCourseWeek - 1L));
            }
            JSONObject payload = new JSONObject();
            JSONArray semesterItems = new JSONArray();
            JSONObject semester = new JSONObject()
                    .put("name", semesterName)
                    .put("dataSemester", semesterName)
                    .put("startDate", startDate.toString())
                    .put("endDate", lastDate.toString());
            semesterItems.put(semester);
            payload.put("semesters", semesterItems).put("courses", courses);
            return new ScheduleResult(payload, "");
        } catch (Exception error) {
            return new ScheduleResult(null, errorMessage(error));
        }
    }

    private static SemesterWeeks loadSemesterWeeks(String semesterName, String token) {
        try {
            JSONObject response = requestJson(
                    DATA + "/third-api/v1/learn-space/semester/week/list?semester="
                            + enc(semesterName), "GET", null, null, token);
            if (!response.optBoolean("success", false)) return emptySemesterWeeks();
            return parseSemesterWeeks(response);
        } catch (Exception ignored) {
            return emptySemesterWeeks();
        }
    }

    static SemesterWeeks parseSemesterWeeks(JSONObject response) {
        JSONObject data = response == null ? null : response.optJSONObject("data");
        JSONArray list = data == null ? null : data.optJSONArray("week_list");
        Set<Integer> unique = new LinkedHashSet<>();
        LocalDate first = null;
        LocalDate last = null;
        if (list != null) {
            for (int index = 0; index < list.length(); index++) {
                Object raw = list.opt(index);
                int week = raw instanceof JSONObject
                        ? ((JSONObject) raw).optInt("week", 0) : parsePositiveInt(raw);
                if (week > 0) unique.add(week);
                if (!(raw instanceof JSONObject)) continue;
                JSONObject item = (JSONObject) raw;
                LocalDate start = parseDateTime(firstNonEmpty(item.optString("start_time"),
                        item.optString("startTime"), item.optString("start_date")));
                LocalDate end = parseDateTime(firstNonEmpty(item.optString("end_time"),
                        item.optString("endTime"), item.optString("end_date")));
                if (start != null && (first == null || start.isBefore(first))) first = start;
                if (end != null && (last == null || end.isAfter(last))) last = end;
            }
        }
        List<Integer> weeks = new ArrayList<>(unique);
        Collections.sort(weeks);
        if (first != null) first = ScheduleUtils.mondayOnOrBefore(first);
        return new SemesterWeeks(weeks, first, last);
    }

    private static SemesterWeeks emptySemesterWeeks() {
        return new SemesterWeeks(new ArrayList<>(), null, null);
    }

    private static int parsePositiveInt(Object raw) {
        try {
            int value = Integer.parseInt(String.valueOf(raw));
            return Math.max(0, value);
        } catch (Exception ignored) {
            return 0;
        }
    }

    private static final class WeekResponse {
        final int week;
        final JSONObject response;

        WeekResponse(int week, JSONObject response) {
            this.week = week;
            this.response = response;
        }
    }

    private static List<JSONObject> fetchScheduleWeeks(String semesterName, List<Integer> weeks,
                                                       String token,
                                                       ScheduleProgress progress) throws Exception {
        int totalWeeks = weeks.size();
        int workerCount = Math.min(4, Math.max(1, totalWeeks));
        ExecutorService executor = Executors.newFixedThreadPool(workerCount);
        CompletionService<WeekResponse> completion = new ExecutorCompletionService<>(executor);
        List<Future<WeekResponse>> futures = new ArrayList<>();
        try {
            for (int index = 0; index < totalWeeks; index++) {
                final int requestedWeek = weeks.get(index);
                final int responseIndex = index;
                futures.add(completion.submit(() -> {
                    try {
                        JSONObject response = requestJson(
                                DATA + "/third-api/v1/learn-space/my/course-schedule"
                                + "?semester=" + enc(semesterName) + "&week=" + requestedWeek,
                                "GET", null, null, token);
                        return new WeekResponse(responseIndex, response);
                    } catch (Exception error) {
                        throw new IllegalStateException("读取第" + requestedWeek + "周课表失败："
                                + errorMessage(error), error);
                    }
                }));
            }
            JSONObject[] responses = new JSONObject[totalWeeks];
            long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(TIMEOUT_MS * 2L);
            for (int completed = 0; completed < totalWeeks; completed++) {
                try {
                    long remaining = deadline - System.nanoTime();
                    if (remaining <= 0L) throw new IllegalStateException("读取课表超时");
                    Future<WeekResponse> future = completion.poll(remaining, TimeUnit.NANOSECONDS);
                    if (future == null) throw new IllegalStateException("读取课表超时");
                    WeekResponse result = future.get();
                    responses[result.week] = result.response;
                    if (progress != null) progress.onProgress(completed + 1, totalWeeks);
                } catch (ExecutionException error) {
                    Throwable cause = error.getCause();
                    if (cause instanceof Exception) throw (Exception) cause;
                    throw new IllegalStateException(cause == null ? "读取课表失败" : cause.getMessage());
                }
            }
            List<JSONObject> ordered = new ArrayList<>();
            for (JSONObject response : responses) ordered.add(response);
            return ordered;
        } finally {
            for (Future<WeekResponse> future : futures) {
                if (!future.isDone()) future.cancel(true);
            }
            executor.shutdownNow();
        }
    }

    static void saveToken(Context context, SharedPreferences store, String token) throws Exception {
        if (token == null || token.trim().isEmpty()) throw new IllegalArgumentException("empty token");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, keyStoreKey());
        String iv = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP);
        String value = Base64.encodeToString(cipher.doFinal(token.getBytes(StandardCharsets.UTF_8)), Base64.NO_WRAP);
        store.edit().putString(TOKEN_IV_KEY, iv).putString(TOKEN_KEY, value).apply();
    }

    static void clearToken(Context context, SharedPreferences store) {
        store.edit().remove(TOKEN_KEY).remove(TOKEN_IV_KEY).apply();
    }

    static String readToken(Context context, SharedPreferences store) {
        try {
            String value = store.getString(TOKEN_KEY, "");
            String iv = store.getString(TOKEN_IV_KEY, "");
            if (value == null || value.isEmpty() || iv == null || iv.isEmpty()) return "";
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, keyStoreKey(),
                    new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
            return new String(cipher.doFinal(Base64.decode(value, Base64.NO_WRAP)), StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            return "";
        }
    }

    /**
     * Mirrors the official App's third-party navigation: pass the long-lived
     * idToken through CAS so the WebView receives the target service cookies
     * before the JSON collector runs.
     */
    static String authenticatedServiceUrl(Context context, SharedPreferences store,
                                          String serviceUrl) {
        String token = readToken(context, store);
        if (token.isEmpty() || serviceUrl == null || serviceUrl.trim().isEmpty()) {
            return serviceUrl;
        }
        try {
            if (serviceUrl.startsWith("https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/")) {
                if (serviceUrl.contains("idToken=")) return serviceUrl;
                return serviceUrl + (serviceUrl.contains("?") ? "&" : "?")
                        + "idToken=" + enc(token);
            }
            return "https://uis.nwpu.edu.cn/cas/login?service=" + enc(serviceUrl)
                    + "&idToken=" + enc(token);
        } catch (Exception ignored) {
            return serviceUrl;
        }
    }

    static JSONObject coursePayload(JSONObject item, int week, String semesterName,
                                    ScheduleModels.Semester localSemester) throws Exception {
        if (item == null) return null;
        String name = firstNonEmpty(item.optString("course_name"), item.optString("courseName"),
                item.optString("name"));
        String beginValue = firstNonEmpty(item.optString("course_begin"), item.optString("courseBegin"));
        String endValue = firstNonEmpty(item.optString("course_end"), item.optString("courseEnd"));
        LocalDate date = parseDateTime(beginValue);
        LocalDate endDate = parseDateTime(endValue);
        LocalTime begin = parseTime(beginValue);
        LocalTime end = parseTime(endValue);
        if (name.isEmpty() || date == null || begin == null || end == null) return null;
        int day = date.getDayOfWeek().getValue();
        int[] sections = sectionRangeFromValue(item.opt("section"));
        if (sections[0] < 1) {
            sections = sectionRange(begin, end, item.optString("area", ""), date, localSemester);
        }
        if (sections[0] < 1 || sections[1] < sections[0]) return null;
        String teacher = teacherText(item.opt("teacher"));
        String area = firstNonEmpty(item.optString("area"), item.optString("room"), item.optString("location"));
        StringBuilder schedule = new StringBuilder().append(week).append("周 星期")
                .append(day).append(' ').append(sections[0]);
        if (sections[1] != sections[0]) schedule.append('-').append(sections[1]);
        schedule.append("节");
        JSONObject course = new JSONObject()
                .put("name", name)
                .put("scheduleText", schedule.toString())
                .put("dataSemester", semesterName);
        String code = firstNonEmpty(item.optString("course_number"), item.optString("courseCode"),
                item.optString("course_code"));
        if (!code.isEmpty()) course.put("code", code);
        if (item.has("credits") && !item.isNull("credits")) course.put("credits", item.optDouble("credits"));
        if (!teacher.isEmpty()) course.put("teacher", teacher);
        if (!area.isEmpty()) course.put("location", area);
        return course;
    }

    static int[] sectionRangeFromValue(Object raw) {
        if (raw == null || raw == JSONObject.NULL) return new int[]{-1, -1};
        Matcher matcher = Pattern.compile("\\d+").matcher(String.valueOf(raw));
        int first = -1;
        int last = -1;
        while (matcher.find()) {
            int value;
            try { value = Integer.parseInt(matcher.group()); }
            catch (Exception ignored) { continue; }
            if (value < 1 || value > 30) continue;
            if (first < 0) first = value;
            last = value;
        }
        return new int[]{first, last < 0 ? first : last};
    }

    private static int[] sectionRange(LocalTime begin, LocalTime end, String area,
                                      LocalDate date, ScheduleModels.Semester semester) {
        int first = -1;
        int last = -1;
        int count = semester == null ? 13 : Math.max(13, semester.sectionCount);
        for (int section = 1; section <= count; section++) {
            ScheduleModels.SectionTime time = ScheduleModels.sectionTimeFor(semester, area, date, section);
            if (time == null) continue;
            LocalTime start = parseTime(time.start);
            LocalTime finish = parseTime(time.end);
            if (start == null || finish == null) continue;
            if (Math.abs(start.toSecondOfDay() - begin.toSecondOfDay()) <= 120) {
                if (first < 0) first = section;
            }
            if (Math.abs(finish.toSecondOfDay() - end.toSecondOfDay()) <= 120) {
                last = section;
            }
        }
        if (first < 0) first = nearestSection(begin, area, date, semester, count, true);
        if (last < 0) last = nearestSection(end, area, date, semester, count, false);
        return new int[]{first, Math.max(first, last)};
    }

    private static int nearestSection(LocalTime value, String area, LocalDate date,
                                      ScheduleModels.Semester semester, int count, boolean start) {
        int best = -1;
        long distance = Long.MAX_VALUE;
        for (int section = 1; section <= count; section++) {
            ScheduleModels.SectionTime time = ScheduleModels.sectionTimeFor(semester, area, date, section);
            if (time == null) continue;
            LocalTime candidate = parseTime(start ? time.start : time.end);
            if (candidate == null) continue;
            long d = Math.abs(candidate.toSecondOfDay() - value.toSecondOfDay());
            if (d < distance) { distance = d; best = section; }
        }
        return distance <= 20 * 60 ? best : -1;
    }

    private static String passwordLogin(String username, String password, String state) throws Exception {
        JSONObject response = requestJson(AUTH + "/password/passwordLogin?username=" + enc(username)
                + "&password=" + enc(password) + "&appId=" + enc(APP_ID) + "&geo=&deviceId="
                + enc(DEVICE_ID) + "&osType=android&clientId=" + enc(CLIENT_ID)
                + "&mfaState=" + enc(state), "POST", "application/json", null);
        JSONObject data = response.optJSONObject("data");
        String token = data == null ? "" : firstNonEmpty(data.optString("idToken"), data.optString("userToken"));
        if (token.isEmpty()) throw new IllegalStateException(responseMessage(response, "长期课表登录失败"));
        return token;
    }

    private static JSONObject requestJson(String url, String method, String contentType,
                                          String body) throws Exception {
        return requestJson(url, method, contentType, body, "");
    }

    private static JSONObject requestJson(String url, String method, String contentType,
                                          String body, String token) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setRequestMethod(method);
        connection.setConnectTimeout(TIMEOUT_MS);
        connection.setReadTimeout(TIMEOUT_MS);
        connection.setUseCaches(false);
        connection.setRequestProperty("User-Agent", BROWSER_UA);
        connection.setRequestProperty("Accept", "application/json");
        if (token != null && !token.isEmpty()) connection.setRequestProperty("x-cas-token", token);
        if (contentType != null && !contentType.isEmpty()) connection.setRequestProperty("Content-Type", contentType);
        try {
            if (body != null) {
                connection.setDoOutput(true);
                try (OutputStream output = connection.getOutputStream()) {
                    output.write(body.getBytes(StandardCharsets.UTF_8));
                }
            }
            int status = connection.getResponseCode();
            InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
            String text = readAll(stream);
            if (status < 200 || status >= 300) {
                throw new IllegalStateException("HTTP " + status + " " + text);
            }
            try { return new JSONObject(text); }
            catch (Exception error) { throw new IllegalStateException("接口返回格式错误"); }
        } finally {
            connection.disconnect();
        }
    }

    private static String readAll(InputStream input) throws Exception {
        if (input == null) return "";
        StringBuilder value = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) value.append(line);
        }
        return value.toString();
    }

    private static SecretKey keyStoreKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (!keyStore.containsAlias(TOKEN_ALIAS)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(TOKEN_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            generator.generateKey();
        }
        return ((KeyStore.SecretKeyEntry) keyStore.getEntry(TOKEN_ALIAS, null)).getSecretKey();
    }

    private static long tokenExpiry(String token) {
        try {
            String[] parts = token.split("\\.");
            if (parts.length < 2) return 0L;
            String encoded = parts[1].replace('-', '+').replace('_', '/');
            while ((encoded.length() & 3) != 0) encoded += "=";
            JSONObject payload = new JSONObject(new String(
                    Base64.decode(encoded, Base64.DEFAULT), StandardCharsets.UTF_8));
            return payload.optLong("exp", 0L);
        } catch (Exception ignored) { return 0L; }
    }

    private static String responseMessage(JSONObject response, String fallback) {
        if (response != null) {
            String value = firstNonEmpty(response.optString("message"), response.optString("msg"),
                    response.optString("error"));
            if (!value.isEmpty() && !"null".equalsIgnoreCase(value)) return value;
        }
        return fallback;
    }

    private static boolean isAuthFailure(JSONObject response) {
        if (response == null) return false;
        String code = response.optString("code", "");
        String message = responseMessage(response, "").toLowerCase(Locale.ROOT);
        return "00101P401".equalsIgnoreCase(code) || "401".equals(code)
                || (message.contains("签名") && (message.contains("错") || message.contains("失效")))
                || message.contains("token过期") || message.contains("token失效");
    }

    private static String errorMessage(Exception error) {
        String message = error == null ? "" : error.getMessage();
        return message == null || message.trim().isEmpty() ? "网络请求失败" : message.trim();
    }

    private static boolean contains(JSONArray values, String value) {
        if (values == null || value == null) return false;
        for (int i = 0; i < values.length(); i++) if (value.equals(values.optString(i))) return true;
        return false;
    }

    private static String teacherText(Object raw) {
        if (raw == null || raw == JSONObject.NULL) return "";
        Set<String> names = new LinkedHashSet<>();
        if (raw instanceof JSONArray) {
            JSONArray values = (JSONArray) raw;
            for (int i = 0; i < values.length(); i++) addTeacher(names, values.opt(i));
        } else addTeacher(names, raw);
        return String.join("、", names);
    }

    private static void addTeacher(Set<String> names, Object raw) {
        if (raw instanceof JSONObject) {
            JSONObject value = (JSONObject) raw;
            String name = firstNonEmpty(value.optString("nameZh"), value.optString("name"), value.optString("teacherName"));
            if (!name.isEmpty()) names.add(name);
        } else if (raw != null && raw != JSONObject.NULL && !String.valueOf(raw).trim().isEmpty()) {
            names.add(String.valueOf(raw).trim());
        }
    }

    private static LocalDate parseDateTime(String value) {
        if (value == null || value.trim().isEmpty()) return null;
        String normalized = value.trim().replace('T', ' ');
        try { return LocalDateTime.parse(normalized, API_DATE_TIME).toLocalDate(); }
        catch (Exception ignored) {
            try { return LocalDate.parse(normalized.substring(0, 10)); }
            catch (Exception ignoredAgain) { return null; }
        }
    }

    private static LocalTime parseTime(String value) {
        if (value == null || value.trim().isEmpty()) return null;
        String normalized = value.trim().replace('T', ' ');
        try { return LocalDateTime.parse(normalized, API_DATE_TIME).toLocalTime(); }
        catch (Exception ignored) {
            try { return LocalTime.parse(normalized.substring(Math.max(0, normalized.length() - 8))); }
            catch (Exception ignoredAgain) { return null; }
        }
    }

    private static LocalDate parseDate(String value) {
        try { return LocalDate.parse(value); }
        catch (Exception ignored) { return null; }
    }

    private static LocalDate semesterStartFromName(String value) {
        java.util.regex.Matcher matcher = java.util.regex.Pattern
                .compile("(\\d{4})-(\\d{4}).*(春|秋|夏|冬)").matcher(value == null ? "" : value);
        if (matcher.find()) {
            int year = Integer.parseInt(matcher.group(1));
            boolean spring = "春".equals(matcher.group(3));
            if (spring) year = Integer.parseInt(matcher.group(2));
            int month = spring ? 2 : 9;
            return ScheduleUtils.mondayOnOrBefore(LocalDate.of(year, month, spring ? 24 : 1));
        }
        return ScheduleUtils.mondayOnOrBefore(LocalDate.now());
    }

    private static String firstNonEmpty(String... values) {
        for (String value : values) if (value != null && !value.trim().isEmpty()) return value.trim();
        return "";
    }

    private static String enc(String value) throws Exception {
        return URLEncoder.encode(value == null ? "" : value, "UTF-8");
    }
}
