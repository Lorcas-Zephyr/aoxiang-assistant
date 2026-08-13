package cn.nwpu.campus;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

final class UpdateDiff {
    static final class Item {
        final String key;
        final String name;
        final String signature;

        Item(String key, String name, String signature) {
            this.key = clean(key);
            this.name = clean(name);
            this.signature = signature == null ? "" : signature;
        }
    }

    private UpdateDiff() {}

    static List<String> changedNames(List<Item> before, List<Item> after) {
        Map<String, Item> oldItems = index(before);
        Map<String, Item> newItems = index(after);
        Set<String> keys = new LinkedHashSet<>();
        keys.addAll(oldItems.keySet());
        keys.addAll(newItems.keySet());

        Set<String> names = new LinkedHashSet<>();
        for (String key : keys) {
            Item oldItem = oldItems.get(key);
            Item newItem = newItems.get(key);
            if (oldItem == null || newItem == null || !Objects.equals(oldItem.signature, newItem.signature)) {
                String name = newItem != null ? newItem.name : oldItem.name;
                if (!name.isEmpty()) names.add(name);
            }
        }
        List<String> result = new ArrayList<>(names);
        Collections.sort(result);
        return result;
    }

    static String notificationText(List<String> courseNames, boolean grades) {
        if (courseNames == null || courseNames.isEmpty()) return grades ? "成绩有更新" : "课表有更新";
        String suffix = grades ? "成绩有更新" : "排课有更新";
        if (courseNames.size() == 1) return courseNames.get(0) + suffix;
        if (courseNames.size() == 2) return courseNames.get(0) + "、" + courseNames.get(1) + suffix;
        return courseNames.get(0) + "、" + courseNames.get(1) + "等 " + courseNames.size() + " 门" + suffix;
    }

    static List<Item> scheduleItems(List<ScheduleModels.Course> courses) {
        List<Item> items = new ArrayList<>();
        if (courses == null) return items;
        for (ScheduleModels.Course course : courses) {
            List<String> slots = new ArrayList<>();
            if (course.timeSlots != null) {
                for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                    slots.add(clean(slot.weekRange) + ":" + slot.repeatRule.name() + ":"
                            + slot.dayOfWeek + ":" + slot.classSections);
                }
            }
            Collections.sort(slots);
            String identity = clean(course.code).isEmpty() ? clean(course.name) : clean(course.code);
            String key = clean(course.semesterId) + "|" + identity;
            String signature = clean(course.name) + "|" + clean(course.code) + "|"
                    + clean(course.location) + "|" + clean(course.teacher) + "|" + slots;
            items.add(new Item(key, course.name, signature));
        }
        return items;
    }

    private static Map<String, Item> index(List<Item> items) {
        Map<String, Item> result = new LinkedHashMap<>();
        if (items == null) return result;
        for (Item item : items) {
            if (item != null && !item.key.isEmpty()) result.put(item.key, item);
        }
        return result;
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
