package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class GoldenOperationalFixtureTest {
    @Test public void settlementFixtureFreezesTheAsiaShanghaiWindow() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson(
                "golden/v1/electricity-settlement/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson(
                "golden/v1/electricity-settlement/expected.json");
        ZoneId zone = ZoneId.of(expected.getString("zone"));

        JSONArray samples = input.getJSONArray("samples");
        JSONArray expectedSamples = expected.getJSONArray("samples");
        assertEquals(expectedSamples.length(), samples.length());
        for (int i = 0; i < samples.length(); i++) {
            JSONObject sample = samples.getJSONObject(i);
            JSONObject answer = expectedSamples.getJSONObject(i);
            assertEquals(answer.getString("id"), sample.getString("id"));
            assertEquals(answer.getBoolean("settlement"),
                    SyncTimePolicy.isElectricitySettlementTime(
                            instant(sample.getString("instant")), zone));
        }
        JSONObject defer = input.getJSONObject("defer");
        assertEquals(instant(expected.getString("deferExpected")),
                SyncTimePolicy.deferElectricityDueAt(
                        instant(defer.getString("dueAt")), instant(defer.getString("now")), zone));
        JSONObject overdue = input.getJSONObject("overdue");
        assertEquals(instant(expected.getString("overdueExpected")),
                SyncTimePolicy.deferElectricityDueAt(
                        instant(overdue.getString("dueAt")), instant(overdue.getString("now")), zone));
    }

    @Test public void electricityAnomalyFixtureFailsClosed() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson("golden/v1/electricity-anomaly/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson("golden/v1/electricity-anomaly/expected.json");

        assertFixtureDouble(expected, "valid",
                PortalApiParsers.electricityBalance(input.getJSONObject("valid")));
        assertFixtureDouble(expected, "missing",
                PortalApiParsers.electricityBalance(input.getJSONObject("missing")));
        assertFixtureDouble(expected, "negative",
                PortalApiParsers.electricityBalance(input.getJSONObject("negative")));
        assertFixtureDouble(expected, "malformed",
                PortalApiParsers.electricityBalance(input.getJSONObject("malformed")));
    }

    @Test public void authenticationFixtureFreezesOnlyObservableStates() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson("golden/v1/auth-states/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson("golden/v1/auth-states/expected.json");
        JSONArray cases = input.getJSONArray("cases");
        JSONArray expectedCases = expected.getJSONArray("cases");

        for (int i = 0; i < cases.length(); i++) {
            JSONObject current = cases.getJSONObject(i);
            JSONObject answer = expectedCases.getJSONObject(i);
            UnifiedAuthTracker tracker = new UnifiedAuthTracker();
            JSONArray urls = current.getJSONArray("urls");
            for (int j = 0; j < urls.length(); j++) tracker.record(urls.getString(j));
            assertEquals(answer.getString("id"), current.getString("id"));
            assertEquals(answer.getBoolean("authExited"), tracker.hasExited());
            assertEquals(answer.getBoolean("credentialsValid"),
                    "credentials_valid".equals(current.getString("phase")));
            assertEquals(answer.getBoolean("interactiveLogin"),
                    AuthenticationPolicy.requiresInteractiveCollectionLogin(
                            current.getString("target"), current.getString("phase")));
            assertEquals(answer.getBoolean("explicitCredentialError"),
                    AuthenticationPolicy.isExplicitCredentialError(current.getString("phase")));
        }
    }

    @Test public void updateDiffFixtureFreezesNamesAndNotificationText() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson(
                "golden/v1/update-diff-notifications/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson(
                "golden/v1/update-diff-notifications/expected.json");

        List<UpdateDiff.Item> gradeBefore = items(input.getJSONObject("gradeCase").getJSONArray("before"));
        List<UpdateDiff.Item> gradeAfter = items(input.getJSONObject("gradeCase").getJSONArray("after"));
        List<String> gradeChanged = UpdateDiff.changedNames(gradeBefore, gradeAfter);
        assertStringList(expected.getJSONArray("gradeChangedNames"), gradeChanged);
        assertEquals(expected.getString("gradeNotification"),
                UpdateDiff.notificationText(gradeChanged, true));

        List<UpdateDiff.Item> scheduleBefore = items(input.getJSONObject("scheduleCase").getJSONArray("before"));
        List<UpdateDiff.Item> scheduleAfter = items(input.getJSONObject("scheduleCase").getJSONArray("after"));
        List<String> scheduleChanged = UpdateDiff.changedNames(scheduleBefore, scheduleAfter);
        assertStringList(expected.getJSONArray("scheduleChangedNames"), scheduleChanged);
        assertEquals(expected.getString("scheduleNotification"),
                UpdateDiff.notificationText(scheduleChanged, false));
    }

    private static long instant(String value) {
        return OffsetDateTime.parse(value).toInstant().toEpochMilli();
    }

    private static List<UpdateDiff.Item> items(JSONArray values) throws Exception {
        List<UpdateDiff.Item> result = new ArrayList<>();
        for (int i = 0; i < values.length(); i++) {
            JSONObject item = values.getJSONObject(i);
            result.add(new UpdateDiff.Item(item.getString("key"), item.getString("name"),
                    item.getString("signature")));
        }
        return result;
    }

    private static void assertStringList(JSONArray expected, List<String> actual) throws Exception {
        assertEquals(expected.length(), actual.size());
        for (int i = 0; i < actual.size(); i++) {
            assertEquals(expected.getString(i), actual.get(i));
        }
    }

    private static void assertFixtureDouble(JSONObject expected, String key, double actual)
            throws Exception {
        if (expected.isNull(key)) {
            assertTrue(Double.isNaN(actual));
            return;
        }
        assertEquals(expected.getDouble(key), actual, 0.0001);
    }
}
