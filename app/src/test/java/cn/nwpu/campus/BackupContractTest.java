package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Collections;
import java.time.ZoneOffset;

public class BackupContractTest {
    @Test public void createsVersionedBackupWithOnlyPortableData() throws Exception {
        JSONObject backup = BackupContract.createDocument(
                Collections.emptyList(), Collections.emptyList(), "", null, false,
                LocalDate.of(2026, 1, 15));

        assertEquals(BackupContract.FORMAT, backup.getString(BackupContract.KEY_FORMAT));
        assertEquals(BackupContract.CURRENT_SCHEMA_VERSION,
                backup.getInt(BackupContract.KEY_SCHEMA_VERSION));
        assertEquals("2026-01-15", backup.getString(BackupContract.KEY_EXPORT_DATE));
        assertFalse(backup.toString().contains("password"));
        assertFalse(backup.toString().contains("cookie"));
        assertFalse(backup.toString().contains("sms"));
        assertFalse(backup.toString().contains("login_credentials"));
    }

    @Test public void readsLegacyV20BackupAndMarksItForMigration() throws Exception {
        JSONObject legacy = new JSONObject()
                .put("version", "2.0")
                .put("exportDate", "2026-01-15")
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject()
                        .put("semesters", new org.json.JSONArray())
                        .put("themeColor", "#2F80ED")
                        .put("darkMode", false));

        BackupContract.BackupData data = BackupContract.readDocument(legacy);

