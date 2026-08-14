package cn.nwpu.campus;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.app.DatePickerDialog;
import android.app.Dialog;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.text.InputType;
import android.util.Base64;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.ViewConfiguration;
import android.view.Window;
import android.view.WindowManager;
import android.view.animation.DecelerateInterpolator;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.text.DecimalFormat;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

public class MainActivity extends Activity {
    private static final String EDUCATION_SSO = "https://jwxt.nwpu.edu.cn/student/sso-login";
    private static final String ELECTRICITY_HOME = "https://yktapp.nwpu.edu.cn/plat/shouyeUser";
    private static final String ELECTRICITY_SSO = "https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/supwisdom?targetUrl=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat";
    private static final String EXTRA_START_TAB = "start_tab";
    private static final String GRADE_CHANNEL = "grade_updates";
    private static final String SCHEDULE_CHANNEL = "schedule_updates";
    private static final String ELECTRICITY_CHANNEL = "electricity_alerts";
    private static final String CREDENTIAL_KEY = "campus_login_credentials";
    private static final int REQUEST_EXPORT_JSON = 11;
    private static final int REQUEST_IMPORT_JSON = 12;
    private static final int TAB_HOME = 0;
    private static final int TAB_SCHEDULE = 1;
    private static final int TAB_GRADES = 2;
    private static final int TAB_MANAGE = 3;
    private static final int TAB_SETTINGS = 4;
    private static final String UNIT_MINUTES = "分钟";
    private static final String UNIT_HOURS = "小时";
    private static final String UNIT_DAYS = "天";
    private static final int SCHEDULE_SECTION_HEIGHT_DP = 48;

    private static volatile boolean activityAlive;

    public static boolean isActivityAlive() {
        return activityAlive;
    }

    private final DecimalFormat scoreDf = new DecimalFormat("0.00");
    private final DecimalFormat pointDf = new DecimalFormat("0.000");
    private final Handler automationHandler = new Handler(Looper.getMainLooper());
    private final DateTimeFormatter monthDayFormatter = DateTimeFormatter.ofPattern("M/d", Locale.CHINA);

    private SharedPreferences store;
    private FrameLayout root;
    private FrameLayout content;
    private FrameLayout automationHost;
    private LinearLayout mainShell;
    private LinearLayout bottom;
    private View pendingPreviousMainShell;
    private View pendingPreviousAutomationHost;
    private ScrollView currentPage;
    private WebView automationWeb;
    private Dialog loginDialog;

    private boolean loginPromptVisible;
    private boolean autoGradeEnabled;
    private boolean autoScheduleEnabled;
    private boolean autoElectricityEnabled;
    private boolean electricityAlertEnabled;
    private boolean gradeUpdateNotificationEnabled;
    private boolean scheduleUpdateNotificationEnabled;
    private boolean bootAutoStart;
    private boolean automaticRun;
    private boolean silentBoot;
    private boolean darkMode;
    private boolean scheduleShowMonth;
    private int gradeIntervalValue;
    private int scheduleIntervalValue;
    private int electricityIntervalValue;
    private int currentTab;
    private final int[] tabScrollPositions = new int[5];
    private int automationGeneration;
    private int scheduleWeekOffset;
    private View scheduleContentView;
    private FrameLayout scheduleViewport;
    private View scheduleSwipeIncoming;
    private int scheduleSwipeDirection;
    private int scheduleSwipeWidth;
    private boolean scheduleSwipeAnimating;
    private String automationTarget = "";
    private String pendingSmsCode = "";
    private String autoCollectScript = "";
    private String themeColor = ScheduleModels.DEFAULT_THEME_COLOR;
    private String selectedSemesterId = "";
    private String pendingExportJson = "";
    private String gradeIntervalUnit = UNIT_MINUTES;
    private String scheduleIntervalUnit = UNIT_MINUTES;
    private String electricityIntervalUnit = UNIT_MINUTES;
    private String settingsPanel = "";
    private double electricityBalance = Double.NaN;
    private double electricityAlertThreshold = 20.0;

    private Runnable automationTask;
    private Runnable scheduledUpdateTask;

    private List<Grade> grades = new ArrayList<>();
    private List<ScheduleModels.Semester> semesters = new ArrayList<>();
    private List<ScheduleModels.Course> courses = new ArrayList<>();
    private LocalDate scheduleMonthAnchor = LocalDate.now();

    private interface SemesterCallback {
        void onPick(ScheduleModels.Semester semester);
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        activityAlive = true;
        store = getSharedPreferences("campus_private", MODE_PRIVATE);
        themeColor = ScheduleStorage.loadThemeColor(store);
        darkMode = ScheduleStorage.loadDarkMode(store);
        autoCollectScript = loadAsset("auto_collect.js");
        grades = loadGrades();
        semesters = ScheduleStorage.loadSemesters(store);
        courses = ScheduleStorage.loadCourses(store);
        if (normalizeSemesterSectionTimes() | normalizeSemesterStartDates()) {
            ScheduleStorage.saveSemesters(store, semesters);
        }
        selectedSemesterId = ScheduleStorage.loadSelectedSemester(store);
        autoGradeEnabled = store.getBoolean("auto_grade_enabled", true);
        autoScheduleEnabled = store.getBoolean("auto_schedule_enabled", true);
        autoElectricityEnabled = store.getBoolean("auto_electricity_enabled", true);
        electricityAlertEnabled = store.getBoolean("electricity_alert_enabled", true);
        gradeUpdateNotificationEnabled = store.getBoolean("grade_update_notification_enabled", true);
        scheduleUpdateNotificationEnabled = store.getBoolean("schedule_update_notification_enabled", true);
        bootAutoStart = store.getBoolean("boot_auto_start", true);
        int legacyGradeSeconds = Math.max(60, store.getInt("grade_interval_seconds", 600));
        gradeIntervalValue = Math.max(1, store.getInt("grade_interval_value", (legacyGradeSeconds + 59) / 60));
        scheduleIntervalValue = Math.max(1, store.getInt("schedule_interval_value", 60));
        electricityIntervalValue = Math.max(1, store.getInt("electricity_interval_value", 10));
        gradeIntervalUnit = loadIntervalUnit("grade_interval_unit", UNIT_MINUTES);
        scheduleIntervalUnit = loadIntervalUnit("schedule_interval_unit", UNIT_MINUTES);
        electricityIntervalUnit = loadIntervalUnit("electricity_interval_unit", UNIT_MINUTES);
        electricityBalance = ELECTRICITY_HOME.equals(store.getString("electricity_balance_source", ""))
                ? parseStoredDouble("electricity_balance", Double.NaN) : Double.NaN;
        electricityAlertThreshold = parseStoredDouble("electricity_alert_threshold", 20.0);
        silentBoot = getIntent().getBooleanExtra("silent_boot", false);
        ensureSelectedSemester();
        applyWindowTheme();

        root = new FrameLayout(this);
        root.setBackgroundColor(backgroundColor());
        setContentView(root);
        applySystemBarInsets();
        buildShell();
        createNotificationChannel();
        showTab(getIntent().getIntExtra(EXTRA_START_TAB, TAB_HOME));
        if (autoGradeEnabled || autoScheduleEnabled || electricityAlertEnabled) {
            requestNotificationPermission();
        }
        scheduleAllAutomaticUpdates(1500);
        syncBackgroundService();
        if (silentBoot) {
            root.postDelayed(() -> moveTaskToBack(true), 300);
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (intent.hasExtra(EXTRA_START_TAB)) {
            cancelAutomation();
            showTab(intent.getIntExtra(EXTRA_START_TAB, TAB_HOME));
            return;
        }
        if (Intent.ACTION_MAIN.equals(intent.getAction()) && intent.hasCategory(Intent.CATEGORY_LAUNCHER)) {
            cancelAutomation();
            showTab(TAB_HOME);
        }
    }

    @Override
    protected void onDestroy() {
        cancelScheduledUpdates();
        cancelAutomation();
        activityAlive = false;
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        if (loginPromptVisible) {
            if (loginDialog != null) loginDialog.dismiss();
            loginPromptVisible = false;
            cancelAutomation();
            return;
        }
        if (automationWeb != null) {
            cancelAutomation();
            showTab(currentTab);
            return;
        }
        if (currentTab == TAB_SETTINGS && !settingsPanel.isEmpty()) {
            settingsPanel = "";
            if (currentPage != null) currentPage.scrollTo(0, 0);
            showTab(TAB_SETTINGS);
            return;
        }
        super.onBackPressed();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        if (requestCode == REQUEST_EXPORT_JSON) {
            writeExportJson(uri);
        } else if (requestCode == REQUEST_IMPORT_JSON) {
            importBackupJson(uri);
        }
    }

    private void buildShell() {
        View previousMainShell = mainShell;
        View previousAutomationHost = automationHost;

        mainShell = new LinearLayout(this);
        mainShell.setOrientation(LinearLayout.VERTICAL);
        mainShell.setBackgroundColor(backgroundColor());

        content = new FrameLayout(this);
        mainShell.addView(content, new LinearLayout.LayoutParams(-1, 0, 1));

        bottom = new LinearLayout(this);
        bottom.setGravity(Gravity.CENTER);
        bottom.setPadding(dp(8), dp(5), dp(8), dp(6));
        bottom.setBackground(border(panelColor(), lineColor(), 0));
        mainShell.addView(bottom, new LinearLayout.LayoutParams(-1, dp(62)));

        String[] labels = {"首页", "课表", "成绩", "管理", "设置"};
        int[] icons = {R.drawable.ic_nav_home, R.drawable.ic_nav_schedule, R.drawable.ic_nav_grades,
                R.drawable.ic_nav_manage, R.drawable.ic_nav_settings};
        for (int i = 0; i < labels.length; i++) {
            final int tab = i;
            LinearLayout item = new LinearLayout(this);
            item.setOrientation(LinearLayout.VERTICAL);
            item.setGravity(Gravity.CENTER);
            ImageView icon = new ImageView(this);
            icon.setImageResource(icons[i]);
            icon.setColorFilter(currentTab == tab ? primaryColor() : mutedColor());
            icon.setContentDescription(labels[i]);
            icon.setPadding(dp(8), dp(4), dp(8), dp(3));
            TextView text = label(labels[i], 10, currentTab == tab ? primaryColor() : mutedColor());
            text.setGravity(Gravity.CENTER);
            if (currentTab == tab) text.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            item.addView(icon, new LinearLayout.LayoutParams(-1, dp(29)));
            item.addView(text, new LinearLayout.LayoutParams(-1, dp(19)));
            item.setOnClickListener(v -> {
                if (tab == TAB_SETTINGS) {
                    settingsPanel = "";
                    if (currentTab == TAB_SETTINGS && currentPage != null) currentPage.scrollTo(0, 0);
                }
                showTab(tab);
            });
            bottom.addView(item, new LinearLayout.LayoutParams(0, -1, 1));
        }

        automationHost = new FrameLayout(this);
        automationHost.setBackgroundColor(backgroundColor());
        automationHost.setVisibility(View.GONE);

        root.addView(mainShell, 0, new FrameLayout.LayoutParams(-1, -1));
        root.addView(automationHost, 1, new FrameLayout.LayoutParams(-1, -1));
        pendingPreviousMainShell = previousMainShell;
        pendingPreviousAutomationHost = previousAutomationHost;
    }

