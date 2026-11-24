package cn.nwpu.campus;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;
import java.util.Locale;

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
        Map<String, ScheduleAggregate> grouped = new LinkedHashMap<>();
        if (courses == null) return new ArrayList<>();
        for (ScheduleModels.Course course : courses) {
            if (course == null) continue;
            String name = normalizeText(course.name);
            String code = normalizeText(course.code).toUpperCase(Locale.ROOT);
            String identity = code.isEmpty() ? name : code;
            String key = clean(course.semesterId) + "|" + identity;
            if (identity.isEmpty()) continue;
            ScheduleAggregate aggregate = grouped.computeIfAbsent(key, unused -> new ScheduleAggregate());
            if (!name.isEmpty()) aggregate.names.add(name);
            if (!code.isEmpty()) aggregate.codes.add(code);
            if (course.timeSlots != null) {
                for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                    if (slot == null) continue;
                    Set<Integer> weeks = effectiveWeeks(slot);
                    Set<Integer> sections = new TreeSet<>();
                    if (slot.classSections != null) sections.addAll(slot.classSections);
                    String location = normalizeText(ScheduleModels.cleanLocationText(
                            slot.location == null ? course.location : slot.location));
                    String teacher = canonicalPeople(slot.teacher == null ? course.teacher : slot.teacher).toString();
                    if (weeks.isEmpty()) {
                        // Invalid/legacy ranges should still participate in the diff instead of
                        // silently disappearing from the signature.
                        aggregate.slots.add("unparsed:" + normalizeText(slot.weekRange) + ":"
                                + slot.dayOfWeek + ":" + sections + ":" + location + ":" + teacher);
                        continue;
                    }
                    // Compare the actual weekly meetings, not the portal's grouping of them.
                    // The portal may alternate between one range and several rows, or encode
                    // odd/even occurrences as either a repeat rule or explicit week numbers.
                    for (Integer week : weeks) {
                        for (Integer section : sections) {
                            aggregate.slots.add(week + ":" + slot.dayOfWeek + ":" + section
                                    + ":" + location + ":" + teacher);
                        }
                    }
                }
            }
        }
        List<Item> items = new ArrayList<>();
        for (Map.Entry<String, ScheduleAggregate> entry : grouped.entrySet()) {
            ScheduleAggregate value = entry.getValue();
            String signature = value.names + "|" + value.codes + "|" + value.slots;
            items.add(new Item(entry.getKey(), join(value.names), signature));
        }
        return items;
    }

    private static final class ScheduleAggregate {
        final Set<String> names = new TreeSet<>();
        final Set<String> codes = new TreeSet<>();
        final Set<String> slots = new TreeSet<>();
    }

    private static Set<Integer> effectiveWeeks(ScheduleModels.TimeSlot slot) {
        Set<Integer> weeks = new TreeSet<>();
        ScheduleModels.RepeatRule rule = slot.repeatRule == null
                ? ScheduleModels.RepeatRule.ALL : slot.repeatRule;
        for (Integer week : ScheduleUtils.parseWeeks(slot.weekRange)) {
            if (ScheduleUtils.matchesRepeatRule(week, rule)) weeks.add(week);
        }
        return weeks;
    }

    private static Set<String> canonicalPeople(String value) {
        Set<String> people = new TreeSet<>();
        if (value == null) return people;
        for (String part : value.split("[,，、;/；|｜\\s]+")) {
            String cleaned = normalizeText(part);
            if (!cleaned.isEmpty()) people.add(cleaned);
        }
        return people;
    }

    private static String join(Set<String> values) {
        return String.join("、", values);
    }

    private static String normalizeText(String value) {
        return value == null ? "" : value.trim().replaceAll("\\s+", " ");
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
