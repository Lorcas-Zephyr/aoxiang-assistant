package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

public class GoldenGradeEdgeFixtureTest {
    @Test public void componentHtmlFixtureUsesTheSharedSanitizedDetail() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson(
                "golden/v1/grades-component-html/input.json");
        String html = GoldenFixtureSupport.readText(
                "golden/v1/grades-component-html/detail.html");
        JSONObject expected = GoldenFixtureSupport.readJson(
                "golden/v1/grades-component-html/expected.json");

        GradeRecord record = GradeRecord.from(input.put("detail", html));

        assertEquals(expected.getString("detail"), record.detail);
    }

    @Test public void missingApiGpaFallsBackToThePortraitFixture() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson(
                "golden/v1/grades-gpa-portrait-fallback/input.json");
        String portrait = GoldenFixtureSupport.readText(
                "golden/v1/grades-gpa-portrait-fallback/portrait.html");
        JSONObject expected = GoldenFixtureSupport.readJson(
                "golden/v1/grades-gpa-portrait-fallback/expected.json");

        JSONArray rows = PortalApiParsers.gradeRows(input.getJSONArray("gradeResponses"));
        double apiGpa = PortalApiParsers.gpa(input.getJSONObject("gpaResponse"));
        double portraitGpa = PortalApiParsers.portraitGpa(portrait);
        double selectedGpa = PortalApiParsers.selectGpa(apiGpa, portraitGpa);

        assertEquals(expected.getInt("gradeCount"), rows.length());
        assertTrue(expected.isNull("apiGpa"));
        assertTrue(Double.isNaN(apiGpa));
        assertEquals(expected.getDouble("portraitGpa"), portraitGpa, 0.0001);
        assertEquals(expected.getDouble("selectedGpa"), selectedGpa, 0.0001);
    }

    @Test public void sameNameRetakeFixtureKeepsTheHighestScore() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson(
                "golden/v1/grades-retake-same-name/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson(
                "golden/v1/grades-retake-same-name/expected.json");
        JSONArray source = input.getJSONArray("records");
        List<GradeRecord> records = new ArrayList<>();
        for (int i = 0; i < source.length(); i++) {
            records.add(GradeRecord.from(source.getJSONObject(i)));
        }

        List<GradeRecord> best = GradeRecord.keepHighest(records);

        assertEquals(expected.getJSONArray("records").length(), best.size());
        for (int i = 0; i < best.size(); i++) {
            assertEquals(expected.getJSONArray("records").getJSONObject(i).toString(),
                    best.get(i).json().toString());
        }
    }
}