    private void applySystemBarInsets() {
        if (Build.VERSION.SDK_INT < 21) return;
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
            return insets;
        });
        root.requestApplyInsets();
    }

    private void showTab(int tab) {
        showTab(tab, false);
    }

    private void showTab(int tab, boolean forceShellRebuild) {
        int previousTab = currentTab;
        if (currentPage != null && currentTab >= TAB_HOME && currentTab <= TAB_SETTINGS) {
            tabScrollPositions[currentTab] = currentPage.getScrollY();
        }
        boolean reuseShell = !forceShellRebuild && previousTab == tab && mainShell != null
                && content != null && mainShell.getParent() == root;
        currentPage = null;
        currentTab = tab;
        if (reuseShell) content.removeAllViews();
        else buildShell();
        switch (tab) {
            case TAB_SCHEDULE:
                schedulePage();
                break;
            case TAB_GRADES:
                gradesPage();
                break;
            case TAB_MANAGE:
                managePage();
                break;
            case TAB_SETTINGS:
                settingsPage();
                break;
            default:
                homePage();
                break;
        }
        ScrollView renderedPage = currentPage;
        int scrollPosition = tabScrollPositions[tab];
        if (renderedPage != null && scrollPosition > 0) {
            renderedPage.post(() -> {
                if (currentPage == renderedPage) renderedPage.scrollTo(0, scrollPosition);
            });
        }
        removePendingShellViews();
    }

    private void removePendingShellViews() {
        if (pendingPreviousMainShell != null) root.removeView(pendingPreviousMainShell);
        if (pendingPreviousAutomationHost != null) root.removeView(pendingPreviousAutomationHost);
        pendingPreviousMainShell = null;
        pendingPreviousAutomationHost = null;
    }

    private void homePage() {
        ScrollView scroll = page();
        LinearLayout l = column();
        scroll.addView(l);
        content.addView(scroll);

        l.addView(title("翱翔助手"));
        ScheduleModels.Semester semester = selectedSemester();
        if (semester != null) {
            TextView sub = label(semester.name + "  第 " + currentScheduleWeek(semester) + " 周", 12, mutedColor());
            l.addView(sub);
        }
        LinearLayout overviewHeader = sectionHeader("数据概览");
        Button gradeUpdate = syncButton("成绩", "更新成绩");
        gradeUpdate.setOnClickListener(v -> openPortal("grades", false));
        overviewHeader.addView(gradeUpdate, new LinearLayout.LayoutParams(dp(82), dp(36)));
        addHorizontalGap(overviewHeader, 8);
        Button electricityUpdate = syncButton("电费", "更新电费");
        electricityUpdate.setOnClickListener(v -> openPortal("electricity", false));
        overviewHeader.addView(electricityUpdate, new LinearLayout.LayoutParams(dp(82), dp(36)));
        l.addView(overviewHeader);

        LinearLayout summary = card(panelColor());
        LinearLayout firstMetrics = new LinearLayout(this);
        firstMetrics.addView(metric("GPA", grades.isEmpty() ? "--" : weightedPoint(), "绩点"), new LinearLayout.LayoutParams(0, dp(70), 1));
        firstMetrics.addView(metric("加权成绩", grades.isEmpty() ? "--" : weightedScore(), "分"), new LinearLayout.LayoutParams(0, dp(70), 1));
        summary.addView(firstMetrics);
        View divider = new View(this);
        divider.setBackgroundColor(lineColor());
        summary.addView(divider, new LinearLayout.LayoutParams(-1, dp(1)));
        LinearLayout secondMetrics = new LinearLayout(this);
        secondMetrics.addView(metric("课程", String.valueOf(grades.size()), "门"), new LinearLayout.LayoutParams(0, dp(70), 1));
        secondMetrics.addView(metric("剩余电费", Double.isNaN(electricityBalance) ? "--" : scoreDf.format(electricityBalance), "元"), new LinearLayout.LayoutParams(0, dp(70), 1));
        summary.addView(secondMetrics);
        l.addView(summary);

        l.addView(section("今日课程"));
        List<ScheduleModels.Course> todayCourses = coursesForDate(LocalDate.now(), selectedSemester());
        if (todayCourses.isEmpty()) {
            l.addView(emptyHint("今天没有课程"));
        } else {
            for (ScheduleModels.Course course : todayCourses) l.addView(schedulePreviewRow(course, LocalDate.now()));
        }

    }

    private void schedulePage() {
        scheduleContentView = null;
        scheduleViewport = null;
        scheduleSwipeIncoming = null;
        ScrollView scroll = page();
        LinearLayout l = column();
        l.setPadding(dp(8), dp(18), dp(8), dp(26));
        scroll.addView(l);
        content.addView(scroll);

        LinearLayout header = pageHeader("课表", "一周课程总览");
        header.setPadding(dp(8), 0, dp(8), dp(12));
        l.addView(header);

        if (semesters.isEmpty()) {
            l.addView(emptyHint("还没有课表数据"));
            addGap(l, 10);
            Button importButton = action("导入课表", true);
            importButton.setOnClickListener(v -> openPortal("schedule", false));
            l.addView(importButton, new LinearLayout.LayoutParams(-1, dp(46)));
            return;
        }

        ScheduleModels.Semester semester = selectedSemester();
        if (semester == null) {
            l.addView(emptyHint("请选择学期"));
            return;
        }

        LinearLayout tools = card(panelColor());
        LinearLayout topRow = new LinearLayout(this);
        topRow.setGravity(Gravity.CENTER_VERTICAL);
        Button semesterButton = action(semester.name, false);
        semesterButton.setOnClickListener(v -> showSemesterPicker("选择学期", picked -> {
            selectedSemesterId = picked.id;
            ScheduleStorage.saveSelectedSemester(store, selectedSemesterId);
            scheduleWeekOffset = 0;
            scheduleMonthAnchor = LocalDate.parse(picked.startDate);
            semesterButton.setText(picked.name);
            replaceScheduleContent(picked);
        }));
        topRow.addView(semesterButton, new LinearLayout.LayoutParams(0, dp(42), 1));
        addHorizontalGap(topRow, 10);
        Button monthButton = action(scheduleShowMonth ? "周视图" : "月历视图", false);
        monthButton.setOnClickListener(v -> {
            ScheduleModels.Semester active = selectedSemester();
            scheduleShowMonth = !scheduleShowMonth;
            scheduleMonthAnchor = weekStartForCurrentSelection(active);
            monthButton.setText(scheduleShowMonth ? "周视图" : "月历视图");
            replaceScheduleContent(active);
        });
        topRow.addView(monthButton, new LinearLayout.LayoutParams(dp(96), dp(40)));
        tools.addView(topRow);

        addGap(tools, 8);
        LinearLayout switchRow = new LinearLayout(this);
        switchRow.setGravity(Gravity.CENTER_VERTICAL);
        Button prev = stepButton("‹");
        Button next = stepButton("›");
        Button today = action("本周", false);
        today.setOnClickListener(v -> {
            ScheduleModels.Semester active = selectedSemester();
            scheduleWeekOffset = 0;
            scheduleMonthAnchor = weekStartForCurrentSelection(active);
            replaceScheduleContent(active);
        });
        prev.setOnClickListener(v -> {
            animateSchedulePosition(semester, -1);
        });
        next.setOnClickListener(v -> {
            animateSchedulePosition(semester, 1);
        });
        switchRow.addView(prev, new LinearLayout.LayoutParams(dp(40), dp(38)));
        addHorizontalGap(switchRow, 8);
        switchRow.addView(today, new LinearLayout.LayoutParams(0, dp(38), 1));
        addHorizontalGap(switchRow, 8);
        switchRow.addView(next, new LinearLayout.LayoutParams(dp(40), dp(38)));
        tools.addView(switchRow);
        l.addView(tools);

        addGap(l, 12);
        scheduleViewport = new FrameLayout(this);
        scheduleViewport.setClipChildren(true);
        scheduleViewport.setClipToPadding(true);
        scheduleContentView = scheduleShowMonth ? buildMonthCalendar(semester) : buildWeekSchedule(semester);
        scheduleViewport.addView(scheduleContentView, new FrameLayout.LayoutParams(-1, -2));
        l.addView(scheduleViewport, new LinearLayout.LayoutParams(-1, -2));
    }

    private void gradesPage() {
        ScrollView scroll = page();
        LinearLayout l = column();
        scroll.addView(l);
        content.addView(scroll);

        LinearLayout header = pageHeader("成绩", "共 " + grades.size() + " 门课程");
        ImageView update = iconButton(R.drawable.ic_sync, "手动更新成绩");
        update.setOnClickListener(v -> openPortal("grades", false));
        header.addView(update, new LinearLayout.LayoutParams(dp(40), dp(40)));
        l.addView(header);

        LinearLayout summary = card(panelColor());
        summary.setOrientation(LinearLayout.HORIZONTAL);
        summary.addView(metric("GPA", grades.isEmpty() ? "--" : weightedPoint(), "绩点"), new LinearLayout.LayoutParams(0, dp(76), 1));
        summary.addView(metric("加权成绩", grades.isEmpty() ? "--" : weightedScore(), "分"), new LinearLayout.LayoutParams(0, dp(76), 1));
        summary.addView(metric("课程", String.valueOf(grades.size()), "门"), new LinearLayout.LayoutParams(0, dp(76), 1));
        l.addView(summary);

        l.addView(section("成绩明细"));
        if (grades.isEmpty()) {
            l.addView(emptyHint("还没有成绩"));
        } else {
            LinearLayout gradeList = card(panelColor());
            gradeList.setPadding(dp(14), 0, dp(14), 0);
            for (Grade grade : grades) gradeList.addView(gradeRow(grade));
            l.addView(gradeList);
        }
    }

    private void managePage() {
        ScrollView scroll = page();
        LinearLayout l = column();
        scroll.addView(l);
        content.addView(scroll);

        l.addView(pageHeader("管理", "维护课表与学期数据"));

        l.addView(section("课表同步"));
        LinearLayout syncCard = card(panelColor());
        LinearLayout actionRow = new LinearLayout(this);
        Button importSchedule = action("导入课表", true);
        importSchedule.setOnClickListener(v -> openPortal("schedule", false));
        actionRow.addView(importSchedule, new LinearLayout.LayoutParams(0, dp(46), 1));
        addHorizontalGap(actionRow, 8);
        Button updateSchedule = action("手动更新", false);
        updateSchedule.setOnClickListener(v -> openPortal("schedule", false));
        actionRow.addView(updateSchedule, new LinearLayout.LayoutParams(0, dp(46), 1));
        syncCard.addView(actionRow);
        l.addView(syncCard);

        LinearLayout semesterHeader = sectionHeader("学期");
        Button addSemester = action("新增", false);
        addSemester.setOnClickListener(v -> showSemesterDialog(null));
        semesterHeader.addView(addSemester, new LinearLayout.LayoutParams(dp(76), dp(36)));
        l.addView(semesterHeader);
        if (semesters.isEmpty()) {
            l.addView(emptyHint("还没有学期"));
        } else {
            for (ScheduleModels.Semester semester : semesters) l.addView(semesterCard(semester));
        }

        LinearLayout courseHeader = sectionHeader("课程");
        l.addView(courseHeader);
        ScheduleModels.Semester semester = selectedSemester();
        if (semester == null) {
            l.addView(emptyHint("请选择学期后再管理课程"));
        } else {
            Button picker = action("当前学期：" + semester.name, false);
            picker.setOnClickListener(v -> showSemesterPicker("切换学期", picked -> {
                selectedSemesterId = picked.id;
                ScheduleStorage.saveSelectedSemester(store, selectedSemesterId);
                showTab(TAB_MANAGE);
            }));
            l.addView(picker, new LinearLayout.LayoutParams(-1, dp(42)));
            addGap(l, 8);
            List<ScheduleModels.Course> semesterCourses = sortedCourses(coursesForSemester(semester.id));
            if (semesterCourses.isEmpty()) {
                l.addView(emptyHint("该学期还没有课程"));
            } else {
                for (ScheduleModels.Course course : semesterCourses) l.addView(courseManageCard(course));
            }
        }

    }

    private void settingsPage() {
        ScrollView scroll = page();
        LinearLayout l = column();
        scroll.addView(l);
        content.addView(scroll);

        if (settingsPanel.isEmpty()) {
            l.addView(pageHeader("设置", "账号、同步与显示"));
            addSettingsRoot(l);
            return;
        }

        String title;
        String subtitle;
        switch (settingsPanel) {
            case "account":
                title = "账号";
                subtitle = "统一身份认证账号";
                break;
            case "updates":
                title = "自动更新";
                subtitle = "后台同步频率与运行方式";
                break;
            case "notifications":
                title = "通知";
                subtitle = "数据变化时提醒";
                break;
            case "electricity":
                title = "电费提醒";
                subtitle = "余额不足阈值";
                break;
            case "appearance":
                title = "外观";
                subtitle = "主题与显示模式";
                break;
            case "data":
                title = "数据";
                subtitle = "课表备份与恢复";
                break;
            default:
                title = "关于";
                subtitle = "应用信息与许可";
                break;
        }
        l.addView(settingsPanelHeader(title, subtitle));
        switch (settingsPanel) {
            case "account":
                addAccountSettings(l);
                break;
            case "updates":
                addUpdateSettings(l);
                break;
            case "notifications":
                addNotificationSettings(l);
                break;
            case "electricity":
                addElectricitySettings(l);
                break;
            case "appearance":
                addAppearanceSettings(l);
                break;
            case "data":
                addDataSettings(l);
                break;
            default:
                addAboutSettings(l);
                break;
        }
    }

    private void addSettingsRoot(LinearLayout parent) {
        String[] credentials = readCredentials();
        parent.addView(section("账户与同步"));
        LinearLayout sync = card(panelColor());
        sync.setPadding(dp(14), 0, dp(8), 0);
        addSettingNavigation(sync, "账号", credentials[0].isEmpty() ? "尚未登录" : maskAccount(credentials[0]), "account", true);
        addSettingNavigation(sync, "自动更新", automaticUpdateSummary(), "updates", true);
        addSettingNavigation(sync, "通知", notificationSummary(), "notifications", false);
        parent.addView(sync);

        parent.addView(section("偏好"));
        LinearLayout preferences = card(panelColor());
        preferences.setPadding(dp(14), 0, dp(8), 0);
        addSettingNavigation(preferences, "电费提醒",
                electricityAlertEnabled ? "低于 " + scoreDf.format(electricityAlertThreshold) + " 元时提醒" : "已关闭",
                "electricity", true);
        addSettingNavigation(preferences, "外观", darkMode ? "深色模式" : "浅色模式", "appearance", false);
        parent.addView(preferences);

        parent.addView(section("其他"));
        LinearLayout other = card(panelColor());
        other.setPadding(dp(14), 0, dp(8), 0);
        addSettingNavigation(other, "数据", "导入或导出课表数据", "data", true);
        addSettingNavigation(other, "关于", "翱翔助手 " + appVersion(), "about", false);
        parent.addView(other);
    }

    private void addAccountSettings(LinearLayout parent) {
        String[] credentials = readCredentials();
        LinearLayout account = card(panelColor());
        TextView accountTitle = label(credentials[0].isEmpty() ? "尚未登录" : maskAccount(credentials[0]), 15, textColor());
        accountTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        account.addView(accountTitle);
        addGap(account, 10);
        LinearLayout actions = new LinearLayout(this);
        Button signIn = action(credentials[0].isEmpty() ? "登录" : "更换账号", true);
        signIn.setOnClickListener(v -> showCredentialsDialog(false));
        Button signOut = action("退出登录", false);
        signOut.setEnabled(!credentials[0].isEmpty());
        signOut.setOnClickListener(v -> signOut());
        actions.addView(signIn, new LinearLayout.LayoutParams(0, dp(42), 1));
        addHorizontalGap(actions, 8);
        actions.addView(signOut, new LinearLayout.LayoutParams(0, dp(42), 1));
        account.addView(actions);
        parent.addView(account);
    }

    private void addUpdateSettings(LinearLayout parent) {
        addAutomaticUpdateControls(parent, "成绩", "grades");
        addAutomaticUpdateControls(parent, "课表", "schedule");
        addAutomaticUpdateControls(parent, "电费", "electricity");

        parent.addView(section("运行"));
        LinearLayout runCard = card(panelColor());
        Switch bootSwitch = settingSwitch("开机后恢复自动更新", bootAutoStart);
        bootSwitch.setOnCheckedChangeListener((button, checked) -> {
            bootAutoStart = checked;
            store.edit().putBoolean("boot_auto_start", checked).apply();
        });
        runCard.addView(bootSwitch, new LinearLayout.LayoutParams(-1, dp(48)));
        parent.addView(runCard);
    }

    private void addNotificationSettings(LinearLayout parent) {
        LinearLayout notificationCard = card(panelColor());
        Switch gradeNotice = settingSwitch("成绩有更新时通知", gradeUpdateNotificationEnabled);
        gradeNotice.setOnCheckedChangeListener((button, checked) -> {
            gradeUpdateNotificationEnabled = checked;
            store.edit().putBoolean("grade_update_notification_enabled", checked).apply();
            if (checked) requestNotificationPermission();
            else getSystemService(NotificationManager.class).cancel(1001);
        });
        notificationCard.addView(gradeNotice, new LinearLayout.LayoutParams(-1, dp(48)));
        notificationCard.addView(settingDivider());
        Switch scheduleNotice = settingSwitch("课表有更新时通知", scheduleUpdateNotificationEnabled);
        scheduleNotice.setOnCheckedChangeListener((button, checked) -> {
            scheduleUpdateNotificationEnabled = checked;
            store.edit().putBoolean("schedule_update_notification_enabled", checked).apply();
            if (checked) requestNotificationPermission();
            else getSystemService(NotificationManager.class).cancel(1003);
        });
        notificationCard.addView(scheduleNotice, new LinearLayout.LayoutParams(-1, dp(48)));
        parent.addView(notificationCard);
    }

    private void addElectricitySettings(LinearLayout parent) {
        LinearLayout electricityCard = card(panelColor());
        LinearLayout alertRow = new LinearLayout(this);
        alertRow.setGravity(Gravity.CENTER_VERTICAL);
        Switch alertSwitch = settingSwitch("余额不足提醒", electricityAlertEnabled);
        alertRow.addView(alertSwitch, new LinearLayout.LayoutParams(0, dp(52), 1));
        EditText thresholdInput = new EditText(this);
        thresholdInput.setSingleLine(true);
        thresholdInput.setGravity(Gravity.CENTER);
        thresholdInput.setIncludeFontPadding(false);
        thresholdInput.setTextSize(16);
        thresholdInput.setPadding(dp(8), 0, dp(8), dp(1));
        thresholdInput.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        thresholdInput.setText(scoreDf.format(electricityAlertThreshold));
        thresholdInput.setBackground(border(surfaceColor(), lineColor(), 5));
        alertRow.addView(thresholdInput, new LinearLayout.LayoutParams(dp(84), dp(42)));
        TextView yuan = label("元", 13, mutedColor());
        yuan.setGravity(Gravity.CENTER);
        alertRow.addView(yuan, new LinearLayout.LayoutParams(dp(28), dp(38)));
        electricityCard.addView(alertRow);
        alertSwitch.setOnCheckedChangeListener((button, checked) -> {
            electricityAlertEnabled = checked;
            store.edit().putBoolean("electricity_alert_enabled", checked).apply();
            if (checked) requestNotificationPermission();
            else store.edit().putBoolean("electricity_alert_active", false).apply();
        });
        LinearLayout electricityActions = new LinearLayout(this);
        Button saveThreshold = action("保存余量", false);
        saveThreshold.setOnClickListener(v -> saveElectricityThreshold(thresholdInput));
        Button updateElectricity = action("立即更新", false);
        updateElectricity.setOnClickListener(v -> openPortal("electricity", false));
        electricityActions.addView(saveThreshold, new LinearLayout.LayoutParams(0, dp(40), 1));
        addHorizontalGap(electricityActions, 8);
        electricityActions.addView(updateElectricity, new LinearLayout.LayoutParams(0, dp(40), 1));
        electricityCard.addView(electricityActions);
        parent.addView(electricityCard);
    }

    private void addAppearanceSettings(LinearLayout parent) {
        LinearLayout appearance = card(panelColor());
        Switch darkSwitch = settingSwitch("深色模式", darkMode);
        darkSwitch.setOnCheckedChangeListener((button, checked) -> {
            darkMode = checked;
            saveTheme();
            applyWindowTheme();
            showTab(TAB_SETTINGS, true);
        });
        appearance.addView(darkSwitch, new LinearLayout.LayoutParams(-1, dp(48)));
        appearance.addView(settingDivider());
        addGap(appearance, 10);
        LinearLayout swatchRow = new LinearLayout(this);
        swatchRow.setGravity(Gravity.CENTER_VERTICAL);
        for (String color : ScheduleModels.PRESET_COLORS) {
            View swatch = colorSwatch(color, themeColor.equals(color));
            swatch.setOnClickListener(v -> {
                themeColor = color;
                saveTheme();
                applyWindowTheme();
                showTab(TAB_SETTINGS, true);
            });
            swatchRow.addView(swatch);
            addHorizontalGap(swatchRow, 8);
        }
        appearance.addView(swatchRow);
        parent.addView(appearance);
    }

    private void addDataSettings(LinearLayout parent) {
        LinearLayout dataCard = card(panelColor());
        LinearLayout dataActions = new LinearLayout(this);
        Button export = action("导出课表数据", false);
        export.setOnClickListener(v -> exportBackup());
        Button importData = action("导入课表数据", false);
        importData.setOnClickListener(v -> requestImportBackup());
        dataActions.addView(export, new LinearLayout.LayoutParams(0, dp(42), 1));
        addHorizontalGap(dataActions, 8);
        dataActions.addView(importData, new LinearLayout.LayoutParams(0, dp(42), 1));
        dataCard.addView(dataActions);
        parent.addView(dataCard);
    }

    private void addAboutSettings(LinearLayout parent) {
        LinearLayout identity = card(panelColor());
        TextView name = label("翱翔助手", 20, textColor());
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        identity.addView(name);
        identity.addView(label("版本 " + appVersion(), 13, mutedColor()));
        addGap(identity, 12);
        identity.addView(label("包名", 11, mutedColor()));
        identity.addView(label(getPackageName(), 13, textColor()));
        parent.addView(identity);

        parent.addView(section("项目"));
        LinearLayout project = card(panelColor());
        TextView repository = label("GitHub 仓库", 14, textColor());
        repository.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        project.addView(repository);
        project.addView(label("Lorcas-Zephyr/aoxiang-assistant", 12, mutedColor()));
        addGap(project, 10);
        Button openRepository = action("打开仓库", false);
        openRepository.setOnClickListener(v -> startActivity(new Intent(Intent.ACTION_VIEW,
                Uri.parse("https://github.com/Lorcas-Zephyr/aoxiang-assistant"))));
        project.addView(openRepository, new LinearLayout.LayoutParams(-1, dp(42)));
        parent.addView(project);

        parent.addView(section("说明"));
        LinearLayout notice = card(panelColor());
        notice.addView(label("本应用不是西北工业大学官方应用。", 13, textColor()));
        addGap(notice, 8);
        notice.addView(label("课表功能经许可参考 Whippap/soaring-schedule-remake。", 12, mutedColor()));
        parent.addView(notice);
    }

    private View buildWeekSchedule(ScheduleModels.Semester semester) {
        SwipeLayout wrap = new SwipeLayout(this, semester, false);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setBackground(bg(surfaceColor(), 5));
        wrap.setPadding(dp(4), dp(10), dp(4), dp(10));

        int week = currentScheduleWeek(semester);
        LocalDate weekStart = weekStartForSelection(semester, week);
        TextView caption = label(semester.name + " · 第" + week + "周", 14, textColor());
        caption.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        wrap.addView(caption);
        addGap(wrap, 8);

        LinearLayout board = new LinearLayout(this);
        board.setOrientation(LinearLayout.VERTICAL);

        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.addView(dayHeader("", ""), new LinearLayout.LayoutParams(dp(44), dp(48)));
        for (int day = 1; day <= 7; day++) {
            LocalDate date = weekStart.plusDays(day - 1);
            head.addView(dayHeader(dayLabel(day).substring(1), monthDayFormatter.format(date)),
                    new LinearLayout.LayoutParams(0, dp(48), 1));
        }
        board.addView(head);

        LinearLayout body = new LinearLayout(this);
        body.setGravity(Gravity.TOP);
        LinearLayout timeColumn = new LinearLayout(this);
        timeColumn.setOrientation(LinearLayout.VERTICAL);
        for (int section = 1; section <= semester.sectionCount; section++) {
            timeColumn.addView(sectionLabel(semester, section),
                    new LinearLayout.LayoutParams(-1, dp(SCHEDULE_SECTION_HEIGHT_DP)));
        }
        body.addView(timeColumn, new LinearLayout.LayoutParams(dp(44), -2));

        List<ScheduleModels.Course> weekCourses = coursesForWeek(semester, week);
        for (int day = 1; day <= 7; day++) {
            LinearLayout dayColumn = new LinearLayout(this);
            dayColumn.setOrientation(LinearLayout.VERTICAL);
            int section = 1;
            while (section <= semester.sectionCount) {
                ScheduleModels.Course starting = courseStartingAt(weekCourses, week, day, section);
                if (starting == null) {
                    dayColumn.addView(emptyCell(), new LinearLayout.LayoutParams(-1, dp(SCHEDULE_SECTION_HEIGHT_DP)));
                    section++;
                } else {
                    int span = spanForCourse(starting, week, day, section);
                    View block = courseBlock(starting, span, week, day, section);
                    dayColumn.addView(block,
                            new LinearLayout.LayoutParams(-1, dp(SCHEDULE_SECTION_HEIGHT_DP * span)));
                    section += span;
                }
            }
            body.addView(dayColumn, new LinearLayout.LayoutParams(0, -2, 1));
        }
        board.addView(body);
        wrap.addView(board, new LinearLayout.LayoutParams(-1, -2));
        return wrap;
    }

    private View buildMonthCalendar(ScheduleModels.Semester semester) {
        LocalDate monthStart = normalizedScheduleMonthStart(semester);
        LocalDate gridStart = monthStart.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));

        SwipeLayout wrap = new SwipeLayout(this, semester, true);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setBackground(bg(surfaceColor(), 5));
        wrap.setPadding(dp(12), dp(12), dp(12), dp(12));

        TextView title = label(monthStart.getYear() + "年" + monthStart.getMonthValue() + "月", 15, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        wrap.addView(title);
        addGap(wrap, 8);

        LinearLayout weekHeader = new LinearLayout(this);
        String[] names = {"一", "二", "三", "四", "五", "六", "日"};
        for (String name : names) {
            TextView day = label(name, 12, mutedColor());
            day.setGravity(Gravity.CENTER);
            weekHeader.addView(day, new LinearLayout.LayoutParams(0, dp(24), 1));
        }
        wrap.addView(weekHeader);

        LocalDate cursor = gridStart;
        for (int row = 0; row < 6; row++) {
            LinearLayout line = new LinearLayout(this);
            for (int col = 0; col < 7; col++) {
                final LocalDate date = cursor;
                LinearLayout cell = new LinearLayout(this);
                cell.setOrientation(LinearLayout.VERTICAL);
                cell.setPadding(dp(6), dp(6), dp(6), dp(6));
                cell.setBackground(border(backgroundColor(), lineColor()));
                TextView day = label(String.valueOf(date.getDayOfMonth()), 12, date.getMonthValue() == monthStart.getMonthValue() ? textColor() : mutedColor());
                day.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                cell.addView(day);
                List<ScheduleModels.Course> daily = coursesForDate(date, semester);
                if (!daily.isEmpty()) {
                    LinearLayout dots = new LinearLayout(this);
                    dots.setOrientation(LinearLayout.HORIZONTAL);
                    dots.setGravity(Gravity.CENTER_VERTICAL);
                    dots.setPadding(0, dp(8), 0, 0);
                    for (ScheduleModels.Course course : sortedCourses(daily)) {
                        View dot = new View(this);
                        dot.setContentDescription(course.name);
                        dot.setBackground(bg(parseColorSafe(course.color, primaryColor()), 5));
                        LinearLayout.LayoutParams dotParams = new LinearLayout.LayoutParams(dp(9), dp(9));
                        dotParams.setMarginEnd(dp(4));
                        dots.addView(dot, dotParams);
                    }
                    cell.addView(dots, new LinearLayout.LayoutParams(-1, dp(18)));
                }
                cell.setOnClickListener(v -> showDailyCoursesDialog(date, daily));
                line.addView(cell, new LinearLayout.LayoutParams(0, dp(86), 1));
                cursor = cursor.plusDays(1);
            }
            wrap.addView(line);
        }
        return wrap;
    }

    private void prepareScheduleSwipe(SwipeLayout source, float dx) {
        if (scheduleSwipeAnimating || scheduleSwipeIncoming != null || source != scheduleContentView
                || scheduleViewport == null) return;
        int width = source.getWidth();
        if (width <= 0) width = getResources().getDisplayMetrics().widthPixels;
        scheduleSwipeWidth = width;
        scheduleSwipeDirection = dx < 0 ? 1 : -1;
        if (!canMoveSchedule(source.semester, source.monthView, scheduleSwipeDirection)) return;

        int previousWeekOffset = scheduleWeekOffset;
        LocalDate previousMonthAnchor = scheduleMonthAnchor;
        if (source.monthView) {
            if (scheduleMonthAnchor == null) scheduleMonthAnchor = weekStartForCurrentSelection(source.semester);
            scheduleMonthAnchor = scheduleMonthAnchor.plusMonths(scheduleSwipeDirection > 0 ? 1 : -1);
        } else {
            scheduleWeekOffset += scheduleSwipeDirection;
        }
        View incoming = source.monthView ? buildMonthCalendar(source.semester) : buildWeekSchedule(source.semester);
        scheduleWeekOffset = previousWeekOffset;
        scheduleMonthAnchor = previousMonthAnchor;

        scheduleSwipeIncoming = incoming;
        scheduleViewport.addView(incoming, new FrameLayout.LayoutParams(-1, -2));
        float clampedDx = clampSwipeTranslation(dx);
        source.setTranslationX(clampedDx);
        incoming.setTranslationX(scheduleSwipeDirection * scheduleSwipeWidth + clampedDx);
    }

    private void animateSchedulePosition(ScheduleModels.Semester semester, int direction) {
        if (!(scheduleContentView instanceof SwipeLayout) || scheduleSwipeAnimating) return;
        SwipeLayout source = (SwipeLayout) scheduleContentView;
        float initialDx = direction > 0 ? -dp(100) : dp(100);
        prepareScheduleSwipe(source, initialDx);
        if (scheduleSwipeIncoming != null) finishScheduleSwipe(source, initialDx);
    }

    private void replaceScheduleContent(ScheduleModels.Semester semester) {
        if (semester == null || scheduleViewport == null || scheduleSwipeAnimating) return;
        View outgoing = scheduleContentView;
        View incoming = scheduleShowMonth ? buildMonthCalendar(semester) : buildWeekSchedule(semester);
        scheduleViewport.addView(incoming, 0, new FrameLayout.LayoutParams(-1, -2));
        if (outgoing != null) scheduleViewport.removeView(outgoing);
        scheduleContentView = incoming;
        scheduleSwipeIncoming = null;
    }

    private void updateScheduleSwipe(SwipeLayout source, float dx) {
        if (scheduleSwipeIncoming == null) {
            prepareScheduleSwipe(source, dx);
        }
        if (scheduleSwipeIncoming != null) {
            float clampedDx = clampSwipeTranslation(dx);
            source.setTranslationX(clampedDx);
            scheduleSwipeIncoming.setTranslationX(scheduleSwipeDirection * scheduleSwipeWidth + clampedDx);
        }
    }

    private void finishScheduleSwipe(SwipeLayout source, float dx) {
        if (scheduleSwipeIncoming == null) {
            source.animate().translationX(0f).setDuration(120).start();
            return;
        }
        float clampedDx = clampSwipeTranslation(dx);
        boolean sameDirection = (scheduleSwipeDirection > 0 && clampedDx < 0)
                || (scheduleSwipeDirection < 0 && clampedDx > 0);
        // Keep the gesture threshold usable on wide screens while requiring a deliberate drag.
        int commitDistance = Math.min(dp(96), Math.max(dp(72), scheduleSwipeWidth / 4));
        if (!sameDirection || Math.abs(clampedDx) < commitDistance) {
            cancelScheduleSwipe(source);
            return;
        }
        final int direction = scheduleSwipeDirection;
        final int width = scheduleSwipeWidth;
        final View incoming = scheduleSwipeIncoming;
        scheduleSwipeAnimating = true;
        source.animate()
                .translationX(-direction * width)
                .setDuration(180)
                .setInterpolator(new DecelerateInterpolator())
                .withEndAction(() -> {
                    commitSchedulePosition(source.semester, source.monthView, direction);
                    if (scheduleViewport != null) {
                        scheduleViewport.removeView(source);
                        incoming.setTranslationX(0f);
                        scheduleContentView = incoming;
                    }
                    scheduleSwipeIncoming = null;
                    scheduleSwipeAnimating = false;
                })
                .start();
        incoming.animate()
                .translationX(0f)
                .setDuration(180)
                .setInterpolator(new DecelerateInterpolator())
                .start();
    }

    private void cancelScheduleSwipe(SwipeLayout source) {
        if (scheduleSwipeIncoming == null) {
            source.animate().translationX(0f).setDuration(120).start();
            return;
        }
        final View incoming = scheduleSwipeIncoming;
        final int direction = scheduleSwipeDirection;
        scheduleSwipeAnimating = true;
        source.animate()
                .translationX(0f)
                .setDuration(150)
                .setInterpolator(new DecelerateInterpolator())
                .withEndAction(() -> {
                    if (scheduleViewport != null) scheduleViewport.removeView(incoming);
                    scheduleSwipeIncoming = null;
                    scheduleSwipeAnimating = false;
                })
                .start();
        incoming.animate()
                .translationX(direction * scheduleSwipeWidth)
                .setDuration(150)
                .setInterpolator(new DecelerateInterpolator())
                .start();
    }

    private float clampSwipeTranslation(float dx) {
        float width = Math.max(1, scheduleSwipeWidth);
        return Math.max(-width, Math.min(width, dx));
    }

    private void commitSchedulePosition(ScheduleModels.Semester semester, boolean monthView, int direction) {
        if (!canMoveSchedule(semester, monthView, direction)) return;
        if (monthView) {
            scheduleMonthAnchor = normalizedScheduleMonthStart(semester).plusMonths(direction > 0 ? 1 : -1);
        } else {
            int targetWeek = currentScheduleWeek(semester) + (direction > 0 ? 1 : -1);
            scheduleWeekOffset = targetWeek - baseScheduleWeek(semester);
        }
    }

    private boolean canMoveSchedule(ScheduleModels.Semester semester, boolean monthView, int direction) {
        if (semester == null || direction == 0) return false;
        if (!monthView) {
            int week = currentScheduleWeek(semester);
            return direction > 0 ? week < Math.max(1, semester.weekCount) : week > 1;
        }
        LocalDate currentMonth = normalizedScheduleMonthStart(semester);
        LocalDate firstMonth = semesterFirstMonth(semester);
        LocalDate lastMonth = semesterLastMonth(semester);
        return direction > 0 ? currentMonth.isBefore(lastMonth) : currentMonth.isAfter(firstMonth);
    }

    private LocalDate normalizedScheduleMonthStart(ScheduleModels.Semester semester) {
        LocalDate firstMonth = semesterFirstMonth(semester);
        LocalDate lastMonth = semesterLastMonth(semester);
        LocalDate month = scheduleMonthAnchor == null
                ? weekStartForCurrentSelection(semester).withDayOfMonth(1)
                : scheduleMonthAnchor.withDayOfMonth(1);
        if (month.isBefore(firstMonth)) month = firstMonth;
        if (month.isAfter(lastMonth)) month = lastMonth;
        scheduleMonthAnchor = month;
        return month;
    }

    private LocalDate semesterFirstMonth(ScheduleModels.Semester semester) {
        return LocalDate.parse(semester.startDate).withDayOfMonth(1);
    }

    private LocalDate semesterLastMonth(ScheduleModels.Semester semester) {
        return LocalDate.parse(semester.startDate)
                .plusWeeks(Math.max(1, semester.weekCount) - 1L)
                .plusDays(6)
                .withDayOfMonth(1);
    }

    private void showDailyCoursesDialog(LocalDate date, List<ScheduleModels.Course> daily) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(20), dp(12), dp(20), dp(12));
        if (daily.isEmpty()) {
            box.addView(label("没有课程", 14, mutedColor()));
        } else {
            for (ScheduleModels.Course course : sortedCourses(daily)) {
                TextView item = label(course.name + "\n" + ScheduleUtils.formatCourseTime(course), 13, textColor());
                item.setPadding(0, dp(8), 0, dp(8));
                box.addView(item);
            }
        }
        new AlertDialog.Builder(this)
                .setTitle(date.toString())
                .setView(box)
                .setPositiveButton("关闭", null)
                .show();
    }

    /** Handles only clear horizontal gestures, leaving taps and vertical scrolling to children. */
    private class SwipeLayout extends LinearLayout {
        private final ScheduleModels.Semester semester;
        private final boolean monthView;
        private final int touchSlop;
        private float downX;
        private float downY;
        private boolean interceptingSwipe;

        SwipeLayout(Context context, ScheduleModels.Semester semester, boolean monthView) {
            super(context);
            this.semester = semester;
            this.monthView = monthView;
            this.touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
            setClickable(true);
        }

        @Override
        public boolean dispatchTouchEvent(MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = event.getRawX();
                    downY = event.getRawY();
                    interceptingSwipe = false;
                    break;
                case MotionEvent.ACTION_MOVE:
                    if (!interceptingSwipe) {
                        float dx = event.getRawX() - downX;
                        float dy = event.getRawY() - downY;
                        if (Math.abs(dx) >= touchSlop && Math.abs(dx) > Math.abs(dy) * 1.08f) {
                            interceptingSwipe = true;
                            getParent().requestDisallowInterceptTouchEvent(true);
                            prepareScheduleSwipe(this, dx);
                        }
                    }
                    if (interceptingSwipe) {
                        updateScheduleSwipe(this, event.getRawX() - downX);
                        return true;
                    }
                    break;
                case MotionEvent.ACTION_UP:
                    if (interceptingSwipe) {
                        float dx = event.getRawX() - downX;
                        interceptingSwipe = false;
                        getParent().requestDisallowInterceptTouchEvent(false);
                        finishScheduleSwipe(this, dx);
                        return true;
                    }
                    break;
                case MotionEvent.ACTION_CANCEL:
                    if (interceptingSwipe) {
                        interceptingSwipe = false;
                        getParent().requestDisallowInterceptTouchEvent(false);
                        cancelScheduleSwipe(this);
                        return true;
                    }
                    break;
                default:
                    break;
            }
            if (interceptingSwipe) return true;
            return super.dispatchTouchEvent(event);
        }
    }

    private void showSemesterPicker(String title, SemesterCallback callback) {
        if (semesters.isEmpty()) {
            Toast.makeText(this, "还没有学期", Toast.LENGTH_SHORT).show();
            return;
        }
        String[] names = new String[semesters.size()];
        for (int i = 0; i < semesters.size(); i++) names[i] = semesters.get(i).name;
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setItems(names, (dialog, which) -> callback.onPick(semesters.get(which)))
                .show();
    }

    private void showSemesterDialog(ScheduleModels.Semester editing) {
        final boolean isEdit = editing != null;
        final ScheduleModels.Semester base = editing == null ? defaultEditableSemester() : editing;
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(24), 0, dp(24), 0);

        EditText nameInput = new EditText(this);
        nameInput.setHint("学期名称");
        nameInput.setText(base.name);
        form.addView(nameInput, new LinearLayout.LayoutParams(-1, dp(58)));

        String normalizedBaseStart = normalizeSemesterStartDate(base.startDate);
        Button startDateButton = action(normalizedBaseStart, false);
        form.addView(startDateButton, new LinearLayout.LayoutParams(-1, dp(46)));
        addGap(form, 8);

        EditText weekCountInput = new EditText(this);
        weekCountInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        weekCountInput.setHint("周数");
        weekCountInput.setText(String.valueOf(base.weekCount));
        form.addView(weekCountInput, new LinearLayout.LayoutParams(-1, dp(58)));

        EditText sectionCountInput = new EditText(this);
        sectionCountInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        sectionCountInput.setHint("每天节次数");
        sectionCountInput.setText(String.valueOf(base.sectionCount));
        form.addView(sectionCountInput, new LinearLayout.LayoutParams(-1, dp(58)));

        final String[] chosenDate = {normalizedBaseStart};
        startDateButton.setOnClickListener(v -> showDatePicker(chosenDate[0], value -> {
            chosenDate[0] = normalizeSemesterStartDate(value);
            startDateButton.setText(chosenDate[0]);
        }));

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(isEdit ? "编辑学期" : "新增学期")
                .setView(form)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", null)
                .create();
        dialog.setOnShowListener(view -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String name = nameInput.getText().toString().trim();
            int weekCount = parseInt(weekCountInput.getText().toString().trim(), 20);
            int sectionCount = parseInt(sectionCountInput.getText().toString().trim(), 13);
            if (name.isEmpty()) {
                Toast.makeText(this, "请输入学期名称", Toast.LENGTH_SHORT).show();
                return;
            }
            chosenDate[0] = normalizeSemesterStartDate(chosenDate[0]);
            ScheduleModels.Semester semester = new ScheduleModels.Semester(
                    isEdit ? base.id : "semester-" + System.currentTimeMillis(),
                    name,
                    chosenDate[0],
                    LocalDate.parse(chosenDate[0]).plusWeeks(Math.max(1, weekCount)).minusDays(1).toString(),
                    Math.max(1, weekCount),
                    Math.max(1, sectionCount),
                    ScheduleModels.buildDefaultSectionTimes(Math.max(1, sectionCount))
            );
            if (hasSemesterOverlap(semester, isEdit ? base.id : null)) {
                Toast.makeText(this, "学期时间范围与现有学期重叠", Toast.LENGTH_LONG).show();
                return;
            }
            saveSemester(semester, isEdit);
            dialog.dismiss();
            showTab(TAB_MANAGE);
        }));
        dialog.show();
    }

    private void showCourseDialog(ScheduleModels.Course editing) {
        ScheduleModels.Semester semester = selectedSemester();
        if (semester == null) {
            Toast.makeText(this, "请先新增或选择学期", Toast.LENGTH_SHORT).show();
            return;
        }
        final boolean isEdit = editing != null;
        final ScheduleModels.Course base = editing == null ? defaultEditableCourse(semester.id) : editing;

        ScrollView scroll = new ScrollView(this);
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(24), 0, dp(24), 0);
        scroll.addView(form);

        EditText nameInput = field(form, "课程名称", base.name);
        EditText codeInput = field(form, "课程代码", base.code);
        EditText teacherInput = field(form, "教师", base.teacher);
        EditText locationInput = field(form, "地点", base.location);
        EditText assessmentInput = field(form, "考核方式", base.assessmentMethod == null ? "" : base.assessmentMethod.label);
        EditText notesInput = field(form, "备注", base.notes);
        EditText slotInput = field(form, "上课时间（每行一条）", joinSlots(base.timeSlots));
        slotInput.setHint("例如：1-16周 周一 第1-2节");
        slotInput.setMinLines(4);
        slotInput.setGravity(Gravity.TOP);

        TextView colorTitle = label("课程颜色", 14, textColor());
        colorTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        form.addView(colorTitle);
        addGap(form, 8);
        LinearLayout swatches = new LinearLayout(this);
        final String[] chosenColor = {base.color == null ? ScheduleModels.PRESET_COLORS.get(0) : base.color};
        for (String value : ScheduleModels.PRESET_COLORS) {
            View swatch = colorSwatch(value, value.equals(chosenColor[0]));
            swatch.setOnClickListener(v -> {
                chosenColor[0] = value;
                showCourseDialogRefresh(form, swatches, chosenColor[0]);
            });
            swatches.addView(swatch);
            addHorizontalGap(swatches, 8);
        }
        form.addView(swatches);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(isEdit ? "编辑课程" : "新增课程")
                .setView(scroll)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", null)
                .create();
        dialog.setOnShowListener(view -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String name = nameInput.getText().toString().trim();
            if (name.isEmpty()) {
                Toast.makeText(this, "请输入课程名称", Toast.LENGTH_SHORT).show();
                return;
            }
            List<ScheduleModels.TimeSlot> timeSlots = parseManualSlots(slotInput.getText().toString());
            if (timeSlots.isEmpty()) {
                Toast.makeText(this, "请至少输入一条上课时间", Toast.LENGTH_LONG).show();
                return;
            }
            ScheduleModels.Course course = new ScheduleModels.Course(
                    isEdit ? base.id : "course-" + System.currentTimeMillis(),
                    name,
                    base.semesterId,
                    timeSlots
            );
            course.code = emptyToNull(codeInput.getText().toString());
            course.credits = base.credits;
            course.teacher = emptyToNull(teacherInput.getText().toString());
            course.location = emptyToNull(locationInput.getText().toString());
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                slot.teacher = course.teacher;
                slot.location = course.location;
            }
            course.assessmentMethod = ScheduleModels.AssessmentMethod.fromLabel(assessmentInput.getText().toString().trim());
            course.notes = emptyToNull(notesInput.getText().toString());
            course.color = chosenColor[0];
            String conflict = ScheduleUtils.findConflictDescription(course, courses, isEdit ? base.id : null);
            if (conflict != null) {
                Toast.makeText(this, conflict, Toast.LENGTH_LONG).show();
                return;
            }
            saveCourse(course, isEdit);
            dialog.dismiss();
            showTab(TAB_MANAGE);
        }));
        dialog.show();
    }

    private void showCourseDetailDialog(ScheduleModels.Course course) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.addView(detailRow("时间", ScheduleUtils.formatCourseTime(course)));
        box.addView(detailRow("地点", course.location == null ? "--" : course.location));
        box.addView(detailRow("教师", course.teacher == null ? "--" : course.teacher));
        box.addView(detailRow("代码", course.code == null ? "--" : course.code));
        if (course.assessmentMethod != null) box.addView(detailRow("考核", course.assessmentMethod.label));
        if (course.notes != null) box.addView(detailRow("备注", course.notes));
        showCoursePanel("课程详情", course.name, box, dp(680));
    }

    private void showCourseMeetingDetailDialog(ScheduleModels.Course course, ScheduleModels.TimeSlot slot) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        String location = slot != null && slot.location != null ? slot.location : course.location;
        String teacher = slot != null && slot.teacher != null ? slot.teacher : course.teacher;
        box.addView(detailRow("地点", location == null ? "--" : location));
        box.addView(detailRow("教师", teacher == null ? "--" : teacher));
        showCoursePanel("本节课", course.name, box, dp(380));
    }

    private void showCoursePanel(String eyebrowText, String heading, View details, int preferredHeight) {
        Dialog dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setPadding(dp(22), dp(20), dp(22), dp(16));
        shell.setBackground(bg(panelColor(), 16));
        applyRoundedOutline(shell, 16, 10);

        TextView eyebrow = label(eyebrowText, 11, primaryColor());
        eyebrow.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(eyebrow, new LinearLayout.LayoutParams(-1, dp(24)));

        TextView title = label(heading, 21, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setMaxLines(2);
        shell.addView(title, new LinearLayout.LayoutParams(-1, -2));

        View accent = new View(this);
        accent.setBackground(bg(primaryColor(), 2));
        LinearLayout.LayoutParams accentParams = new LinearLayout.LayoutParams(dp(42), dp(3));
        accentParams.topMargin = dp(12);
        accentParams.bottomMargin = dp(8);
        shell.addView(accent, accentParams);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        scroll.setPadding(0, dp(2), 0, dp(2));
        scroll.addView(details);
        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        Button close = action("关闭", true);
        close.setOnClickListener(v -> dialog.dismiss());
        LinearLayout.LayoutParams closeParams = new LinearLayout.LayoutParams(-1, dp(44));
        closeParams.topMargin = dp(10);
        shell.addView(close, closeParams);

        dialog.setContentView(shell);
        dialog.setCanceledOnTouchOutside(true);
        configureCustomDialogWindow(dialog, preferredHeight);
        dialog.show();
        configureCustomDialogWindow(dialog, preferredHeight);
    }

    private void configureCustomDialogWindow(Dialog dialog, int preferredHeight) {
        Window window = dialog.getWindow();
        if (window == null) return;
        int width = getResources().getDisplayMetrics().widthPixels;
        int height = getResources().getDisplayMetrics().heightPixels;
        int dialogWidth = Math.min(width - dp(32), dp(440));
        int dialogHeight = Math.min(height - dp(96), preferredHeight);
        window.setGravity(Gravity.CENTER);
        window.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        WindowManager.LayoutParams params = window.getAttributes();
        params.width = dialogWidth;
        params.height = dialogHeight;
        params.dimAmount = 0.34f;
        window.setAttributes(params);
        window.setLayout(dialogWidth, dialogHeight);
    }

    private View detailRow(String heading, String value) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, dp(8), 0, dp(8));
        TextView caption = label(heading, 11, mutedColor());
        caption.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        row.addView(caption, new LinearLayout.LayoutParams(-1, dp(22)));
        TextView content = label(value == null || value.isEmpty() ? "--" : value, 14, textColor());
        content.setGravity(Gravity.TOP | Gravity.START);
        content.setLineSpacing(0, 1.08f);
        row.addView(content, new LinearLayout.LayoutParams(-1, -2));
        View divider = new View(this);
        divider.setBackgroundColor(lineColor());
        LinearLayout.LayoutParams dividerParams = new LinearLayout.LayoutParams(-1, dp(1));
        dividerParams.topMargin = dp(8);
        row.addView(divider, dividerParams);
        return row;
    }

    private void styleDialogInput(EditText input) {
        input.setTextColor(textColor());
        input.setHintTextColor(mutedColor());
        input.setPadding(dp(14), 0, dp(14), 0);
        input.setBackground(border(surfaceColor(), lineColor(), 8));
    }

    private void showDatePicker(String currentValue, java.util.function.Consumer<String> consumer) {
        LocalDate base = currentValue == null || currentValue.isEmpty() ? LocalDate.now() : LocalDate.parse(currentValue);
        DatePickerDialog picker = new DatePickerDialog(this, (view, year, month, day) ->
                consumer.accept(LocalDate.of(year, month + 1, day).toString()),
                base.getYear(), base.getMonthValue() - 1, base.getDayOfMonth());
        picker.show();
    }

    private void showCredentialsDialog(boolean invalid) {
        if (loginPromptVisible) return;
        loginPromptVisible = true;
        bringAppToFront();
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(0, 0, 0, 0);
        String[] saved = readCredentials();
        EditText username = new EditText(this);
        username.setHint("学号");
        username.setSingleLine(true);
        username.setInputType(InputType.TYPE_CLASS_TEXT);
        username.setText(saved[0]);
        styleDialogInput(username);
        form.addView(username, new LinearLayout.LayoutParams(-1, dp(58)));
        addGap(form, 10);
        EditText password = new EditText(this);
        password.setHint("统一认证密码");
        password.setSingleLine(true);
        password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        password.setText(saved[1]);
        styleDialogInput(password);
        form.addView(password, new LinearLayout.LayoutParams(-1, dp(58)));
        loginDialog = new Dialog(this);
        Dialog dialog = loginDialog;
        showLoginActionPanel(dialog, "账号", "登录教务系统",
                invalid ? "账号或密码不正确，请重新确认" : "使用统一身份认证登录",
                form, "保存", () -> {
                String account = username.getText().toString().trim();
                String secret = password.getText().toString();
                if (account.isEmpty() || secret.isEmpty()) {
                    Toast.makeText(this, "请输入账号和密码", Toast.LENGTH_SHORT).show();
                    return;
                }
                saveCredentials(account, secret);
                scheduleAllAutomaticUpdates(500L);
                syncBackgroundService();
                pendingSmsCode = "";
                loginPromptVisible = false;
                loginDialog.dismiss();
                Toast.makeText(this, "账号已保存", Toast.LENGTH_SHORT).show();
            }, () -> {
            loginPromptVisible = false;
            if (automationWeb != null) cancelAutomation();
        });
    }

    private void showSmsDialog() {
        if (loginPromptVisible) return;
        loginPromptVisible = true;
        bringAppToFront();
        EditText code = new EditText(this);
        code.setHint("短信验证码");
        code.setInputType(InputType.TYPE_CLASS_NUMBER);
        code.setSingleLine(true);
        styleDialogInput(code);
        loginDialog = new Dialog(this);
        Dialog dialog = loginDialog;
        showLoginActionPanel(dialog, "安全验证", "输入短信验证码",
                "验证码已由校方认证系统发送，请输入后继续。",
                code, "验证", () -> {
                String value = code.getText().toString().trim();
                if (value.length() < 4) {
                    Toast.makeText(this, "请输入有效验证码", Toast.LENGTH_SHORT).show();
                    return;
                }
                pendingSmsCode = value;
                loginPromptVisible = false;
                loginDialog.dismiss();
            }, () -> {
            loginPromptVisible = false;
            cancelAutomation();
        });
    }

    private void showLoginActionPanel(Dialog dialog, String eyebrowText, String heading, String subtitle,
                                      View content, String positiveText, Runnable positiveAction,
                                      Runnable cancelAction) {
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setPadding(dp(22), dp(20), dp(22), dp(16));
        shell.setBackground(bg(panelColor(), 16));
        applyRoundedOutline(shell, 16, 10);

        TextView eyebrow = label(eyebrowText, 11, primaryColor());
        eyebrow.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(eyebrow, new LinearLayout.LayoutParams(-1, dp(24)));
        TextView title = label(heading, 21, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(title, new LinearLayout.LayoutParams(-1, -2));
        if (subtitle != null && !subtitle.isEmpty()) {
            TextView hint = label(subtitle, 12, mutedColor());
            hint.setPadding(0, dp(6), 0, dp(4));
            shell.addView(hint, new LinearLayout.LayoutParams(-1, -2));
        }
        View accent = new View(this);
        accent.setBackground(bg(primaryColor(), 2));
        LinearLayout.LayoutParams accentParams = new LinearLayout.LayoutParams(dp(42), dp(3));
        accentParams.topMargin = dp(8);
        accentParams.bottomMargin = dp(8);
        shell.addView(accent, accentParams);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.addView(content);
        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        LinearLayout actions = new LinearLayout(this);
        Button cancel = action("取消", false);
        Button confirm = action(positiveText, true);
        actions.addView(cancel, new LinearLayout.LayoutParams(0, dp(44), 1));
        addHorizontalGap(actions, 10);
        actions.addView(confirm, new LinearLayout.LayoutParams(0, dp(44), 1));
        LinearLayout.LayoutParams actionParams = new LinearLayout.LayoutParams(-1, dp(44));
        actionParams.topMargin = dp(12);
        shell.addView(actions, actionParams);

        cancel.setOnClickListener(v -> {
            cancelAction.run();
            dialog.dismiss();
        });
        confirm.setOnClickListener(v -> positiveAction.run());
        dialog.setContentView(shell);
        dialog.setCanceledOnTouchOutside(false);
        dialog.setOnCancelListener(ignored -> cancelAction.run());
        configureCustomDialogWindow(dialog, dp(430));
        dialog.show();
        configureCustomDialogWindow(dialog, dp(430));
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void openPortal(String target, boolean automatic) {
        cancelScheduledUpdates();
        cancelAutomation();
        automationTarget = target;
        automaticRun = automatic;
        boolean hideBrowser = true;

        FrameLayout overlay = new FrameLayout(this);
        overlay.setBackgroundColor(backgroundColor());

        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(backgroundColor());

        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(12), 0, dp(12), 0);
        TextView back = label("‹", 32, textColor());
        back.setGravity(Gravity.CENTER);
        back.setOnClickListener(v -> {
            cancelAutomation();
            showTab(currentTab);
        });
        bar.addView(back, new LinearLayout.LayoutParams(dp(40), dp(52)));
        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        String targetLabel = automationLabel(target);
        TextView heading = label(("schedule".equals(target) ? "导入" : "更新") + targetLabel, 16, textColor());
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        TextView status = label("正在连接教务系统…", 11, mutedColor());
        titles.addView(heading);
        if (!hideBrowser) titles.addView(status);
        bar.addView(titles, new LinearLayout.LayoutParams(0, dp(52), 1));
        shell.addView(bar);

        ProgressBar progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        shell.addView(progress, new LinearLayout.LayoutParams(-1, dp(3)));

        if (hideBrowser) {
            LinearLayout center = new LinearLayout(this);
            center.setOrientation(LinearLayout.VERTICAL);
            center.setGravity(Gravity.CENTER);
            center.setPadding(dp(20), dp(20), dp(20), dp(20));

            ProgressBar spinner = new ProgressBar(this);
            center.addView(spinner, new LinearLayout.LayoutParams(dp(42), dp(42)));

            LinearLayout card = card(surfaceColor());
            card.setPadding(dp(18), dp(18), dp(18), dp(18));
            addGap(center, 16);
            center.addView(card, new LinearLayout.LayoutParams(-1, -2));

            TextView cardTitle = label("正在通过统一认证" + ("schedule".equals(target) ? "导入" : "更新") + targetLabel, 16, textColor());
            cardTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            card.addView(cardTitle);
            addGap(card, 8);
            card.addView(status);

            shell.addView(center, new LinearLayout.LayoutParams(-1, 0, 1));
        }

        WebView web = new WebView(this);
        automationWeb = web;
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        CookieManager.getInstance().setAcceptCookie(true);
        web.setWebViewClient(new SafeClient(status));
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progress.setProgress(newProgress);
            }
        });

        if (hideBrowser) {
            if (!automatic) {
                web.setAlpha(0f);
                overlay.addView(shell, new FrameLayout.LayoutParams(-1, -1));
                FrameLayout.LayoutParams hiddenWebParams = new FrameLayout.LayoutParams(dp(1), dp(1), Gravity.BOTTOM | Gravity.END);
                overlay.addView(web, hiddenWebParams);
            }
        } else {
            shell.addView(web, new LinearLayout.LayoutParams(-1, 0, 1));
            overlay.addView(shell, new FrameLayout.LayoutParams(-1, -1));
        }

        automationHost.removeAllViews();
        automationHost.setVisibility(View.VISIBLE);
        FrameLayout.LayoutParams hostParams;
        if (automatic) {
            hostParams = new FrameLayout.LayoutParams(dp(1), dp(1), Gravity.BOTTOM | Gravity.END);
            automationHost.setLayoutParams(hostParams);
            automationHost.setBackgroundColor(Color.TRANSPARENT);
            automationHost.addView(web, new FrameLayout.LayoutParams(dp(1), dp(1)));
        } else {
            hostParams = new FrameLayout.LayoutParams(-1, -1);
            automationHost.setLayoutParams(hostParams);
            automationHost.setBackgroundColor(backgroundColor());
            automationHost.addView(overlay, new FrameLayout.LayoutParams(-1, -1));
            automationHost.bringToFront();
        }
        startAutomation(web, status);
        web.loadUrl("electricity".equals(target) ? ELECTRICITY_SSO : EDUCATION_SSO);
    }

    private void startAutomation(WebView web, TextView status) {
        final int generation = ++automationGeneration;
        final int[] attempts = {0};
        final long[] gradeReadyAt = {0};
        final long[] navigationCooldownUntil = {0};
        final boolean[] credentialsSubmitted = {false};
        final boolean[] smsSubmitted = {false};
        final String target = automationTarget;

        automationTask = new Runnable() {
            @Override
            public void run() {
                if (generation != automationGeneration || web.getParent() == null) return;
                if (++attempts[0] > 180) {
                    boolean wasAutomatic = automaticRun;
                    if (!wasAutomatic) Toast.makeText(MainActivity.this, "自动采集超时，请稍后重试", Toast.LENGTH_LONG).show();
                    cancelAutomation();
                    recordAutomaticAttempt(target, wasAutomatic);
                    return;
                }
                if (web.getProgress() < 60) {
                    automationHandler.postDelayed(this, 1000);
                    return;
                }
                String script = autoCollectScript
                        .replace("__MODE__", target)
                        .replace("__ALLOW_NAV__", Boolean.toString(System.currentTimeMillis() >= navigationCooldownUntil[0]));
                String[] credentials = readCredentials();
                script = script.replace("__USERNAME__", JSONObject.quote(credentials[0]))
                        .replace("__PASSWORD__", JSONObject.quote(credentials[1]))
                        .replace("__SMS_CODE__", JSONObject.quote(pendingSmsCode))
                        .replace("__CAN_AUTOFILL__", Boolean.toString(!credentialsSubmitted[0] && !credentials[0].isEmpty() && !credentials[1].isEmpty()))
                        .replace("__CAN_FILL_SMS__", Boolean.toString(!smsSubmitted[0] && !pendingSmsCode.isEmpty()));
                web.evaluateJavascript(script, result -> {
                    if (generation != automationGeneration) return;
                    try {
                        String raw = new JSONArray("[" + result + "]").getString(0);
                        JSONObject payload = new JSONObject(raw);
                        String phase = payload.optString("phase");
                        if ("credentials_required".equals(phase)) {
                            if (automaticRun) {
                                cancelAutomaticAttempt(target);
                                return;
                            }
                            credentialsSubmitted[0] = false;
                            status.setText("需要教务账号");
                            showCredentialsDialog(false);
                        } else if ("credentials_error".equals(phase)) {
                            if (automaticRun) {
                                cancelAutomaticAttempt(target);
                                return;
                            }
                            credentialsSubmitted[0] = false;
                            status.setText("账号或密码有误");
                            showCredentialsDialog(true);
                        } else if ("credentials_submitting".equals(phase)) {
                            credentialsSubmitted[0] = true;
                            status.setText("正在验证账号…");
                        } else if ("sms_required".equals(phase)) {
                            if (automaticRun) {
                                cancelAutomaticAttempt(target);
                                return;
                            }
                            status.setText("需要短信验证码");
                            showSmsDialog();
                        } else if ("sms_submitting".equals(phase)) {
                            smsSubmitted[0] = true;
                            status.setText("正在验证短信验证码…");
                        } else if ("clicked".equals(phase)) {
                            navigationCooldownUntil[0] = System.currentTimeMillis() + 2500L;
                            status.setText("正在打开页面…");
                        } else if ("page".equals(phase)) {
                            navigationCooldownUntil[0] = System.currentTimeMillis() + 1500L;
                            status.setText("页面加载中，请稍候…");
                        } else if ("waiting".equals(phase)) {
                            status.setText("正在查找目标页面…");
                        } else if ("data".equals(phase) && "grades".equals(target)) {
                            if (gradeReadyAt[0] == 0) gradeReadyAt[0] = System.currentTimeMillis() + 5000L;
                            long seconds = Math.max(0, (gradeReadyAt[0] - System.currentTimeMillis() + 999L) / 1000L);
                            if (seconds > 0) {
                                status.setText("成绩加载中，还需 " + seconds + " 秒…");
                            } else {
                                handleCollectedGrades(payload.optJSONArray("rows"));
                                return;
                            }
                        } else if ("schedule_data".equals(phase) && "schedule".equals(target)) {
                            handleCollectedSchedule(payload.optJSONObject("payload"));
                            return;
                        } else if ("electricity_data".equals(phase) && "electricity".equals(target)) {
                            handleCollectedElectricity(payload.optDouble("balance", Double.NaN));
                            return;
                        }
                    } catch (Exception ignored) {
                        status.setText("正在等待页面加载…");
                    }
                    if (generation == automationGeneration) automationHandler.postDelayed(this, 1000);
                });
            }
        };
        automationHandler.postDelayed(automationTask, 700);
    }

    private void handleCollectedGrades(JSONArray array) {
        if (array == null) return;
        List<Grade> out = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            JSONArray row = array.optJSONArray(i);
            if (row != null && row.length() >= 4) out.add(Grade.from(row));
        }
        if (out.isEmpty()) return;
        boolean first = grades.isEmpty();
        List<String> changedCourses = first ? Collections.emptyList()
                : UpdateDiff.changedNames(gradeDiffItems(grades), gradeDiffItems(out));
        boolean wasAutomatic = automaticRun;
        grades = out;
        saveGrades();
        cancelAutomation();
        if (wasAutomatic) {
            if (gradeUpdateNotificationEnabled && !changedCourses.isEmpty()) {
                sendGradeNotification(changedCourses);
            }
        } else {
            Toast.makeText(this, "已更新 " + out.size() + " 门成绩", Toast.LENGTH_SHORT).show();
        }
        if (!wasAutomatic || currentTab == TAB_HOME || currentTab == TAB_GRADES) showTab(currentTab);
        recordAutomaticAttempt("grades", wasAutomatic);
    }

    private void handleCollectedSchedule(JSONObject payload) {
        if (payload == null) return;
        boolean wasAutomatic = automaticRun;
        boolean hadPreviousSchedule = !courses.isEmpty();
        List<UpdateDiff.Item> previousItems = UpdateDiff.scheduleItems(courses);
        ScheduleImport.ParsedData parsed = ScheduleImport.parsePayload(payload);
        int importedCount = 0;
        String firstImportedId = "";

        List<ScheduleModels.Semester> updatedSemesters = new ArrayList<>(semesters);
        List<ScheduleModels.Course> updatedCourses = new ArrayList<>(courses);

        for (ScheduleImport.RawSemester rawSemester : parsed.semesters) {
            List<ScheduleModels.Course> semesterCourses = ScheduleImport.convertToCourses(parsed.courses, "", rawSemester.dataSemester);
            if (semesterCourses.isEmpty()) continue;
            int semesterIndex = findSemesterIndexByName(updatedSemesters, rawSemester.name);
            ScheduleModels.Semester semester;
            if (semesterIndex >= 0) {
                semester = updatedSemesters.get(semesterIndex);
                ScheduleModels.Semester imported = ScheduleImport.createImportedSemester(rawSemester, semesterCourses);
                semester.name = imported.name;
                semester.weekCount = imported.weekCount;
                semester.sectionCount = imported.sectionCount;
                semester.sectionTimes = imported.sectionTimes;
                semester.startDate = normalizeSemesterStartDate(semester.startDate);
                semester.endDate = LocalDate.parse(semester.startDate)
                        .plusWeeks(Math.max(1, semester.weekCount)).minusDays(1).toString();
            } else {
                semester = ScheduleImport.createImportedSemester(rawSemester, semesterCourses);
                updatedSemesters.add(semester);
            }
            replaceCoursesForSemester(updatedCourses, semester.id, semesterCourses);
            if (firstImportedId.isEmpty()) firstImportedId = semester.id;
            importedCount += semesterCourses.size();
        }

        if (importedCount == 0 && !parsed.courses.isEmpty()) {
            ScheduleModels.Semester semester = ScheduleImport.createImportedSemester(parsed.semesters.get(0), new ArrayList<>());
            List<ScheduleModels.Course> semesterCourses = ScheduleImport.convertToCourses(parsed.courses, semester.id, "");
            if (!semesterCourses.isEmpty()) {
                updatedSemesters.add(semester);
                updatedCourses.addAll(semesterCourses);
                firstImportedId = semester.id;
                importedCount = semesterCourses.size();
            }
        }

        if (importedCount == 0) {
            cancelAutomation();
            if (!wasAutomatic) {
                showTab(currentTab);
                Toast.makeText(this, "没有解析到课表数据，请进入“全部课程”页面后重试", Toast.LENGTH_LONG).show();
            }
            recordAutomaticAttempt("schedule", wasAutomatic);
            return;
        }

        semesters = updatedSemesters;
        courses = updatedCourses;
        List<String> changedCourses = hadPreviousSchedule
                ? UpdateDiff.changedNames(previousItems, UpdateDiff.scheduleItems(courses))
                : Collections.emptyList();
        if (!firstImportedId.isEmpty()) selectedSemesterId = firstImportedId;
        saveScheduleState();
        cancelAutomation();
        scheduleShowMonth = false;
        scheduleWeekOffset = 0;
        if (wasAutomatic) {
            if (scheduleUpdateNotificationEnabled && !changedCourses.isEmpty()) {
                sendScheduleNotification(changedCourses);
            }
            if (currentTab == TAB_HOME || currentTab == TAB_SCHEDULE) showTab(currentTab);
        } else {
            showTab(TAB_SCHEDULE);
            Toast.makeText(this, "已导入 " + importedCount + " 门课程", Toast.LENGTH_LONG).show();
        }
        recordAutomaticAttempt("schedule", wasAutomatic);
    }

    private void handleCollectedElectricity(double balance) {
        if (Double.isNaN(balance) || balance < 0) return;
        boolean wasAutomatic = automaticRun;
        electricityBalance = balance;
        store.edit()
                .putString("electricity_balance", Double.toString(balance))
                .putString("electricity_balance_source", ELECTRICITY_HOME)
                .apply();
        updateElectricityAlert(balance);
        cancelAutomation();
        if (!wasAutomatic) Toast.makeText(this, "剩余电费 " + scoreDf.format(balance) + " 元", Toast.LENGTH_LONG).show();
        if (!wasAutomatic || currentTab == TAB_HOME || currentTab == TAB_SETTINGS) showTab(currentTab);
        recordAutomaticAttempt("electricity", wasAutomatic);
    }

    private void cancelAutomation() {
        automationGeneration++;
        if (automationTask != null) automationHandler.removeCallbacks(automationTask);
        automationTask = null;
        if (automationWeb != null) {
            WebView web = automationWeb;
            automationWeb = null;
            if (web.getParent() instanceof ViewGroup) {
                ((ViewGroup) web.getParent()).removeView(web);
            }
            web.stopLoading();
            web.destroy();
        }
        automationHost.removeAllViews();
        automationHost.setVisibility(View.GONE);
        automationHost.setLayoutParams(new FrameLayout.LayoutParams(-1, -1));
        automationTarget = "";
        automaticRun = false;
        pendingSmsCode = "";
    }

    private void scheduleAllAutomaticUpdates(long minimumDelayMillis) {
        cancelScheduledUpdates();
        if (!hasCredentials()) return;
        long now = System.currentTimeMillis();
        String nextTarget = null;
        long nextAt = Long.MAX_VALUE;
        String[] targets = {"grades", "electricity", "schedule"};
        for (String target : targets) {
            if (!isAutomaticEnabled(target)) continue;
            long lastAttempt = store.getLong("auto_last_" + target, 0L);
            long dueAt = lastAttempt == 0L ? now + Math.max(0, minimumDelayMillis)
                    : lastAttempt + intervalMillis(target);
            if (dueAt < nextAt) {
                nextAt = dueAt;
                nextTarget = target;
            }
        }
        if (nextTarget == null) return;
        final String target = nextTarget;
        scheduledUpdateTask = () -> {
            scheduledUpdateTask = null;
            if (automationWeb == null) openPortal(target, true);
            else scheduleAllAutomaticUpdates(30_000L);
        };
        automationHandler.postDelayed(scheduledUpdateTask, Math.max(0L, nextAt - now));
    }

    private void syncBackgroundService() {
        if (!hasCredentials() || (!autoGradeEnabled && !autoScheduleEnabled && !autoElectricityEnabled)) {
            stopBackgroundService();
            return;
        }
        BackgroundSyncScheduler.schedule(this);
    }

    private void stopBackgroundService() {
        BackgroundSyncScheduler.cancel(this);
        stopService(new Intent(this, BackgroundSyncService.class));
    }

    private void cancelScheduledUpdates() {
        if (scheduledUpdateTask != null) automationHandler.removeCallbacks(scheduledUpdateTask);
        scheduledUpdateTask = null;
    }

    private void recordAutomaticAttempt(String target, boolean wasAutomatic) {
        if (wasAutomatic) store.edit().putLong("auto_last_" + target, System.currentTimeMillis()).apply();
        scheduleAllAutomaticUpdates(0L);
        syncBackgroundService();
    }

    private void cancelAutomaticAttempt(String target) {
        cancelAutomation();
        recordAutomaticAttempt(target, true);
    }

    private void exportBackup() {
        JSONObject backup = new JSONObject();
        try {
            backup.put("version", "2.0");
            backup.put("exportDate", LocalDate.now().toString());
            JSONArray courseArray = new JSONArray();
            for (ScheduleModels.Course course : courses) courseArray.put(course.json());
            backup.put("courses", courseArray);
            JSONObject settings = new JSONObject();
            JSONArray semestersArray = new JSONArray();
            for (ScheduleModels.Semester semester : semesters) semestersArray.put(semester.json());
            settings.put("semesters", semestersArray);
            settings.put("themeColor", themeColor);
            settings.put("darkMode", darkMode);
            backup.put("settings", settings);
            pendingExportJson = backup.toString(2);
            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("application/json");
            intent.putExtra(Intent.EXTRA_TITLE, "soaring-schedule-" + LocalDate.now() + ".json");
            startActivityForResult(intent, REQUEST_EXPORT_JSON);
        } catch (Exception e) {
            Toast.makeText(this, "导出失败", Toast.LENGTH_SHORT).show();
        }
    }

    private void writeExportJson(Uri uri) {
        try (OutputStream stream = getContentResolver().openOutputStream(uri)) {
            if (stream == null) throw new IllegalStateException();
            stream.write(pendingExportJson.getBytes(StandardCharsets.UTF_8));
            stream.flush();
            Toast.makeText(this, "导出成功", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "导出失败", Toast.LENGTH_SHORT).show();
        }
    }

    private void requestImportBackup() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");
        startActivityForResult(intent, REQUEST_IMPORT_JSON);
    }

    private void importBackupJson(Uri uri) {
        try (InputStream input = getContentResolver().openInputStream(uri);
             BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            StringBuilder builder = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) builder.append(line).append('\n');
            JSONObject parsed = new JSONObject(builder.toString());
            JSONArray courseArray = parsed.optJSONArray("courses");
            JSONObject settings = parsed.optJSONObject("settings");
            if (courseArray == null || settings == null) throw new IllegalStateException();

            List<ScheduleModels.Course> importedCourses = new ArrayList<>();
            for (int i = 0; i < courseArray.length(); i++) {
                JSONObject item = courseArray.optJSONObject(i);
                if (item != null) importedCourses.add(ScheduleModels.Course.from(item));
            }
            List<ScheduleModels.Semester> importedSemesters = new ArrayList<>();
            JSONArray semesterArray = settings.optJSONArray("semesters");
            if (semesterArray != null) {
                for (int i = 0; i < semesterArray.length(); i++) {
                    JSONObject item = semesterArray.optJSONObject(i);
                    if (item != null) importedSemesters.add(ScheduleModels.Semester.from(item));
                }
            }
            courses = importedCourses;
            semesters = importedSemesters;
            normalizeSemesterSectionTimes();
            themeColor = settings.optString("themeColor", ScheduleModels.DEFAULT_THEME_COLOR);
            darkMode = settings.optBoolean("darkMode", false);
            ensureSelectedSemester();
            saveScheduleState();
            applyWindowTheme();
            showTab(TAB_SETTINGS, true);
            Toast.makeText(this, "导入成功", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "导入失败", Toast.LENGTH_LONG).show();
        }
    }

    private void saveScheduleState() {
        ensureSelectedSemester();
        ScheduleStorage.saveSemesters(store, semesters);
        ScheduleStorage.saveCourses(store, courses);
        ScheduleStorage.saveSelectedSemester(store, selectedSemesterId);
        ScheduleStorage.saveTheme(store, themeColor, darkMode);
        ScheduleWidgetUpdater.updateAll(this);
    }

    private boolean normalizeSemesterSectionTimes() {
        boolean changed = false;
        for (ScheduleModels.Semester semester : semesters) {
            List<ScheduleModels.SectionTime> expected = ScheduleModels.buildDefaultSectionTimes(semester.sectionCount);
            if (!sameSectionTimes(semester.sectionTimes, expected)) {
                semester.sectionTimes = expected;
                changed = true;
            }
        }
        return changed;
    }

    private boolean normalizeSemesterStartDates() {
        boolean changed = false;
        for (ScheduleModels.Semester semester : semesters) {
            String start = normalizeSemesterStartDate(semester.startDate);
            String end = LocalDate.parse(start)
                    .plusWeeks(Math.max(1, semester.weekCount)).minusDays(1).toString();
            if (!start.equals(semester.startDate) || !end.equals(semester.endDate)) {
                semester.startDate = start;
                semester.endDate = end;
                changed = true;
            }
        }
        return changed;
    }

    private String normalizeSemesterStartDate(String value) {
        try {
            return ScheduleUtils.mondayOnOrBefore(LocalDate.parse(value)).toString();
        } catch (Exception ignored) {
            return ScheduleUtils.mondayOnOrBefore(LocalDate.now()).toString();
        }
    }

    private boolean sameSectionTimes(List<ScheduleModels.SectionTime> first, List<ScheduleModels.SectionTime> second) {
        if (first == null || first.size() != second.size()) return false;
        for (int i = 0; i < first.size(); i++) {
            ScheduleModels.SectionTime left = first.get(i);
            ScheduleModels.SectionTime right = second.get(i);
            if (!left.start.equals(right.start) || !left.end.equals(right.end)) return false;
        }
        return true;
    }

    private void saveTheme() {
        ScheduleStorage.saveTheme(store, themeColor, darkMode);
        ScheduleWidgetUpdater.updateAll(this);
    }

    private void saveSemester(ScheduleModels.Semester semester, boolean isEdit) {
        semester.startDate = normalizeSemesterStartDate(semester.startDate);
        semester.endDate = LocalDate.parse(semester.startDate)
                .plusWeeks(Math.max(1, semester.weekCount)).minusDays(1).toString();
        if (isEdit) {
            for (int i = 0; i < semesters.size(); i++) {
                if (semesters.get(i).id.equals(semester.id)) {
                    adjustCoursesForSemester(semester.id, semester.weekCount, semester.sectionCount);
                    semesters.set(i, semester);
                    break;
                }
            }
        } else {
            semesters.add(semester);
        }
        selectedSemesterId = semester.id;
        saveScheduleState();
    }

    private void saveCourse(ScheduleModels.Course course, boolean isEdit) {
        if (isEdit) {
            for (int i = 0; i < courses.size(); i++) {
                if (courses.get(i).id.equals(course.id)) {
                    courses.set(i, course);
                    saveScheduleState();
                    return;
                }
            }
        }
        courses.add(course);
        saveScheduleState();
    }

    private void signOut() {
        cancelScheduledUpdates();
        cancelAutomation();
        stopBackgroundService();
        grades = new ArrayList<>();
        semesters = new ArrayList<>();
        courses = new ArrayList<>();
        selectedSemesterId = "";
        electricityBalance = Double.NaN;
        scheduleWeekOffset = 0;
        scheduleMonthAnchor = LocalDate.now();
        Arrays.fill(tabScrollPositions, 0);
        store.edit()
                .remove("login_credentials")
                .remove("grades")
                .remove(ScheduleStorage.KEY_SEMESTERS)
                .remove(ScheduleStorage.KEY_COURSES)
                .remove(ScheduleStorage.KEY_SELECTED_SEMESTER)
                .remove("electricity_balance")
                .remove("electricity_balance_source")
                .remove("electricity_alert_active")
                .remove("auto_last_grades")
                .remove("auto_last_schedule")
                .remove("auto_last_electricity")
                .apply();
        NotificationManager notifications = getSystemService(NotificationManager.class);
        if (notifications != null) {
            notifications.cancel(1001);
            notifications.cancel(1002);
            notifications.cancel(1003);
        }
        CookieManager cookies = CookieManager.getInstance();
        cookies.removeAllCookies(null);
        cookies.flush();
        ScheduleWidgetUpdater.updateAll(this);
        showTab(TAB_SETTINGS);
        Toast.makeText(this, "已退出登录并清除成绩、课表和电费", Toast.LENGTH_SHORT).show();
    }

    private SecretKey credentialKey() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (!store.containsAlias(CREDENTIAL_KEY)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(CREDENTIAL_KEY, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build());
            generator.generateKey();
        }
        return ((KeyStore.SecretKeyEntry) store.getEntry(CREDENTIAL_KEY, null)).getSecretKey();
    }

    private void saveCredentials(String username, String password) {
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, credentialKey());
            String payload = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP) + ":" +
                    Base64.encodeToString(cipher.doFinal((username + "\n" + password).getBytes(StandardCharsets.UTF_8)), Base64.NO_WRAP);
            store.edit().putString("login_credentials", payload).apply();
        } catch (Exception error) {
            Toast.makeText(this, "无法安全保存账号，请重试", Toast.LENGTH_LONG).show();
        }
    }

    private String[] readCredentials() {
        try {
            String value = store.getString("login_credentials", "");
            if (value == null || value.isEmpty()) return new String[]{"", ""};
            String[] parts = value.split(":", 2);
            if (parts.length != 2) return new String[]{"", ""};
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, credentialKey(), new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
            String[] account = new String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), StandardCharsets.UTF_8).split("\n", 2);
            return account.length == 2 ? account : new String[]{"", ""};
        } catch (Exception ignored) {
            return new String[]{"", ""};
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(GRADE_CHANNEL, "成绩更新", NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("检测到成绩变化时通知");
            getSystemService(NotificationManager.class).createNotificationChannel(channel);
            NotificationChannel schedule = new NotificationChannel(SCHEDULE_CHANNEL, "课表更新", NotificationManager.IMPORTANCE_HIGH);
            schedule.setDescription("检测到课表变化时通知");
            getSystemService(NotificationManager.class).createNotificationChannel(schedule);
            NotificationChannel electricity = new NotificationChannel(ELECTRICITY_CHANNEL, "电费提醒", NotificationManager.IMPORTANCE_HIGH);
            electricity.setDescription("剩余电费低于设定余量时通知");
            getSystemService(NotificationManager.class).createNotificationChannel(electricity);
        }
    }

    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 7);
        }
    }

    private void sendGradeNotification(List<String> changedCourses) {
        Intent intent = new Intent(this, MainActivity.class).putExtra(EXTRA_START_TAB, TAB_GRADES);
        PendingIntent pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        android.app.Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new android.app.Notification.Builder(this, GRADE_CHANNEL)
                : new android.app.Notification.Builder(this);
        builder.setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle("成绩有更新")
                .setContentText(UpdateDiff.notificationText(changedCourses, true))
                .setAutoCancel(true)
                .setContentIntent(pending);
        getSystemService(NotificationManager.class).notify(1001, builder.build());
    }

    private void sendScheduleNotification(List<String> changedCourses) {
        Intent intent = new Intent(this, MainActivity.class).putExtra(EXTRA_START_TAB, TAB_SCHEDULE);
        PendingIntent pending = PendingIntent.getActivity(this, 1, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        android.app.Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new android.app.Notification.Builder(this, SCHEDULE_CHANNEL)
                : new android.app.Notification.Builder(this);
        builder.setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle("课表有更新")
                .setContentText(UpdateDiff.notificationText(changedCourses, false))
                .setAutoCancel(true)
                .setContentIntent(pending);
        getSystemService(NotificationManager.class).notify(1003, builder.build());
    }

    private void applyWindowTheme() {
        if (root != null) root.setBackgroundColor(backgroundColor());
        if (Build.VERSION.SDK_INT >= 21) getWindow().setStatusBarColor(backgroundColor());
        if (Build.VERSION.SDK_INT >= 23) {
            int flags = getWindow().getDecorView().getSystemUiVisibility();
            if (darkMode) flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            else flags |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            getWindow().getDecorView().setSystemUiVisibility(flags);
        }
    }

    private int backgroundColor() {
        return darkMode ? Color.rgb(17, 21, 28) : Color.rgb(247, 249, 252);
    }

    private int surfaceColor() {
        return darkMode ? Color.rgb(28, 34, 43) : Color.rgb(239, 244, 249);
    }

    private int panelColor() {
        return darkMode ? Color.rgb(24, 29, 37) : Color.WHITE;
    }

    private int textColor() {
        return darkMode ? Color.rgb(245, 248, 252) : Color.rgb(25, 50, 77);
    }

    private int mutedColor() {
        return darkMode ? Color.rgb(156, 176, 199) : Color.rgb(94, 113, 133);
    }

    private int lineColor() {
        return darkMode ? Color.rgb(53, 62, 74) : Color.rgb(220, 227, 235);
    }

    private int primaryColor() {
        try {
            return Color.parseColor(themeColor);
        } catch (Exception ignored) {
            return Color.rgb(47, 128, 237);
        }
    }

    private ScrollView page() {
        ScrollView s = new ScrollView(this);
        s.setFillViewport(true);
        s.setBackgroundColor(backgroundColor());
        s.setSaveEnabled(false);
        currentPage = s;
        return s;
    }

    private LinearLayout column() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setPadding(dp(16), dp(14), dp(16), dp(24));
        return l;
    }

    private TextView label(String text, float size, int color) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(size);
        t.setTextColor(color);
        t.setGravity(Gravity.CENTER_VERTICAL);
        return t;
    }

    private TextView title(String text) {
        TextView t = label(text, 24, textColor());
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t.setPadding(0, dp(5), 0, dp(2));
        return t;
    }

    private TextView section(String text) {
        TextView t = label(text, 14, textColor());
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t.setPadding(0, dp(18), 0, dp(8));
        return t;
    }

    private LinearLayout pageHeader(String heading, String subtitle) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, 0, 0, dp(12));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(title(heading));
        if (subtitle != null && !subtitle.isEmpty()) text.addView(label(subtitle, 12, mutedColor()));
        row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
        return row;
    }

    private LinearLayout settingsPanelHeader(String heading, String subtitle) {
        LinearLayout row = pageHeader(heading, subtitle);
        ImageView back = iconButton(R.drawable.ic_arrow_back, "返回设置");
        back.setOnClickListener(v -> {
            settingsPanel = "";
            if (currentPage != null) currentPage.scrollTo(0, 0);
            tabScrollPositions[TAB_SETTINGS] = 0;
            showTab(TAB_SETTINGS);
        });
        row.addView(back, 0, new LinearLayout.LayoutParams(dp(40), dp(40)));
        ((LinearLayout.LayoutParams) back.getLayoutParams()).setMarginEnd(dp(10));
        return row;
    }

    private void addSettingNavigation(LinearLayout parent, String heading, String summary,
                                      String panel, boolean divider) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(8), 0, dp(8));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = label(heading, 14, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        text.addView(title);
        if (summary != null && !summary.isEmpty()) text.addView(label(summary, 11, mutedColor()));
        row.addView(text, new LinearLayout.LayoutParams(0, dp(54), 1));
        ImageView arrow = new ImageView(this);
        arrow.setImageResource(R.drawable.ic_chevron_right);
        arrow.setColorFilter(mutedColor());
        arrow.setContentDescription("打开" + heading);
        arrow.setPadding(dp(7), dp(7), dp(7), dp(7));
        row.addView(arrow, new LinearLayout.LayoutParams(dp(32), dp(32)));
        row.setOnClickListener(v -> {
            settingsPanel = panel;
            if (currentPage != null) currentPage.scrollTo(0, 0);
            tabScrollPositions[TAB_SETTINGS] = 0;
            showTab(TAB_SETTINGS);
        });
        parent.addView(row);
        if (divider) parent.addView(settingDivider());
    }

    private String automaticUpdateSummary() {
        int enabled = (autoGradeEnabled ? 1 : 0) + (autoScheduleEnabled ? 1 : 0)
                + (autoElectricityEnabled ? 1 : 0);
        return enabled == 0 ? "全部关闭" : "已开启 " + enabled + " 项";
    }

    private String notificationSummary() {
        if (gradeUpdateNotificationEnabled && scheduleUpdateNotificationEnabled) return "成绩与课表变化";
        if (gradeUpdateNotificationEnabled) return "仅成绩变化";
        if (scheduleUpdateNotificationEnabled) return "仅课表变化";
        return "已关闭";
    }

    private String appVersion() {
        try {
            android.content.pm.PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
            long versionCode = Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
            return info.versionName + " (" + versionCode + ")";
        } catch (Exception ignored) {
            return "1.4 (5)";
        }
    }

    private LinearLayout sectionHeader(String heading) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView text = section(heading);
        row.addView(text, new LinearLayout.LayoutParams(0, dp(54), 1));
        return row;
    }

    private LinearLayout metric(String caption, String value, String unit) {
        LinearLayout metric = new LinearLayout(this);
        metric.setOrientation(LinearLayout.VERTICAL);
        metric.setGravity(Gravity.CENTER_VERTICAL);
        metric.setPadding(dp(8), dp(4), dp(8), dp(4));
        metric.addView(label(caption, 11, mutedColor()));
        LinearLayout valueRow = new LinearLayout(this);
        valueRow.setGravity(Gravity.BOTTOM);
        TextView number = label(value, 23, textColor());
        number.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        valueRow.addView(number);
        TextView suffix = label(" " + unit, 10, mutedColor());
        suffix.setPadding(0, 0, 0, dp(3));
        valueRow.addView(suffix);
        metric.addView(valueRow);
        return metric;
    }

    private ImageView iconButton(int resource, String description) {
        ImageView button = new ImageView(this);
        button.setImageResource(resource);
        button.setColorFilter(primaryColor());
        button.setContentDescription(description);
        button.setPadding(dp(9), dp(9), dp(9), dp(9));
        button.setBackground(border(panelColor(), lineColor(), 5));
        return button;
    }

    private Button syncButton(String text, String description) {
        Button button = action(text, false);
        android.graphics.drawable.Drawable icon = getDrawable(R.drawable.ic_sync);
        if (icon != null) {
            icon = icon.mutate();
            icon.setTint(primaryColor());
            icon.setBounds(0, 0, dp(16), dp(16));
            button.setCompoundDrawables(icon, null, null, null);
            button.setCompoundDrawablePadding(dp(4));
        }
        button.setContentDescription(description);
        button.setMinWidth(0);
        button.setPadding(dp(7), 0, dp(7), 0);
        return button;
    }

    private Switch settingSwitch(String text, boolean checked) {
        Switch value = new Switch(this);
        value.setText(text);
        value.setTextSize(13);
        value.setTextColor(textColor());
        value.setChecked(checked);
        value.setGravity(Gravity.CENTER_VERTICAL);
        return value;
    }

    private View settingDivider() {
        View divider = new View(this);
        divider.setBackgroundColor(lineColor());
        divider.setLayoutParams(new LinearLayout.LayoutParams(-1, dp(1)));
        return divider;
    }

    private LinearLayout card(int color) {
        LinearLayout c = new LinearLayout(this);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setBackground(border(color, lineColor(), 5));
        c.setPadding(dp(14), dp(12), dp(14), dp(12));
        return c;
    }

    private GradientDrawable bg(int color, int radiusDp) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(radiusDp));
        return d;
    }

    private GradientDrawable border(int fill, int stroke) {
        return border(fill, stroke, 5);
    }

    private GradientDrawable border(int fill, int stroke, int radiusDp) {
        GradientDrawable d = bg(fill, radiusDp);
        d.setStroke(dp(1), stroke);
        return d;
    }

    private Button action(String text, boolean filled) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextSize(12);
        b.setAllCaps(false);
        b.setTextColor(filled ? Color.WHITE : primaryColor());
        b.setMinHeight(dp(42));
        b.setPadding(dp(12), 0, dp(12), 0);
        b.setBackground(border(filled ? primaryColor() : panelColor(), filled ? primaryColor() : lineColor(), 5));
        applyRoundedButtonOutline(b, 5);
        return b;
    }

    private Button stepButton(String mark) {
        Button b = new Button(this);
        b.setText(mark);
        b.setTextSize(20);
        b.setTextColor(primaryColor());
        b.setPadding(0, 0, 0, 0);
        b.setMinWidth(0);
        b.setMinHeight(0);
        b.setBackground(border(panelColor(), lineColor(), 5));
        applyRoundedButtonOutline(b, 5);
        return b;
    }

    private void applyRoundedButtonOutline(Button button, int radiusDp) {
        button.setStateListAnimator(null);
        applyRoundedOutline(button, radiusDp, 1);
    }

    private void applyRoundedOutline(View view, int radiusDp, int elevationDp) {
        view.setElevation(dp(elevationDp));
        view.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View target, Outline outline) {
                if (target.getWidth() > 0 && target.getHeight() > 0) {
                    outline.setRoundRect(0, 0, target.getWidth(), target.getHeight(), dp(radiusDp));
                }
            }
        });
        view.setClipToOutline(true);
    }

    private View colorSwatch(String value, boolean selected) {
        View swatch = new View(this);
        GradientDrawable d = bg(Color.parseColor(value), 10);
        d.setStroke(dp(selected ? 3 : 1), selected ? textColor() : lineColor());
        swatch.setBackground(d);
        swatch.setLayoutParams(new LinearLayout.LayoutParams(dp(28), dp(28)));
        return swatch;
    }

    private TextView emptyHint(String text) {
        TextView t = label(text, 14, mutedColor());
        t.setGravity(Gravity.CENTER);
        t.setBackground(border(panelColor(), lineColor(), 5));
        t.setPadding(dp(14), dp(18), dp(14), dp(18));
        return t;
    }

    private LinearLayout gradeRow(Grade grade) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(11), 0, dp(11));
        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        TextView name = label(grade.course, 15, textColor());
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        left.addView(name);
        left.addView(label(grade.category + " · " + grade.credits + " 学分", 12, mutedColor()));
        if (!grade.detail.isEmpty()) left.addView(label(grade.detail, 11, mutedColor()));
        row.addView(left, new LinearLayout.LayoutParams(0, dp(64), 1));
        LinearLayout right = new LinearLayout(this);
        right.setOrientation(LinearLayout.VERTICAL);
        right.setGravity(Gravity.CENTER);
        TextView point = label("绩点 " + grade.pointText(), 15, primaryColor());
        point.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        right.addView(point);
        right.addView(label("成绩 " + grade.scoreText(), 11, mutedColor()));
        row.addView(right, new LinearLayout.LayoutParams(dp(84), dp(64)));
        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.addView(row);
        View line = new View(this);
        line.setBackgroundColor(lineColor());
        wrap.addView(line, new LinearLayout.LayoutParams(-1, dp(1)));
        return wrap;
    }

    private LinearLayout schedulePreviewRow(ScheduleModels.Course course, LocalDate date) {
        LinearLayout card = card(surfaceColor());
        ScheduleModels.TimeSlot slot = primarySlotForDate(course, date);
        TextView name = label(course.name, 15, textColor());
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        card.addView(name);
        card.addView(label(slot == null ? primaryTimeForDate(course, date)
                : ScheduleUtils.formatSections(slot.classSections), 12, mutedColor()));
        String location = slot != null && slot.location != null ? slot.location : course.location;
        if (location != null) card.addView(label(location, 12, mutedColor()));
        card.setOnClickListener(v -> showCourseMeetingDetailDialog(course, slot));
        return card;
    }

    private LinearLayout semesterCard(ScheduleModels.Semester semester) {
        LinearLayout card = card(surfaceColor());
        TextView title = label(semester.name, 15, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        card.addView(title);
        card.addView(label(semester.startDate + " 至 " + semester.endDate, 12, mutedColor()));
        card.addView(label(semester.weekCount + " 周 · " + semester.sectionCount + " 节", 12, mutedColor()));
        addGap(card, 10);
        LinearLayout actions = new LinearLayout(this);
        Button select = action(selectedSemesterId.equals(semester.id) ? "当前学期" : "切换", false);
        select.setOnClickListener(v -> {
            selectedSemesterId = semester.id;
            ScheduleStorage.saveSelectedSemester(store, selectedSemesterId);
            showTab(TAB_MANAGE);
        });
        Button edit = action("编辑", false);
        edit.setOnClickListener(v -> showSemesterDialog(semester));
        Button delete = action("删除", false);
        delete.setOnClickListener(v -> deleteSemester(semester));
        actions.addView(select, new LinearLayout.LayoutParams(0, dp(42), 1));
        addHorizontalGap(actions, 8);
        actions.addView(edit, new LinearLayout.LayoutParams(0, dp(42), 1));
        addHorizontalGap(actions, 8);
        actions.addView(delete, new LinearLayout.LayoutParams(0, dp(42), 1));
        card.addView(actions);
        return card;
    }

    private LinearLayout courseManageCard(ScheduleModels.Course course) {
        LinearLayout card = card(surfaceColor());
        TextView title = label(course.name, 15, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        card.addView(title);
        card.addView(label(ScheduleUtils.formatCourseTime(course), 12, mutedColor()));
        if (course.location != null) card.addView(label(course.location, 12, mutedColor()));
        if (course.teacher != null) card.addView(label(course.teacher, 12, mutedColor()));
        addGap(card, 10);
        LinearLayout actions = new LinearLayout(this);
        Button detail = action("详情", false);
        detail.setOnClickListener(v -> showCourseDetailDialog(course));
        actions.addView(detail, new LinearLayout.LayoutParams(-1, dp(42)));
        card.addView(actions);
        return card;
    }

    private View dayHeader(String top, String bottom) {
        LinearLayout cell = new LinearLayout(this);
        cell.setOrientation(LinearLayout.VERTICAL);
        cell.setGravity(Gravity.CENTER);
        cell.setBackground(border(backgroundColor(), lineColor(), 5));
        TextView t1 = label(top, 11, textColor());
        t1.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t1.setGravity(Gravity.CENTER);
        TextView t2 = label(bottom, 9, mutedColor());
        t2.setGravity(Gravity.CENTER);
        cell.addView(t1);
        cell.addView(t2);
        return cell;
    }

    private View sectionLabel(ScheduleModels.Semester semester, int section) {
        LinearLayout cell = new LinearLayout(this);
        cell.setOrientation(LinearLayout.VERTICAL);
        cell.setGravity(Gravity.CENTER);
        cell.setBackground(border(backgroundColor(), lineColor(), 5));
        TextView name = label(String.valueOf(section), 10, textColor());
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        name.setGravity(Gravity.CENTER);
        cell.addView(name);
        if (section - 1 < semester.sectionTimes.size()) {
            ScheduleModels.SectionTime time = semester.sectionTimes.get(section - 1);
            TextView range = label(time.start + "\n" + time.end, 8, mutedColor());
            range.setGravity(Gravity.CENTER);
            cell.addView(range);
        }
        return cell;
    }

    private View emptyCell() {
        View cell = new View(this);
        cell.setBackground(border(backgroundColor(), lineColor(), 5));
        return cell;
    }

    private View courseBlock(ScheduleModels.Course course, int span, int week, int day, int section) {
        LinearLayout block = new LinearLayout(this);
        ScheduleModels.TimeSlot slot = matchingSlot(course, week, day, section);
        block.setOrientation(LinearLayout.VERTICAL);
        int fill = parseColorSafe(course.color, primaryColorWithAlpha(240));
        block.setBackground(border(fill, lineColor(), 5));
        block.setPadding(dp(3), dp(3), dp(3), dp(3));
        TextView title = label(course.name, 10, contrastText(fill));
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setMaxLines(span <= 1 ? 2 : 4);
        block.addView(title);
        TextView time = label(slot == null ? dayPrimarySectionLabel(course, week, day)
                : ScheduleUtils.formatSections(slot.classSections), 8, contrastText(fill));
        time.setMaxLines(1);
        block.addView(time);
        String slotLocation = slot != null && slot.location != null ? slot.location : course.location;
        if (slotLocation != null) {
            TextView location = label(slotLocation, 8, contrastText(fill));
            location.setMaxLines(span <= 1 ? 1 : 2);
            block.addView(location);
        }
        block.setOnClickListener(v -> showCourseMeetingDetailDialog(course, slot));
        return block;
    }

    private TextView infoLine(String labelText, String value) {
        TextView view = label(labelText + "：\n" + value, 13, textColor());
        view.setPadding(0, dp(6), 0, dp(6));
        return view;
    }

    private EditText field(LinearLayout parent, String hint, String value) {
        EditText input = new EditText(this);
        input.setHint(hint);
        if (value != null) input.setText(value);
        parent.addView(input, new LinearLayout.LayoutParams(-1, dp(58)));
        return input;
    }

    private void showCourseDialogRefresh(LinearLayout form, LinearLayout container, String chosen) {
        container.removeAllViews();
        for (String value : ScheduleModels.PRESET_COLORS) {
            View swatch = colorSwatch(value, value.equals(chosen));
            container.addView(swatch);
            addHorizontalGap(container, 8);
        }
    }

    private void deleteSemester(ScheduleModels.Semester semester) {
        semesters.remove(semester);
        List<ScheduleModels.Course> remaining = new ArrayList<>();
        for (ScheduleModels.Course course : courses) {
            if (!course.semesterId.equals(semester.id)) remaining.add(course);
        }
        courses = remaining;
        if (semester.id.equals(selectedSemesterId)) selectedSemesterId = "";
        saveScheduleState();
        showTab(TAB_MANAGE);
    }

    private void deleteCourse(ScheduleModels.Course course) {
        courses.remove(course);
        saveScheduleState();
        showTab(TAB_MANAGE);
    }

    private void ensureSelectedSemester() {
        if (!selectedSemesterId.isEmpty()) {
            for (ScheduleModels.Semester semester : semesters) {
                if (semester.id.equals(selectedSemesterId)) return;
            }
        }
        selectedSemesterId = semesters.isEmpty() ? "" : semesters.get(0).id;
    }

    private ScheduleModels.Semester selectedSemester() {
        ensureSelectedSemester();
        for (ScheduleModels.Semester semester : semesters) {
            if (semester.id.equals(selectedSemesterId)) return semester;
        }
        return null;
    }

    private ScheduleModels.Semester defaultEditableSemester() {
        LocalDate now = ScheduleUtils.mondayOnOrBefore(LocalDate.now());
        return new ScheduleModels.Semester(
                "semester-" + System.currentTimeMillis(),
                now.getYear() + "-" + (now.getYear() + 1) + " 学年",
                now.withMonth(9).withDayOfMonth(1).toString(),
                now.withMonth(9).withDayOfMonth(1).plusWeeks(20).minusDays(1).toString(),
                20,
                13,
                ScheduleModels.buildDefaultSectionTimes(13)
        );
    }

    private ScheduleModels.Course defaultEditableCourse(String semesterId) {
        ScheduleModels.Course course = new ScheduleModels.Course(
                "course-" + System.currentTimeMillis(),
                "",
                semesterId,
                Arrays.asList(new ScheduleModels.TimeSlot("1-16", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(1, 2)))
        );
        course.color = ScheduleModels.PRESET_COLORS.get(0);
        return course;
    }

    private List<ScheduleModels.Course> coursesForSemester(String semesterId) {
        List<ScheduleModels.Course> out = new ArrayList<>();
        for (ScheduleModels.Course course : courses) if (course.semesterId.equals(semesterId)) out.add(course);
        return out;
    }

    private List<ScheduleModels.Course> sortedCourses(List<ScheduleModels.Course> input) {
        List<ScheduleModels.Course> out = new ArrayList<>(input);
        out.sort(Comparator.comparingInt((ScheduleModels.Course course) -> firstDay(course))
                .thenComparingInt(ScheduleModels.Course::startSection)
                .thenComparing(course -> course.name));
        return out;
    }

    private List<ScheduleModels.Course> coursesForWeek(ScheduleModels.Semester semester, int week) {
        List<ScheduleModels.Course> out = new ArrayList<>();
        for (ScheduleModels.Course course : coursesForSemester(semester.id)) {
            boolean matches = false;
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                if (ScheduleUtils.isWeekInRange(week, slot.weekRange) && ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)) {
                    matches = true;
                    break;
                }
            }
            if (matches) out.add(course);
        }
        return sortedCourses(out);
    }

    private List<ScheduleModels.Course> coursesForDate(LocalDate date, ScheduleModels.Semester semester) {
        List<ScheduleModels.Course> out = new ArrayList<>();
        if (semester == null) return out;
        int week = ScheduleUtils.weekNumberForDate(date, semester);
        int day = date.getDayOfWeek().getValue();
        for (ScheduleModels.Course course : coursesForWeek(semester, week)) {
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                if (slot.dayOfWeek == day && ScheduleUtils.isWeekInRange(week, slot.weekRange) && ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)) {
                    out.add(course);
                    break;
                }
            }
        }
        return sortedCourses(out);
    }

    private int currentScheduleWeek(ScheduleModels.Semester semester) {
        int baseWeek = baseScheduleWeek(semester);
        int weekCount = Math.max(1, semester.weekCount);
        int selectedWeek = Math.max(1, Math.min(weekCount, baseWeek + scheduleWeekOffset));
        scheduleWeekOffset = selectedWeek - baseWeek;
        return selectedWeek;
    }

    private int baseScheduleWeek(ScheduleModels.Semester semester) {
        int weekCount = Math.max(1, semester.weekCount);
        int current = ScheduleUtils.weekNumberForDate(LocalDate.now(), semester);
        return Math.max(1, Math.min(weekCount, current == 0 ? 1 : current));
    }

    private LocalDate weekStartForCurrentSelection(ScheduleModels.Semester semester) {
        return weekStartForSelection(semester, currentScheduleWeek(semester));
    }

    private LocalDate weekStartForSelection(ScheduleModels.Semester semester, int week) {
        return LocalDate.parse(semester.startDate).plusWeeks(week - 1L);
    }

    private ScheduleModels.Course courseStartingAt(List<ScheduleModels.Course> weekCourses, int week, int day, int section) {
        for (ScheduleModels.Course course : weekCourses) {
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                if (slot.dayOfWeek == day
                        && ScheduleUtils.isWeekInRange(week, slot.weekRange)
                        && ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)
                        && !slot.classSections.isEmpty()
                        && Collections.min(slot.classSections) == section) {
                    return course;
                }
            }
        }
        return null;
    }

    private int spanForCourse(ScheduleModels.Course course, int week, int day, int section) {
        int span = 1;
        for (ScheduleModels.TimeSlot slot : course.timeSlots) {
            if (slot.dayOfWeek == day
                    && ScheduleUtils.isWeekInRange(week, slot.weekRange)
                    && ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)
                    && !slot.classSections.isEmpty()
                    && Collections.min(slot.classSections) == section) {
                span = Math.max(span, slot.classSections.size());
            }
        }
        return span;
    }

    private int firstDay(ScheduleModels.Course course) {
        int day = 7;
        for (ScheduleModels.TimeSlot slot : course.timeSlots) day = Math.min(day, slot.dayOfWeek);
        return day;
    }

    private String primaryTimeForDate(ScheduleModels.Course course, LocalDate date) {
        ScheduleModels.Semester semester = selectedSemester();
        if (semester == null) return ScheduleUtils.formatCourseTime(course);
        int week = ScheduleUtils.weekNumberForDate(date, semester);
        int day = date.getDayOfWeek().getValue();
        return dayPrimarySectionLabel(course, week, day);
    }

    private ScheduleModels.TimeSlot primarySlotForDate(ScheduleModels.Course course, LocalDate date) {
        ScheduleModels.Semester semester = selectedSemester();
        if (semester == null) return null;
        int week = ScheduleUtils.weekNumberForDate(date, semester);
        int day = date.getDayOfWeek().getValue();
        ScheduleModels.TimeSlot earliest = null;
        for (ScheduleModels.TimeSlot slot : course.timeSlots) {
            if (slot.dayOfWeek != day
                    || !ScheduleUtils.isWeekInRange(week, slot.weekRange)
                    || !ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)
                    || slot.classSections.isEmpty()) continue;
            if (earliest == null || Collections.min(slot.classSections) < Collections.min(earliest.classSections)) {
                earliest = slot;
            }
        }
        return earliest;
    }

    private ScheduleModels.TimeSlot matchingSlot(ScheduleModels.Course course, int week, int day, int section) {
        for (ScheduleModels.TimeSlot slot : course.timeSlots) {
            if (slot.dayOfWeek == day
                    && ScheduleUtils.isWeekInRange(week, slot.weekRange)
                    && ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)
                    && !slot.classSections.isEmpty()
                    && Collections.min(slot.classSections) == section) return slot;
        }
        return null;
    }

    private String dayPrimarySectionLabel(ScheduleModels.Course course, int week, int day) {
        for (ScheduleModels.TimeSlot slot : course.timeSlots) {
            if (slot.dayOfWeek == day
                    && ScheduleUtils.isWeekInRange(week, slot.weekRange)
                    && ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)) {
                return ScheduleUtils.formatSections(slot.classSections);
            }
        }
        return ScheduleUtils.formatCourseTime(course);
    }

    private boolean hasSemesterOverlap(ScheduleModels.Semester candidate, String excludeId) {
        for (ScheduleModels.Semester semester : semesters) {
            if (semester.id.equals(excludeId)) continue;
            if (candidate.startDate.compareTo(semester.endDate) <= 0 && semester.startDate.compareTo(candidate.endDate) <= 0) return true;
        }
        return false;
    }

    private void adjustCoursesForSemester(String semesterId, int maxWeek, int maxSection) {
        List<ScheduleModels.Course> updated = new ArrayList<>();
        for (ScheduleModels.Course course : courses) {
            if (!course.semesterId.equals(semesterId)) {
                updated.add(course);
                continue;
            }
            List<ScheduleModels.TimeSlot> slots = new ArrayList<>();
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                List<Integer> weeks = new ArrayList<>();
                for (Integer week : ScheduleUtils.parseWeeks(slot.weekRange)) if (week <= maxWeek) weeks.add(week);
                List<Integer> sections = new ArrayList<>();
                for (Integer section : slot.classSections) if (section <= maxSection) sections.add(section);
                if (weeks.isEmpty() || sections.isEmpty()) continue;
                slot.weekRange = weeks.get(0).equals(weeks.get(weeks.size() - 1)) ? String.valueOf(weeks.get(0)) : weeks.get(0) + "-" + weeks.get(weeks.size() - 1);
                slot.classSections = sections;
                slots.add(slot);
            }
            course.timeSlots = slots;
            updated.add(course);
        }
        courses = updated;
    }

    private void replaceCoursesForSemester(List<ScheduleModels.Course> targetCourses, String semesterId, List<ScheduleModels.Course> imported) {
        List<ScheduleModels.Course> kept = new ArrayList<>();
        for (ScheduleModels.Course course : targetCourses) {
            if (!course.semesterId.equals(semesterId)) kept.add(course);
        }
        for (ScheduleModels.Course course : imported) {
            course.semesterId = semesterId;
            kept.add(course);
        }
        targetCourses.clear();
        targetCourses.addAll(kept);
    }

    private int findSemesterIndexByName(List<ScheduleModels.Semester> values, String name) {
        for (int i = 0; i < values.size(); i++) {
            if (values.get(i).name.equals(name)) return i;
        }
        return -1;
    }

    private List<ScheduleModels.TimeSlot> parseManualSlots(String raw) {
        List<ScheduleModels.TimeSlot> slots = new ArrayList<>();
        for (String line : raw.split("\n")) {
            slots.addAll(ScheduleImport.parseScheduleText(line.trim()));
        }
        return slots;
    }

    private String joinSlots(List<ScheduleModels.TimeSlot> slots) {
        List<String> values = new ArrayList<>();
        for (ScheduleModels.TimeSlot slot : slots) values.add(ScheduleUtils.formatSlot(slot));
        return ScheduleUtils.join(values, "\n");
    }

    private String emptyToNull(String value) {
        return value == null || value.trim().isEmpty() ? null : value.trim();
    }

    private Double parseDoubleOrNull(String value) {
        try {
            return value == null || value.trim().isEmpty() ? null : Double.parseDouble(value.trim());
        } catch (Exception ignored) {
            return null;
        }
    }

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(value);
        } catch (Exception ignored) {
            return fallback;
        }
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void addGap(LinearLayout layout, int heightDp) {
        View v = new View(this);
        layout.addView(v, new LinearLayout.LayoutParams(1, dp(heightDp)));
    }

    private void addHorizontalGap(LinearLayout layout, int widthDp) {
        View v = new View(this);
        layout.addView(v, new LinearLayout.LayoutParams(dp(widthDp), 1));
    }

    private int primaryColorWithAlpha(int alpha) {
        int base = primaryColor();
        return Color.argb(Math.max(0, Math.min(255, alpha)), Color.red(base), Color.green(base), Color.blue(base));
    }

    private int parseColorSafe(String value, int fallback) {
        try {
            return value == null ? fallback : Color.parseColor(value);
        } catch (Exception ignored) {
            return fallback;
        }
    }

    private int contrastText(int background) {
        double luminance = (0.2126 * Color.red(background) + 0.7152 * Color.green(background) + 0.0722 * Color.blue(background)) / 255.0;
        return luminance > 0.68 ? Color.rgb(25, 50, 77) : Color.WHITE;
    }

    private String weightedScore() {
        return weighted(false);
    }

    private String weightedPoint() {
        return weighted(true);
    }

    private String weighted(boolean usePoint) {
        double[] credits = new double[grades.size()];
        double[] values = new double[grades.size()];
        for (int i = 0; i < grades.size(); i++) {
            Grade grade = grades.get(i);
            credits[i] = grade.credits;
            Double value = usePoint ? grade.point : grade.score;
            values[i] = value == null ? Double.NaN : value;
        }
        double result = GradeMath.weightedAverage(credits, values);
        return Double.isNaN(result) ? "--" : (usePoint ? pointDf : scoreDf).format(result);
    }

    private String gradeSignature(List<Grade> values) {
        List<String> rows = new ArrayList<>();
        for (Grade g : values) rows.add(g.course + "|" + g.credits + "|" + g.point + "|" + g.score + "|" + g.detail);
        Collections.sort(rows);
        return rows.toString();
    }

    private List<UpdateDiff.Item> gradeDiffItems(List<Grade> values) {
        List<UpdateDiff.Item> items = new ArrayList<>();
        for (Grade grade : values) {
            String signature = grade.course + "|" + grade.credits + "|" + grade.point + "|"
                    + grade.score + "|" + grade.detail;
            items.add(new UpdateDiff.Item(grade.course, grade.course, signature));
        }
        return items;
    }

    private String scheduleSignature(List<ScheduleModels.Course> values) {
        List<String> rows = new ArrayList<>();
        for (ScheduleModels.Course course : values) {
            List<String> slots = new ArrayList<>();
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                slots.add(slot.weekRange + ":" + slot.repeatRule.name() + ":" + slot.dayOfWeek + ":" + slot.classSections);
            }
            Collections.sort(slots);
            rows.add(course.semesterId + "|" + course.name + "|" + course.code + "|" + course.location + "|" + slots);
        }
        Collections.sort(rows);
        return rows.toString();
    }

    private List<Grade> loadGrades() {
        try {
            String raw = store.getString("grades", "");
            if (raw == null || raw.isEmpty()) return new ArrayList<>();
            JSONArray array = new JSONArray(raw);
            List<Grade> out = new ArrayList<>();
            for (int i = 0; i < array.length(); i++) out.add(Grade.from(array.getJSONObject(i)));
            return out;
        } catch (Exception ignored) {
            return new ArrayList<>();
        }
    }

    private void saveGrades() {
        try {
            JSONArray array = new JSONArray();
            for (Grade grade : grades) array.put(grade.json());
            store.edit().putString("grades", array.toString()).apply();
        } catch (Exception ignored) {}
    }

    private void addAutomaticUpdateControls(LinearLayout parent, String title, String target) {
        parent.addView(section(title));
        LinearLayout control = card(surfaceColor());
        Switch enabled = new Switch(this);
        enabled.setText("自动更新");
        enabled.setTextColor(textColor());
        enabled.setChecked(isAutomaticEnabled(target));
        control.addView(enabled, new LinearLayout.LayoutParams(-1, dp(48)));

        LinearLayout intervalRow = new LinearLayout(this);
        intervalRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView intervalTitle = label("更新间隔", 13, mutedColor());
        intervalRow.addView(intervalTitle, new LinearLayout.LayoutParams(0, dp(44), 1));

        Button less = stepButton("−");
        EditText valueInput = new EditText(this);
        valueInput.setSingleLine(true);
        valueInput.setSelectAllOnFocus(true);
        valueInput.setGravity(Gravity.CENTER);
        valueInput.setIncludeFontPadding(false);
        valueInput.setTextSize(14);
        valueInput.setTextColor(textColor());
        valueInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        valueInput.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_DONE);
        valueInput.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(3)});
        valueInput.setPadding(dp(4), 0, dp(4), dp(1));
        valueInput.setBackground(border(panelColor(), lineColor(), 5));
        valueInput.setText(String.valueOf(intervalValue(target)));
        Button more = stepButton("+");
        Spinner unit = new Spinner(this);
        String[] units = {UNIT_MINUTES, UNIT_HOURS, UNIT_DAYS};
        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, units);
        unit.setAdapter(adapter);
        unit.setSelection(Arrays.asList(units).indexOf(intervalUnit(target)));
        intervalRow.addView(less, new LinearLayout.LayoutParams(dp(38), dp(38)));
        addHorizontalGap(intervalRow, 4);
        intervalRow.addView(valueInput, new LinearLayout.LayoutParams(dp(54), dp(38)));
        addHorizontalGap(intervalRow, 4);
        intervalRow.addView(more, new LinearLayout.LayoutParams(dp(38), dp(38)));
        addHorizontalGap(intervalRow, 8);
        intervalRow.addView(unit, new LinearLayout.LayoutParams(dp(104), dp(44)));
        control.addView(intervalRow);
        parent.addView(control);

        enabled.setOnCheckedChangeListener((button, checked) -> {
            setAutomaticEnabled(target, checked);
            if (checked) requestNotificationPermission();
            if (!checked && target.equals(automationTarget) && automaticRun) cancelAutomation();
            store.edit().remove("auto_last_" + target).apply();
            scheduleAllAutomaticUpdates(0L);
            syncBackgroundService();
        });
        less.setOnClickListener(v -> {
            setIntervalValue(target, Math.max(1, intervalValue(target) - 1));
            valueInput.setText(String.valueOf(intervalValue(target)));
            saveInterval(target);
        });
        more.setOnClickListener(v -> {
            setIntervalValue(target, Math.min(999, intervalValue(target) + 1));
            valueInput.setText(String.valueOf(intervalValue(target)));
            saveInterval(target);
        });
        valueInput.setOnFocusChangeListener((view, hasFocus) -> {
            if (!hasFocus) commitIntervalInput(valueInput, target, false);
        });
        valueInput.setOnEditorActionListener((view, actionId, event) -> {
            if (actionId != android.view.inputmethod.EditorInfo.IME_ACTION_DONE) return false;
            commitIntervalInput(valueInput, target, true);
            valueInput.clearFocus();
            android.view.inputmethod.InputMethodManager keyboard =
                    (android.view.inputmethod.InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
            if (keyboard != null) keyboard.hideSoftInputFromWindow(valueInput.getWindowToken(), 0);
            return true;
        });
        final boolean[] unitInitialized = {false};
        unit.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> parent, View view, int position, long id) {
                if (!unitInitialized[0]) {
                    unitInitialized[0] = true;
                    return;
                }
                if (units[position].equals(intervalUnit(target))) return;
                setIntervalUnit(target, units[position]);
                saveInterval(target);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) {}
        });
    }

    private void commitIntervalInput(EditText input, String target, boolean showError) {
        int parsed;
        try {
            parsed = Integer.parseInt(input.getText().toString().trim());
        } catch (Exception ignored) {
            parsed = -1;
        }
        if (parsed < 1 || parsed > 999) {
            input.setText(String.valueOf(intervalValue(target)));
            if (showError) Toast.makeText(this, "更新间隔请输入 1 到 999", Toast.LENGTH_SHORT).show();
            return;
        }
        input.setText(String.valueOf(parsed));
        if (parsed == intervalValue(target)) return;
        setIntervalValue(target, parsed);
        saveInterval(target);
    }

    private boolean isAutomaticEnabled(String target) {
        if ("schedule".equals(target)) return autoScheduleEnabled;
        if ("electricity".equals(target)) return autoElectricityEnabled;
        return autoGradeEnabled;
    }

    private void setAutomaticEnabled(String target, boolean enabled) {
        if ("schedule".equals(target)) autoScheduleEnabled = enabled;
        else if ("electricity".equals(target)) autoElectricityEnabled = enabled;
        else autoGradeEnabled = enabled;
        store.edit().putBoolean("auto_" + target.replace("grades", "grade") + "_enabled", enabled).apply();
    }

    private int intervalValue(String target) {
        if ("schedule".equals(target)) return scheduleIntervalValue;
        if ("electricity".equals(target)) return electricityIntervalValue;
        return gradeIntervalValue;
    }

    private void setIntervalValue(String target, int value) {
        if ("schedule".equals(target)) scheduleIntervalValue = value;
        else if ("electricity".equals(target)) electricityIntervalValue = value;
        else gradeIntervalValue = value;
    }

    private String intervalUnit(String target) {
        if ("schedule".equals(target)) return scheduleIntervalUnit;
        if ("electricity".equals(target)) return electricityIntervalUnit;
        return gradeIntervalUnit;
    }

    private void setIntervalUnit(String target, String unit) {
        if ("schedule".equals(target)) scheduleIntervalUnit = unit;
        else if ("electricity".equals(target)) electricityIntervalUnit = unit;
        else gradeIntervalUnit = unit;
    }

    private void saveInterval(String target) {
        String prefix = target.equals("grades") ? "grade" : target;
        store.edit()
                .putInt(prefix + "_interval_value", intervalValue(target))
                .putString(prefix + "_interval_unit", intervalUnit(target))
                .remove("auto_last_" + target)
                .apply();
        scheduleAllAutomaticUpdates(0L);
        syncBackgroundService();
    }

    private long intervalMillis(String target) {
        long multiplier = UNIT_DAYS.equals(intervalUnit(target)) ? 86_400_000L
                : UNIT_HOURS.equals(intervalUnit(target)) ? 3_600_000L : 60_000L;
        return Math.max(1, intervalValue(target)) * multiplier;
    }

    private String loadIntervalUnit(String key, String fallback) {
        String value = store.getString(key, fallback);
        return UNIT_MINUTES.equals(value) || UNIT_HOURS.equals(value) || UNIT_DAYS.equals(value) ? value : fallback;
    }

    private double parseStoredDouble(String key, double fallback) {
        try {
            return Double.parseDouble(store.getString(key, Double.toString(fallback)));
        } catch (Exception ignored) {
            return fallback;
        }
    }

    private String automationLabel(String target) {
        if ("schedule".equals(target)) return "课表";
        if ("electricity".equals(target)) return "电费";
        return "成绩";
    }

    private void saveElectricityThreshold(EditText input) {
        Double parsed = parseDoubleOrNull(input.getText().toString());
        if (parsed == null || parsed < 0) {
            Toast.makeText(this, "请输入有效报警余量", Toast.LENGTH_SHORT).show();
            return;
        }
        electricityAlertThreshold = parsed;
        store.edit().putString("electricity_alert_threshold", Double.toString(parsed))
                .putBoolean("electricity_alert_active", false).apply();
        Toast.makeText(this, "报警余量已保存", Toast.LENGTH_SHORT).show();
        if (!Double.isNaN(electricityBalance)) updateElectricityAlert(electricityBalance);
    }

    private void updateElectricityAlert(double balance) {
        boolean active = store.getBoolean("electricity_alert_active", false);
        boolean low = electricityAlertEnabled && balance < electricityAlertThreshold;
        if (low && !active) {
            Intent intent = new Intent(this, MainActivity.class);
            PendingIntent pending = PendingIntent.getActivity(this, 2, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            android.app.Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                    ? new android.app.Notification.Builder(this, ELECTRICITY_CHANNEL)
                    : new android.app.Notification.Builder(this);
            builder.setSmallIcon(R.drawable.ic_launcher)
                    .setContentTitle("电费余额不足")
                    .setContentText("剩余 " + scoreDf.format(balance) + " 元，低于 " + scoreDf.format(electricityAlertThreshold) + " 元")
                    .setAutoCancel(true)
                    .setContentIntent(pending);
            getSystemService(NotificationManager.class).notify(1002, builder.build());
        }
        store.edit().putBoolean("electricity_alert_active", low).apply();
    }

    private boolean hasCredentials() {
        String[] credentials = readCredentials();
        return !credentials[0].isEmpty() && !credentials[1].isEmpty();
    }

    private void bringAppToFront() {
        silentBoot = false;
        ActivityManager manager = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
        if (manager != null) manager.moveTaskToFront(getTaskId(), ActivityManager.MOVE_TASK_WITH_HOME);
    }

    private String maskAccount(String account) {
        return account.length() <= 4 ? account : account.substring(0, 2) + "***" + account.substring(account.length() - 2);
    }

    private String loadAsset(String name) {
        try (InputStream input = getAssets().open(name); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int read;
            while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
            return output.toString(StandardCharsets.UTF_8.name());
        } catch (Exception e) {
            throw new IllegalStateException("Missing automation asset", e);
        }
    }

    private String dayLabel(int value) {
        String[] values = {"", "周一", "周二", "周三", "周四", "周五", "周六", "周日"};
        return values[Math.max(1, Math.min(7, value))];
    }

    private class SafeClient extends WebViewClient {
        private final TextView status;

        SafeClient(TextView status) {
            this.status = status;
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            status.setText("正在识别教务页面…");
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, String url) {
            try {
                String host = Uri.parse(url).getHost();
                if (host != null && (host.equals("nwpu.edu.cn") || host.endsWith(".nwpu.edu.cn"))) return false;
            } catch (Exception ignored) {}
            if (!automaticRun) {
                Toast.makeText(MainActivity.this, "已拦截非西工大页面", Toast.LENGTH_SHORT).show();
            }
            return true;
        }
    }

    private static class Grade {
        String course;
        String category;
        String detail;
        double credits;
        Double point;
        Double score;

        Grade(String course, double credits, Double point, Double score, String category, String detail) {
            this.course = course;
            this.credits = credits;
            this.point = point;
            this.score = score;
            this.category = category;
            this.detail = detail;
        }

        String pointText() {
            return point == null ? "--" : String.format(Locale.US, "%.1f", point);
        }

        String scoreText() {
            return score == null ? "--" : String.format(Locale.US, "%.0f", score);
        }

        JSONObject json() {
            JSONObject o = new JSONObject();
            try {
                o.put("course", course).put("credits", credits).put("point", point == null ? JSONObject.NULL : point).put("score", score == null ? JSONObject.NULL : score).put("category", category).put("detail", detail);
            } catch (Exception ignored) {}
            return o;
        }

        static Grade from(JSONObject o) {
            return new Grade(
                    o.optString("course"),
                    o.optDouble("credits", 0),
                    o.isNull("point") ? null : o.optDouble("point"),
                    o.isNull("score") ? null : o.optDouble("score"),
                    o.optString("category", "必修"),
                    o.optString("detail", "")
            );
        }

        static Grade from(JSONArray c) {
            String course = c.optString(0);
            double credits = parse(c.optString(1));
            double point = parse(c.optString(2));
            double score = parse(c.optString(3));
            return new Grade(course, credits, Double.isNaN(point) ? null : point, Double.isNaN(score) ? null : score, "课程", c.optString(4));
        }

        static double parse(String x) {
            try {
                return Double.parseDouble(x.replaceAll("[^0-9.]", ""));
            } catch (Exception ignored) {
                return Double.NaN;
            }
        }
    }
}
