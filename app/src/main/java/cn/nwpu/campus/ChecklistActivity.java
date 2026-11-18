package cn.nwpu.campus;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.NotificationManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** 清单列表页。清单编辑、条目编辑、提醒选项分别在 ChecklistEditor、ChecklistItemDialog、ChecklistUi。 */
public class ChecklistActivity extends Activity {
    public static final String EXTRA_CHECKLIST_ID = "checklist_id";
    private static final int REQUEST_NOTIFICATIONS = 41;

    private SharedPreferences store;
    private ChecklistUi ui;
    private FrameLayout root;
    private ScrollView page;
    private LinearLayout column;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final List<Runnable> countdownTicks = new ArrayList<>();
    private final Map<String, View> cardViews = new HashMap<>();
    private final List<Checklist> renderedChecklists = new ArrayList<>();
    private TextView summaryLine;
    private boolean ticking;
    private String focusId = "";
    private boolean modified;

    private static final class ChecklistCardBinding {
        TextView countdown;
        TextView progressLabel;
        LinearLayout progressTrack;
    }

    private final Runnable ticker = new Runnable() {
        @Override
        public void run() {
            if (!ticking) return;
            for (Runnable tick : countdownTicks) {
                try {
                    tick.run();
                } catch (Exception ignored) {}
            }
            handler.postDelayed(this, 1000L);
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        store = getSharedPreferences("campus_private", MODE_PRIVATE);
        boolean dark = ScheduleStorage.loadDarkMode(store);
        ui = new ChecklistUi(this, dark, ScheduleStorage.loadThemeColor(store));
        focusId = getIntent().getStringExtra(EXTRA_CHECKLIST_ID);
        if (focusId == null) focusId = "";
        ChecklistReminderScheduler.ensureChannel(this);
        applyWindowTheme();
        buildRoot();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String id = intent.getStringExtra(EXTRA_CHECKLIST_ID);
        if (id != null && !id.isEmpty()) {
            focusId = id;
            render();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        render();
        startTicker();
    }

    @Override
    protected void onPause() {
        stopTicker();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        stopTicker();
        super.onDestroy();
    }

    @Override
    public void finish() {
        if (modified) setResult(RESULT_OK);
        super.finish();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQUEST_NOTIFICATIONS) return;
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            ChecklistReminderScheduler.rescheduleAll(this);
            Toast.makeText(this, "通知已开启，提醒会发送到手机", Toast.LENGTH_SHORT).show();
        } else {
            Toast.makeText(this, "通知未开启，打开应用时会补提醒", Toast.LENGTH_LONG).show();
        }
        render();
    }

    private void buildRoot() {
        root = new FrameLayout(this);
        root.setBackgroundColor(ui.backgroundColor());
        setContentView(root);
        applySystemBarInsets();

        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(10));

        ImageView back = ui.iconButton(R.drawable.ic_arrow_back, "返回");
        back.setOnClickListener(v -> finish());
        header.addView(back, new LinearLayout.LayoutParams(ui.dp(40), ui.dp(40)));

