package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.util.Arrays;
import java.util.List;

public class GradeRecordTest {
    @Test public void keepsHigherScoreForRetakenCourse() {
        List<GradeRecord> result = GradeRecord.keepHighest(Arrays.asList(
                grade("软件工程", 60.0, 1.0),
                grade(" 软件工程 ", 85.0, 3.5)
        ));

        assertEquals(1, result.size());
        assertEquals(85.0, result.get(0).score, 0.001);
    }

    @Test public void usesPointWhenNeitherRecordHasNumericScore() {
        List<GradeRecord> result = GradeRecord.keepHighest(Arrays.asList(
                grade("大学英语", null, 2.0),
                grade("大学英语", null, 3.0)
        ));

        assertEquals(1, result.size());
        assertEquals(3.0, result.get(0).point, 0.001);
    }

    @Test public void doesNotMergeDifferentCourses() {
        List<GradeRecord> result = GradeRecord.keepHighest(Arrays.asList(
                grade("高等数学", 90.0, 4.0),
                grade("线性代数", 80.0, 3.0)
        ));

        assertEquals(2, result.size());
    }

    private static GradeRecord grade(String course, Double score, Double point) {
        return new GradeRecord(course, 2.0, point, score, "课程", "");
    }
}
