package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public class GoldenGradesFixtureTest {
    @Test public void gradesApiFixtureProducesThePublishedRowsAndGpa() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson(
                "golden/v1/grades-api-response/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson(
                "golden/v1/grades-api-response/expected.json");

        JSONArray rows = PortalApiParsers.gradeRows(input.getJSONArray("gradeResponses"));
        assertEquals(expected.getJSONArray("rawRows").toString(), rows.toString());
        double apiGpa = PortalApiParsers.gpa(input.getJSONObject("gpaResponse"));
        assertEquals(expected.getDouble("gpa"),
                PortalApiParsers.selectGpa(apiGpa, Double.NaN), 0.0001);

        JSONArray details = new JSONArray();
        for (int i = 0; i < rows.length(); i++) {
            details.put(GradeRecord.from(rows.getJSONArray(i)).detail);
        }
        assertEquals(expected.getJSONArray("normalizedDetails").toString(), details.toString());
    }
}