        assertTrue(data.legacy);
        assertEquals(BackupContract.LEGACY_SCHEMA_VERSION, data.schemaVersion);
        assertEquals("#2F80ED", data.themeColor);
        assertEquals(BackupContract.CURRENT_SCHEMA_VERSION,
                BackupContract.migrateToCurrent(legacy)
                        .getInt(BackupContract.KEY_SCHEMA_VERSION));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsUnknownLegacyVersion() throws Exception {
        BackupContract.readDocument(new JSONObject()
                .put("version", "1.0")
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject()));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsFutureBackupSchema() throws Exception {
        BackupContract.readDocument(new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", 99)
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject()));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsStringSchemaVersionInsteadOfCoercingIt() throws Exception {
        BackupContract.readDocument(new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", "1")
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject().put("semesters", new org.json.JSONArray())));
    }

    @Test(expected = org.json.JSONException.class)
    public void currentBackupRequiresTheSemestersArray() throws Exception {
        BackupContract.readDocument(new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", BackupContract.CURRENT_SCHEMA_VERSION)
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject()));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsLegacyShapeWhenItContainsCurrentFormatMarker() throws Exception {
        BackupContract.readDocument(new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("version", "2.0")
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject()));
    }

    @Test public void migrationPreservesUnknownFieldsInLegacyRecords() throws Exception {
        JSONObject legacy = new JSONObject()
                .put("version", "2.0")
                .put("exportDate", "2026-01-15")
                .put("courses", new org.json.JSONArray().put(new JSONObject()
                        .put("id", "course-fixture")
                        .put("semesterId", "semester-fixture")
                        .put("futureField", "must-survive")))
                .put("settings", new JSONObject()
                        .put("semesters", new org.json.JSONArray().put(new JSONObject()
                                .put("id", "semester-fixture")))
                        .put("themeColor", "#2F80ED")
                        .put("darkMode", false));

        JSONObject migrated = BackupContract.migrateToCurrent(legacy);

        assertEquals("must-survive", migrated.getJSONArray("courses")
                .getJSONObject(0).getString("futureField"));
    }

    @Test(expected = org.json.JSONException.class)
    public void migrationRejectsRecordsThatCannotBeImportedSafely() throws Exception {
        JSONObject legacy = new JSONObject()
                .put("version", "2.0")
                .put("courses", new org.json.JSONArray().put(new JSONObject()
                        .put("id", "course-fixture")))
                .put("settings", new JSONObject()
                        .put("semesters", new org.json.JSONArray()));

        BackupContract.migrateToCurrent(legacy);
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsUnknownTopLevelFieldsInsteadOfDroppingThemOnMigration() throws Exception {
        JSONObject legacy = new JSONObject()
                .put("version", "2.0")
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject().put("semesters", new org.json.JSONArray()))
                .put("futureTopLevelField", "must-not-be-dropped");

        BackupContract.readDocument(legacy);
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsUnknownSettingsFieldsInsteadOfDroppingThemOnMigration() throws Exception {
        JSONObject legacy = new JSONObject()
                .put("version", "2.0")
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject()
                        .put("semesters", new org.json.JSONArray())
                        .put("futureSetting", true));

        BackupContract.readDocument(legacy);
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsSensitiveKeysAnywhereInTheBackup() throws Exception {
        JSONObject current = new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", BackupContract.CURRENT_SCHEMA_VERSION)
                .put("courses", new org.json.JSONArray().put(new JSONObject()
                        .put("id", "course-fixture")
                        .put("semesterId", "semester-fixture")
                        .put("access_token", "must-not-be-exported")))
                .put("settings", new JSONObject()
                        .put("semesters", new org.json.JSONArray().put(new JSONObject()
                                .put("id", "semester-fixture"))));

        BackupContract.readDocument(current);
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsMalformedExportDateInsteadOfRewritingItToToday() throws Exception {
        JSONObject current = new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", BackupContract.CURRENT_SCHEMA_VERSION)
                .put("exportDate", "2026-99-99")
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject()
                        .put("semesters", new org.json.JSONArray()));

        BackupContract.migrateToCurrent(current);
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsBackupImportWhenCourseIdIsMissing() throws Exception {
        JSONObject backup = new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", BackupContract.CURRENT_SCHEMA_VERSION)
                .put("courses", new org.json.JSONArray().put(new JSONObject()
                        .put("name", "课程")
                        .put("semesterId", "semester-stable")))
                .put("settings", new JSONObject().put("semesters", new org.json.JSONArray()));

        BackupContract.validateForImport(BackupContract.readDocument(backup));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsNumericCourseIdInsteadOfCoercingItToAString() throws Exception {
        JSONObject backup = new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", BackupContract.CURRENT_SCHEMA_VERSION)
                .put("courses", new org.json.JSONArray().put(new JSONObject()
                        .put("id", 123)
                        .put("name", "课程")
                        .put("semesterId", "semester-stable")))
                .put("settings", new JSONObject().put("semesters", new org.json.JSONArray()
                        .put(new JSONObject().put("id", "semester-stable"))));

        BackupContract.validateForImport(BackupContract.readDocument(backup));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsNumericEnumInsteadOfCoercingItToAString() throws Exception {
        JSONObject backup = new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", BackupContract.CURRENT_SCHEMA_VERSION)
                .put("courses", new org.json.JSONArray().put(new JSONObject()
                        .put("id", "course-stable")
                        .put("name", "课程")
                        .put("semesterId", "semester-stable")
                        .put("assessmentMethod", 1)
                        .put("timeSlots", new org.json.JSONArray().put(new JSONObject()
                                .put("repeatRule", 1)))))
                .put("settings", new JSONObject().put("semesters", new org.json.JSONArray()
                        .put(new JSONObject().put("id", "semester-stable"))));

        BackupContract.validateForImport(BackupContract.readDocument(backup));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsBackupImportWhenSelectedSemesterDoesNotExist() throws Exception {
        JSONObject backup = new JSONObject()
                .put("format", BackupContract.FORMAT)
                .put("schemaVersion", BackupContract.CURRENT_SCHEMA_VERSION)
                .put("courses", new org.json.JSONArray())
                .put("settings", new JSONObject()
                        .put("semesters", new org.json.JSONArray().put(new JSONObject()
                                .put("id", "semester-stable")))
                        .put("selectedSemesterId", "semester-missing"));

        BackupContract.validateForImport(BackupContract.readDocument(backup));
    }

    @Test public void defaultExportDateUsesShanghaiBusinessCalendar() throws Exception {
        Clock clock = Clock.fixed(Instant.parse("2025-12-31T16:30:00Z"), ZoneOffset.UTC);

        assertEquals(LocalDate.of(2026, 1, 1), BackupContract.today(clock));
    }
}
