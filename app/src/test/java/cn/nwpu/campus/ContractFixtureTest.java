package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.stream.Collectors;

public class ContractFixtureTest {
    @Test public void backupFixtureIsReadableByThePortableContract() throws Exception {
        JSONObject fixture = readJson("backup/v1/minimal_schedule_backup.json");
        BackupContract.BackupData data = BackupContract.readDocument(fixture);

        assertEquals(BackupContract.CURRENT_SCHEMA_VERSION, data.schemaVersion);
        assertEquals(1, data.courses.length());
        assertEquals(1, data.semesters.length());
        assertEquals("semester-fixture-2026-spring", data.selectedSemesterId);
        assertNoSensitiveKeys(fixture);
    }

    @Test public void localGradeFixtureUsesTheVersionedArrayEnvelope() throws Exception {
        JSONObject fixture = readJson("local/v1/grades.json");
        LocalDataContract.DecodedArray decoded = LocalDataContract.decodeArray(fixture.toString());

        assertEquals(LocalDataContract.CURRENT_SCHEMA_VERSION, decoded.sourceVersion);
        assertEquals(2, decoded.items.length());
        assertEquals("课程A", decoded.items.getJSONObject(0).getString("course"));
    }

    @Test public void collectionFixtureFreezesKnownPhaseNames() throws Exception {
        JSONObject fixture = readJson("collection/v1/phases.json");
        JSONArray phases = fixture.getJSONArray("phases");

        assertEquals(1, fixture.getInt("schemaVersion"));
        assertTrue(phases.toString().contains("grade_api_raw"));
        assertTrue(phases.toString().contains("schedule_data"));
        assertTrue(phases.toString().contains("sms_required"));
    }

    private static JSONObject readJson(String path) throws Exception {
        InputStream stream = ContractFixtureTest.class.getClassLoader().getResourceAsStream(path);
        assertNotNull("Missing contract fixture: " + path, stream);
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            return new JSONObject(reader.lines().collect(Collectors.joining("\n")));
        }
    }

    private static void assertNoSensitiveKeys(JSONObject object) {
        String raw = object.toString().toLowerCase(java.util.Locale.ROOT);
        assertTrue(!raw.contains("password"));
        assertTrue(!raw.contains("cookie"));
        assertTrue(!raw.contains("sms"));
        assertTrue(!raw.contains("token"));
        assertTrue(!raw.contains("login_credentials"));
    }
}
