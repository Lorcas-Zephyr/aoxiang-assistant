package cn.nwpu.campus;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;

/** 新增/编辑手动日程的弹窗。保存后通过回调让列表页刷新。 */
final class ManualEventEditor {
    private final Activity activity;
    private final ManualEventUi ui;
    private final SharedPreferences store;
    private final List<ManualEvent> events;
    private final ManualEventConflictChecker conflicts;
    private final ManualEvent editing;
    private final LocalDate presetDate;
    private final Runnable onChanged;

    ManualEventEditor(Activity activity, ManualEventUi ui, SharedPreferences store,
                      List<ManualEvent> events, ManualEventConflictChecker conflicts,
                      ManualEvent editing, LocalDate presetDate, Runnable onChanged) {
        this.activity = activity;
        this.ui = ui;
        this.store = store;
        this.events = events;
        this.conflicts = conflicts;
        this.editing = editing;
        this.presetDate = presetDate;
        this.onChanged = onChanged;
    }

    void show() {
        boolean isEdit = editing != null;
        LocalDate initialDate = isEdit ? editing.localDate()
                : (presetDate == null ? LocalDate.now() : presetDate);
        final String[] chosenDate = {initialDate.toString()};
        final String[] startTime = {isEdit ? editing.startTime : "08:00"};
        final String[] endTime = {isEdit ? editing.endTime : "09:00"};
        final String[] chosenColor = {isEdit && editing.color != null
                ? editing.color : ManualEvent.DEFAULT_COLOR};

        LinearLayout form = new LinearLayout(activity);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(ui.dp(22), ui.dp(2), ui.dp(22), 0);
        ScrollView scroll = new ScrollView(activity);
        scroll.addView(form);

        EditText titleInput = ui.field(form, "日程名称", isEdit ? editing.title : "");
        ui.styleDialogInput(titleInput);
        ui.addFormLabel(form, "备注（可选）");
        EditText noteInput = ui.multilineField(form, "地点、要带的东西、补充说明…",
                isEdit && editing.note != null ? editing.note : "");

        ui.addFormLabel(form, "日期");
        TextView dateValue = ui.inputLike(ui.eventDateLabel(chosenDate[0]));
        dateValue.setOnClickListener(v -> ui.showDatePicker(chosenDate[0], value -> {
            chosenDate[0] = value;
            dateValue.setText(ui.eventDateLabel(value));
        }));
        form.addView(dateValue, new LinearLayout.LayoutParams(-1, ui.dp(48)));

        ui.addFormLabel(form, "时间");
        LinearLayout timeRow = new LinearLayout(activity);
        timeRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView startValue = ui.inputLike(startTime[0]);
        startValue.setOnClickListener(v -> ui.showTimePicker(startTime[0], value -> {
            startTime[0] = value;
            startValue.setText(value);
        }));
        timeRow.addView(startValue, new LinearLayout.LayoutParams(0, ui.dp(48), 1f));
        TextView dash = ui.label("至", 12, ui.mutedColor());
        dash.setGravity(Gravity.CENTER);
        timeRow.addView(dash, new LinearLayout.LayoutParams(ui.dp(30), ui.dp(48)));
        TextView endValue = ui.inputLike(endTime[0]);
        endValue.setOnClickListener(v -> ui.showTimePicker(endTime[0], value -> {
            endTime[0] = value;
            endValue.setText(value);
        }));
        timeRow.addView(endValue, new LinearLayout.LayoutParams(0, ui.dp(48), 1f));
        form.addView(timeRow);

        ui.addFormLabel(form, "重复");
        CheckBox weeklyInput = new CheckBox(activity);
        weeklyInput.setText("每周重复（按开始日期的星期几）");
        weeklyInput.setTextSize(12);
        weeklyInput.setTextColor(ui.textColor());
        weeklyInput.setChecked(isEdit && editing.weekly);
        weeklyInput.setButtonTintList(ColorStateList.valueOf(ui.primaryColor()));
        form.addView(weeklyInput);

        LinearLayout weeksBox = new LinearLayout(activity);
        weeksBox.setOrientation(LinearLayout.VERTICAL);
        LinearLayout weeksRow = new LinearLayout(activity);
        weeksRow.setGravity(Gravity.CENTER_VERTICAL);
        weeksRow.addView(ui.label("持续周数", 12, ui.textColor()),
                new LinearLayout.LayoutParams(0, -2, 1f));
        EditText weeksInput = new EditText(activity);
        weeksInput.setSingleLine(true);
        weeksInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        weeksInput.setHint("例如 3");
        weeksInput.setText(String.valueOf(isEdit && editing.weekly
                ? Math.max(1, editing.repeatWeeks) : 3));
        weeksInput.setTextSize(13);
        weeksInput.setTextColor(ui.textColor());
        weeksInput.setHintTextColor(ui.mutedColor());
        weeksInput.setPadding(ui.dp(14), 0, ui.dp(14), 0);
        weeksInput.setBackground(ui.border(ui.surfaceColor(), ui.lineColor(), 8));
        weeksRow.addView(weeksInput, new LinearLayout.LayoutParams(ui.dp(96), ui.dp(44)));
        weeksBox.addView(weeksRow);
        TextView weeksHint = ui.label("填 1-52，例如 3 表示连续三周；仅一次时无需填写。", 10, ui.mutedColor());
        weeksHint.setPadding(0, ui.dp(3), 0, 0);
        weeksBox.addView(weeksHint);
        weeksBox.setVisibility(weeklyInput.isChecked() ? View.VISIBLE : View.GONE);
        weeklyInput.setOnCheckedChangeListener((button, checked) -> {
            weeksBox.setVisibility(checked ? View.VISIBLE : View.GONE);
            if (checked && weeksInput.getText().toString().trim().isEmpty()) weeksInput.setText("3");
        });
        form.addView(weeksBox);

        ui.addFormLabel(form, "颜色");
        LinearLayout swatches = new LinearLayout(activity);
        swatches.setGravity(Gravity.CENTER_VERTICAL);
        form.addView(swatches);
        ui.refreshSwatches(swatches, chosenColor[0], value -> {
            chosenColor[0] = value;
            ui.refreshSwatches(swatches, value, ignored -> {});
        });

        AlertDialog.Builder builder = new AlertDialog.Builder(activity)
                .setTitle(isEdit ? "编辑日程" : "新增日程")
                .setView(scroll)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", null);
        if (isEdit) builder.setNeutralButton("删除", null);
        AlertDialog dialog = builder.create();
        dialog.setOnShowListener(ignored -> {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> save(dialog, isEdit,
                    titleInput, noteInput, weeklyInput, weeksInput, chosenDate, startTime, endTime, chosenColor));
            if (isEdit) {
                dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> {
                    dialog.dismiss();
                    confirmDelete();
                });
            }
        });
        dialog.show();
    }

    private void save(AlertDialog dialog, boolean isEdit, EditText titleInput, EditText noteInput,
                      CheckBox weeklyInput, EditText weeksInput, String[] chosenDate,
                      String[] startTime, String[] endTime, String[] chosenColor) {
        String title = titleInput.getText().toString().trim();
        if (title.isEmpty()) {
            toast("请输入日程名称");
            return;
        }
        try {
            LocalTime start = LocalTime.parse(startTime[0]);
            LocalTime end = LocalTime.parse(endTime[0]);
            if (!end.isAfter(start)) {
                toast("结束时间需晚于开始时间");
                return;
            }
            LocalDate date = LocalDate.parse(chosenDate[0]);
            boolean weekly = weeklyInput.isChecked();
            int weeks = 1;
            if (weekly) {
                try {
                    weeks = Integer.parseInt(weeksInput.getText().toString().trim());
                } catch (Exception parseError) {
                    weeks = 0;
                }
                if (weeks < 1 || weeks > 52) {
                    toast("持续周数需在 1-52 之间");
                    return;
                }
            }

            ManualEvent event = new ManualEvent(isEdit ? editing.id
                    : "event-" + System.currentTimeMillis(),
                    title, date.toString(), startTime[0], endTime[0]);
            event.note = emptyToNull(noteInput.getText().toString());
            event.color = chosenColor[0];
            event.weekly = weekly;
            event.repeatWeeks = weekly ? weeks : 1;

            String conflict = conflicts.findConflict(event, isEdit ? editing.id : null);
            if (conflict != null) {
                toastLong("时间冲突：" + conflict);
                return;
            }
            if (isEdit) {
                for (int i = 0; i < events.size(); i++) {
                    if (editing.id.equals(events.get(i).id)) {
                        events.set(i, event);
                        break;
                    }
                }
            } else {
                events.add(event);
            }
            ManualEventStore.save(store, events);
            dialog.dismiss();
            onChanged.run();
        } catch (Exception error) {
            toast("时间格式不正确");
        }
    }

    private void confirmDelete() {
        new AlertDialog.Builder(activity)
                .setTitle("删除日程")
                .setMessage("确定删除「" + editing.title + "」吗？")
                .setNegativeButton("取消", null)
                .setPositiveButton("删除", (confirm, which) -> {
                    events.remove(editing);
                    ManualEventStore.save(store, events);
                    onChanged.run();
                })
                .show();
    }

    private String emptyToNull(String value) {
        return value == null || value.trim().isEmpty() ? null : value.trim();
    }

    private void toast(String text) {
        Toast.makeText(activity, text, Toast.LENGTH_SHORT).show();
    }

    private void toastLong(String text) {
        Toast.makeText(activity, text, Toast.LENGTH_LONG).show();
    }
}