        LinearLayout heading = new LinearLayout(this);
        heading.setOrientation(LinearLayout.VERTICAL);
        heading.setPadding(ui.dp(12), 0, 0, 0);
        TextView title = ui.label("清单", 24, ui.textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        heading.addView(title);
        heading.addView(ui.label("截止倒计时 · 多清单 · 提醒", 11, ui.mutedColor()));
        header.addView(heading, new LinearLayout.LayoutParams(0, -2, 1));

        Button add = ui.action("新建", true);
        add.setOnClickListener(v -> openEditor(null));
        header.addView(add, new LinearLayout.LayoutParams(ui.dp(70), ui.dp(40)));
        shell.addView(header);

        page = new ScrollView(this);
        page.setFillViewport(true);
        page.setBackgroundColor(ui.backgroundColor());
        page.setSaveEnabled(false);
        column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(28));
        page.addView(column);
        shell.addView(page, new LinearLayout.LayoutParams(-1, 0, 1));
        root.addView(shell, new FrameLayout.LayoutParams(-1, -1));
    }

    private void applySystemBarInsets() {
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
            return insets;
        });
        root.requestApplyInsets();
    }

    private void render() {
        if (column == null) return;
        int scrollY = page.getScrollY();
        column.removeAllViews();
        countdownTicks.clear();
        cardViews.clear();

        List<Checklist> values = ChecklistStore.load(store);
        ChecklistStore.sortForDisplay(values, System.currentTimeMillis());
        renderedChecklists.clear();
        renderedChecklists.addAll(values);
        addSummary(values);
        if (DeviceCompat.isHuaweiFamily()) addHuaweiReminderCard();

        if (values.isEmpty()) {
            addEmptyState();
        } else {
            for (Checklist checklist : values) addChecklistCard(checklist);
        }

        int safeScroll = scrollY;
        page.post(() -> page.scrollTo(0, safeScroll));
        if (!focusId.isEmpty()) {
            View target = cardViews.get(focusId);
            if (target != null) {
                page.post(() -> page.smoothScrollTo(0, Math.max(0, target.getTop() - ui.dp(8))));
            }
            focusId = "";
        }
    }

    private void addSummary(List<Checklist> values) {
        int pending = 0;
        for (Checklist checklist : values) pending += checklist.pendingCount();
        LinearLayout summary = ui.card(ui.panelColor());
        summary.setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(12));
        TextView line = ui.label(values.size() + " 个清单 · " + pending + " 项待完成", 13, ui.textColor());
        line.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        summaryLine = line;
        summary.addView(line);
        summary.addView(ui.label("提醒会通过系统通知发送；通知被关闭时，打开应用会补提醒。",
                11, ui.mutedColor()));
        if (!notificationsEnabled()) {
            ui.addGap(summary, 8);
            LinearLayout warning = new LinearLayout(this);
            warning.setGravity(Gravity.CENTER_VERTICAL);
            TextView text = ui.label("通知未开启", 11, ui.warningColor());
            text.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            warning.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
            Button enable = ui.action("开启", false);
            enable.setOnClickListener(v -> requestNotifications());
            warning.addView(enable, new LinearLayout.LayoutParams(ui.dp(62), ui.dp(34)));
            summary.addView(warning);
        }
        column.addView(summary);
        ui.addGap(column, 10);
    }

    private void addHuaweiReminderCard() {
        LinearLayout card = ui.card(ui.panelColor());
        card.setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(12));
        TextView title = ui.label("鸿蒙 / 华为提醒设置", 13, ui.textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        card.addView(title);
        TextView hint = ui.label("HarmonyOS 可能限制后台提醒。建议允许通知、自启动和后台活动，并把电池优化设为“不限制”。",
                11, ui.mutedColor());
        hint.setLineSpacing(0, 1.15f);
        hint.setPadding(0, ui.dp(3), 0, ui.dp(2));
        card.addView(hint);
        LinearLayout actions = new LinearLayout(this);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(0, ui.dp(7), 0, 0);
        Button notify = ui.action("通知设置", false);
        notify.setTextSize(11);
        notify.setMinHeight(0);
        notify.setOnClickListener(v -> DeviceCompat.openNotificationSettings(this));
        actions.addView(notify, new LinearLayout.LayoutParams(0, ui.dp(36), 1));
        ui.addHorizontalGap(actions, 8);
        Button settings = ui.action("应用设置", true);
        settings.setTextSize(11);
        settings.setMinHeight(0);
        settings.setOnClickListener(v -> DeviceCompat.openAppSettings(this));
        actions.addView(settings, new LinearLayout.LayoutParams(0, ui.dp(36), 1));
        card.addView(actions);
        column.addView(card);
        ui.addGap(column, 10);
    }

    private void addEmptyState() {
        LinearLayout empty = ui.card(ui.panelColor());
        empty.setGravity(Gravity.CENTER_HORIZONTAL);
        empty.setPadding(ui.dp(18), ui.dp(28), ui.dp(18), ui.dp(24));
        TextView title = ui.label("还没有清单", 17, ui.textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        empty.addView(title);
        TextView hint = ui.label("把要交的作业、要买的东西或近期目标拆成事项，\n设置截止时间后会在首页倒计时。",
                12, ui.mutedColor());
        hint.setGravity(Gravity.CENTER);
        hint.setLineSpacing(0, 1.2f);
        empty.addView(hint, new LinearLayout.LayoutParams(-1, -2));
        ui.addGap(empty, 14);
        Button create = ui.action("创建第一个清单", true);
        create.setOnClickListener(v -> openEditor(null));
        empty.addView(create, new LinearLayout.LayoutParams(-1, ui.dp(44)));
        column.addView(empty);
    }

    private void addChecklistCard(Checklist checklist) {
        ChecklistCardBinding binding = new ChecklistCardBinding();
        LinearLayout card = ui.card(ui.panelColor());
        card.setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(10));

        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.TOP);
        LinearLayout textBox = new LinearLayout(this);
        textBox.setOrientation(LinearLayout.VERTICAL);
        TextView title = ui.label(checklist.title, 16, ui.textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setMaxLines(2);
        textBox.addView(title);
        TextView deadline = ui.label("截止 " + checklist.deadlineDisplay() + " · " + checklist.reminderLabel(),
                11, deadlineColor(checklist));
        deadline.setPadding(0, ui.dp(3), 0, 0);
        textBox.addView(deadline);
        top.addView(textBox, new LinearLayout.LayoutParams(0, -2, 1));

        LinearLayout countdownBox = new LinearLayout(this);
        countdownBox.setOrientation(LinearLayout.VERTICAL);
        countdownBox.setGravity(Gravity.END);
        TextView countdown = ui.label("", 13, ui.primaryColor());
        countdown.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        countdown.setGravity(Gravity.END);
        countdown.setMaxLines(1);
        countdownBox.addView(countdown);
        TextView progressLabel = ui.label(checklist.doneCount() + "/" + checklist.items.size() + " 已完成",
                10, ui.mutedColor());
        progressLabel.setGravity(Gravity.END);
        countdownBox.addView(progressLabel);
        binding.countdown = countdown;
        binding.progressLabel = progressLabel;
        top.addView(countdownBox, new LinearLayout.LayoutParams(-2, -2));
        card.addView(top);

        LinearLayout bar = ui.progressBar(checklist.progress());
        binding.progressTrack = bar;
        LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(-1, ui.dp(4));
        barParams.topMargin = ui.dp(10);
        card.addView(bar, barParams);

        if (checklist.items.isEmpty()) {
            TextView hint = ui.label("还没有事项，在下面添加第一条。", 12, ui.mutedColor());
            hint.setPadding(0, ui.dp(12), 0, ui.dp(2));
            card.addView(hint);
        } else {
            for (Checklist.Item item : checklist.items) card.addView(itemRow(checklist, item, binding));
        }

        LinearLayout addRow = new LinearLayout(this);
        addRow.setGravity(Gravity.CENTER_VERTICAL);
        addRow.setPadding(0, ui.dp(7), 0, 0);
        EditText input = ui.input("添加事项…");
        input.setSingleLine(true);
        input.setImeOptions(EditorInfo.IME_ACTION_DONE);
        input.setTextSize(13);
        addRow.addView(input, new LinearLayout.LayoutParams(0, ui.dp(42), 1));
        ui.addHorizontalGap(addRow, 8);
        Button add = ui.action("添加", true);
        add.setTextSize(12);
        add.setMinHeight(0);
        add.setOnClickListener(v -> addItem(checklist, input));
        input.setOnEditorActionListener((view, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                addItem(checklist, input);
                return true;
            }
            return false;
        });
        addRow.addView(add, new LinearLayout.LayoutParams(ui.dp(58), ui.dp(42)));
        card.addView(addRow);

        LinearLayout footer = new LinearLayout(this);
        footer.setGravity(Gravity.CENTER_VERTICAL);
        footer.setPadding(0, ui.dp(8), 0, 0);
        TextView reminder = ui.label(checklist.reminderMinutes < 0
                ? "未设置提醒" : "提醒 · " + checklist.reminderLabel(), 10, ui.mutedColor());
        footer.addView(reminder, new LinearLayout.LayoutParams(0, -2, 1));
        Button edit = ui.action("编辑清单", false);
        edit.setTextSize(11);
        edit.setMinHeight(0);
        edit.setOnClickListener(v -> openEditor(checklist));
        footer.addView(edit, new LinearLayout.LayoutParams(ui.dp(84), ui.dp(34)));
        card.addView(footer);

        column.addView(card);
        ui.addGap(column, 10);
        cardViews.put(checklist.id, card);
        registerCountdown(countdown, checklist);
    }

    private View itemRow(Checklist checklist, Checklist.Item item, ChecklistCardBinding binding) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, ui.dp(3), 0, ui.dp(3));

        CheckBox check = new CheckBox(this);
        check.setChecked(item.done);
        check.setButtonTintList(ColorStateList.valueOf(item.done ? ui.successColor() : ui.primaryColor()));
        check.setContentDescription(item.done ? "标记为未完成" : "标记为完成");
        row.addView(check, new LinearLayout.LayoutParams(ui.dp(36), ui.dp(40)));

        TextView text = ui.label(item.text, 13, item.done ? ui.mutedColor() : ui.textColor());
        text.setPadding(ui.dp(2), 0, ui.dp(4), 0);
        if (item.done) text.setPaintFlags(text.getPaintFlags() | Paint.STRIKE_THRU_TEXT_FLAG);
        text.setOnClickListener(v -> openItemDialog(checklist, item));
        row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));

        TextView more = ui.label("⋮", 20, ui.mutedColor());
        more.setGravity(Gravity.CENTER);
        more.setContentDescription("事项操作");
        more.setOnClickListener(v -> showItemMenu(more, checklist, item));
        row.addView(more, new LinearLayout.LayoutParams(ui.dp(30), ui.dp(40)));

        check.setOnCheckedChangeListener((button, checked) -> {
            if (item.done == checked) return;
            item.done = checked;
            check.setButtonTintList(ColorStateList.valueOf(checked
                    ? ui.successColor() : ui.primaryColor()));
            check.setContentDescription(checked ? "标记为未完成" : "标记为完成");
            text.setTextColor(checked ? ui.mutedColor() : ui.textColor());
            int flags = text.getPaintFlags();
            if (checked) {
                flags |= Paint.STRIKE_THRU_TEXT_FLAG;
            } else {
                flags &= ~Paint.STRIKE_THRU_TEXT_FLAG;
            }
            text.setPaintFlags(flags);

            checklist.updatedAt = System.currentTimeMillis();
            ChecklistStore.save(store, renderedChecklists);
            if (!checked) ChecklistStore.clearReminded(store, checklist);
            if (checklist.allDone()) {
                ChecklistReminderScheduler.cancel(this, checklist.id);
            } else {
                ChecklistReminderScheduler.schedule(this, checklist);
            }
            refreshChecklistCard(binding, checklist);
            updateSummaryText();
            modified = true;
        });
        return row;
    }

    private void addItem(Checklist checklist, EditText input) {
        String value = input.getText().toString().trim();
        if (value.isEmpty()) {
            Toast.makeText(this, "请输入事项内容", Toast.LENGTH_SHORT).show();
            return;
        }
        Checklist.Item item = new Checklist.Item("item-" + System.currentTimeMillis(), value);
        checklist.items.add(item);
        ChecklistStore.upsert(store, checklist);
        ChecklistStore.clearReminded(store, checklist);
        ChecklistReminderScheduler.schedule(this, checklist);
        modified = true;
        input.setText("");
        render();
    }

    private void showItemMenu(View anchor, Checklist checklist, Checklist.Item item) {
        PopupMenu menu = new PopupMenu(this, anchor);
        menu.getMenu().add("编辑事项");
        menu.getMenu().add("删除事项");
        menu.setOnMenuItemClickListener(choice -> {
            if ("编辑事项".contentEquals(choice.getTitle())) {
                openItemDialog(checklist, item);
            } else {
                confirm("删除事项", "确定删除「" + item.text + "」吗？", () -> {
                    checklist.items.remove(item);
                    ChecklistStore.upsert(store, checklist);
                    if (checklist.allDone()) {
                        ChecklistReminderScheduler.cancel(this, checklist.id);
                    } else {
                        ChecklistReminderScheduler.schedule(this, checklist);
                    }
                    modified = true;
                    render();
                });
            }
            return true;
        });
        menu.show();
    }

    private void openEditor(Checklist editing) {
        new ChecklistEditor(this, ui, store, editing, id -> {
            modified = true;
            if (id != null) focusId = id;
            render();
        }, this::notificationsEnabled, this::requestNotifications).show();
    }

    private void openItemDialog(Checklist checklist, Checklist.Item item) {
        new ChecklistItemDialog(this, ui, store, checklist, item, () -> {
            modified = true;
            render();
        }).show();
    }

    private void confirm(String title, String message, Runnable onConfirm) {
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setNegativeButton("取消", null)
                .setPositiveButton("删除", (dialog, which) -> onConfirm.run())
                .show();
    }

    private void refreshChecklistCard(ChecklistCardBinding binding, Checklist checklist) {
        if (binding == null) return;
        if (binding.progressLabel != null) {
            binding.progressLabel.setText(checklist.doneCount() + "/" + checklist.items.size() + " 已完成");
        }
        if (binding.progressTrack != null) {
            ui.fillProgressTrack(binding.progressTrack, checklist.progress());
        }
        updateChecklistCountdown(binding.countdown, checklist);
    }

    private void updateSummaryText() {
        if (summaryLine == null) return;
        int pending = 0;
        for (Checklist checklist : renderedChecklists) pending += checklist.pendingCount();
        summaryLine.setText(renderedChecklists.size() + " 个清单 · " + pending + " 项待完成");
    }

    private void updateChecklistCountdown(TextView view, Checklist checklist) {
        if (view == null) return;
        long now = System.currentTimeMillis();
        view.setText(checklist.compactCountdownText(now));
        if (checklist.allDone()) {
            view.setTextColor(ui.successColor());
        } else if (checklist.deadlineMillis() <= now) {
            view.setTextColor(ui.warningColor());
        } else {
            view.setTextColor(ui.primaryColor());
        }
    }

    private void registerCountdown(TextView view, Checklist checklist) {
        Runnable tick = () -> updateChecklistCountdown(view, checklist);
        tick.run();
        countdownTicks.add(tick);
    }

    private void startTicker() {
        if (ticking) return;
        ticking = true;
        handler.post(ticker);
    }

    private void stopTicker() {
        ticking = false;
        handler.removeCallbacks(ticker);
    }

    private void requestNotifications() {
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, REQUEST_NOTIFICATIONS);
            return;
        }
        try {
            Intent intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
            startActivity(intent);
        } catch (Exception ignored) {
            Toast.makeText(this, "请到系统设置中开启通知权限", Toast.LENGTH_LONG).show();
        }
    }

    private boolean notificationsEnabled() {
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
            return false;
        }
        NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        return manager != null && manager.areNotificationsEnabled();
    }

    private int deadlineColor(Checklist checklist) {
        if (checklist.allDone()) return ui.successColor();
        if (checklist.deadlineMillis() <= System.currentTimeMillis()) return ui.warningColor();
        return ui.mutedColor();
    }

    private void applyWindowTheme() {
        Window window = getWindow();
        window.setStatusBarColor(ui.backgroundColor());
        window.setNavigationBarColor(ui.panelColor());
        if (Build.VERSION.SDK_INT < 23) return;
        int flags = window.getDecorView().getSystemUiVisibility();
        if (ScheduleStorage.loadDarkMode(store)) {
            flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            if (Build.VERSION.SDK_INT >= 26) flags &= ~View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
        } else {
            flags |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            if (Build.VERSION.SDK_INT >= 26) flags |= View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
        }
        window.getDecorView().setSystemUiVisibility(flags);
    }
}
