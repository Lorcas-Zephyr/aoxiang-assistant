package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.json.JSONObject;

public class UpdateDiffTest {
    @Test public void returnsNoNamesWhenNothingChanged() {
        List<UpdateDiff.Item> values = Collections.singletonList(item("math", "高等数学", "90"));
        assertTrue(UpdateDiff.changedNames(values, values).isEmpty());
    }

    @Test public void detectsChangedAddedAndRemovedCourses() {
        List<UpdateDiff.Item> before = Arrays.asList(
                item("math", "高等数学", "90"),
                item("english", "大学英语", "80"));
        List<UpdateDiff.Item> after = Arrays.asList(
                item("math", "高等数学", "95"),
                item("physics", "大学物理", "88"));

        assertEquals(Arrays.asList("大学物理", "大学英语", "高等数学"),
                UpdateDiff.changedNames(before, after));
    }

    @Test public void treatsAFullImportAfterLocalDeletionAsAddedCourses() {
        List<UpdateDiff.Item> imported = Arrays.asList(
                item("math", "高等数学", "周一1-2节"),
                item("english", "大学英语", "周三3-4节"));

        assertEquals(Arrays.asList("大学英语", "高等数学"),
                UpdateDiff.changedNames(Collections.emptyList(), imported));
    }

    @Test public void formatsAFullGradeImportAfterLocalDeletionAsAnUpdate() {
        List<String> changed = UpdateDiff.changedNames(Collections.emptyList(), Arrays.asList(
                item("math", "高等数学", "90"),
                item("english", "大学英语", "85"),
                item("physics", "大学物理", "88")));

        assertEquals("大学物理、大学英语等 3 门成绩有更新",
                UpdateDiff.notificationText(changed, true));
    }

    @Test public void formatsCourseSpecificNotifications() {
        assertEquals("离散数学成绩有更新",
                UpdateDiff.notificationText(Collections.singletonList("离散数学"), true));
        assertEquals("大学英语、离散数学成绩有更新",
                UpdateDiff.notificationText(Arrays.asList("大学英语", "离散数学"), true));
        assertEquals("大学英语、离散数学等 3 门排课有更新",
                UpdateDiff.notificationText(Arrays.asList("大学英语", "离散数学", "高等数学"), false));
    }

    @Test public void ignoresCourseWhitespaceAndEquivalentDetailFormatting() throws Exception {
        GradeRecord before = GradeRecord.from(new JSONObject()
                .put("course", " 数据库 ")
                .put("credits", 3)
                .put("point", 4)
                .put("score", 95)
                .put("detail", "<span>期末成绩:95</span>"));
        GradeRecord after = GradeRecord.from(new JSONObject()
                .put("course", "数据库")
                .put("credits", 3.0)
                .put("point", 4.0)
                .put("score", 95.0)
                .put("detail", "&lt;span&gt;期末成绩:95&lt;/span&gt;"));

        assertTrue(UpdateDiff.changedNames(
                Collections.singletonList(new UpdateDiff.Item(before.diffKey(), before.course,
                        before.diffSignature())),
                Collections.singletonList(new UpdateDiff.Item(after.diffKey(), after.course,
                        after.diffSignature()))).isEmpty());
    }

    private static UpdateDiff.Item item(String key, String name, String signature) {
        return new UpdateDiff.Item(key, name, signature);
    }
}
