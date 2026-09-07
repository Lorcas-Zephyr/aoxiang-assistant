package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

public class GoldenManifestTest {
    private static final Path GOLDEN_ROOT = locateGoldenRoot();
    private static final Set<String> ALLOWED_ROOT_FILES = new HashSet<>(Arrays.asList(
            "README.md", "manifest.json"
    ));
    private static final Set<String> REQUIRED_IDS = new HashSet<>(Arrays.asList(
            "grades-api-response", "grades-component-html", "grades-gpa-portrait-fallback",
            "grades-retake-same-name", "schedule-empty", "schedule-mixed-repeat",
            "schedule-non-contiguous", "schedule-friendship-summer", "schedule-friendship-winter",
            "schedule-teachers-locations", "schedule-online-filter", "electricity-settlement",
            "electricity-anomaly", "auth-states", "update-diff-notifications"
    ));
    private static final Set<String> SUPPORTED_KINDS = new HashSet<>(Arrays.asList(
            "grades-api", "grades-component-html", "grades-portrait-fallback", "grades-retake",
            "schedule-empty", "schedule-repeat-rules", "schedule-non-contiguous-weeks",
            "schedule-friendship-summer", "schedule-friendship-winter",
            "schedule-teachers-locations", "schedule-online-filter", "electricity-settlement",
            "electricity-anomaly", "authentication-states", "update-diff-notifications"
    ));
    private static final Set<String> FORBIDDEN_KEY_FRAGMENTS = new HashSet<>(Arrays.asList(
            "password", "cookie", "token", "account", "studentid", "studentno", "captcha",
            "smscode", "verificationcode", "authorization", "setcookie", "session", "secret"
    ));
    private static final Set<String> EXPECTED_ONLY_KEYS = new HashSet<>(Arrays.asList(
            "expected", "settlement", "deferexpected", "overdueexpected",
            "authexited", "credentialsvalid", "interactivelogin",
            "explicitcredentialerror", "gradechangednames", "schedulechangednames",
            "gradenotification", "schedulenotification", "selectedgpa"
    ));
    private static final Set<String> ALLOWED_VALUE_TOKENS = new HashSet<>(Arrays.asList(
            "sessionexpired"
    ));

    @Test public void manifestCoversEveryRequiredScenarioAndReferencedFile() throws Exception {
        JSONObject manifest = GoldenFixtureSupport.readJson("golden/v1/manifest.json");
        assertEquals(1, manifest.getInt("schemaVersion"));
        assertEquals("Asia/Shanghai", manifest.getString("businessTimeZone"));
        JSONArray scenarios = manifest.getJSONArray("scenarios");
        Map<String, String> referencedPaths = new HashMap<>();
        Set<String> actualIds = new HashSet<>();
        for (int i = 0; i < scenarios.length(); i++) {
            JSONObject scenario = scenarios.getJSONObject(i);
            String id = scenario.getString("id");
            assertTrue("duplicate scenario id: " + id, actualIds.add(id));
            String kind = scenario.getString("kind");
            assertNotNull(kind);
            assertTrue("unsupported scenario kind: " + kind, SUPPORTED_KINDS.contains(kind));
            assertNoForbiddenKeys(scenario);
            assertInputFixture(registerManifestPath(referencedPaths, id + ":input",
                    scenario.getString("input")));
            assertJsonFixture(registerManifestPath(referencedPaths, id + ":expected",
                    scenario.getString("expected")));
            if (scenario.has("html")) {
                String htmlPath = registerManifestPath(referencedPaths, id + ":html",
                        scenario.getString("html"));
                assertTrue("html fixture must end with .html: " + htmlPath,
                        htmlPath.endsWith(".html"));
                String html = GoldenFixtureSupport.readText("golden/v1/" + htmlPath);
                assertFalse("HTML fixture contains a secret field", hasSecretMarkup(html));
            }
        }
        assertEquals(REQUIRED_IDS, actualIds);
        assertEquals(expectedFixtureFiles(), new HashSet<>(referencedPaths.keySet()));
    }

    private static void assertJsonFixture(String path) throws Exception {
        assertTrue("json fixture must end with .json: " + path, path.endsWith(".json"));
        JSONObject fixture = GoldenFixtureSupport.readJson("golden/v1/" + path);
        assertNoForbiddenKeys(fixture);
    }

    private static void assertInputFixture(String path) throws Exception {
        JSONObject fixture = GoldenFixtureSupport.readJson("golden/v1/" + path);
        assertNoForbiddenKeys(fixture);
        assertNoExpectedOnlyKeys(fixture);
    }

    private static void assertNoExpectedOnlyKeys(Object value) throws Exception {
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            Iterator<String> keys = object.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                assertFalse("golden answer belongs in expected.json: " + key,
                        EXPECTED_ONLY_KEYS.contains(key.toLowerCase(Locale.ROOT)));
                assertNoExpectedOnlyKeys(object.opt(key));
            }
        } else if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) assertNoExpectedOnlyKeys(array.opt(i));
        }
    }

    private static void assertNoForbiddenKeys(Object value) throws Exception {
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            Iterator<String> keys = object.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                String normalized = normalizeToken(key);
                for (String fragment : FORBIDDEN_KEY_FRAGMENTS) {
                    assertFalse("forbidden fixture key: " + key, normalized.contains(fragment));
                }
                assertNoForbiddenKeys(object.opt(key));
            }
        } else if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) assertNoForbiddenKeys(array.opt(i));
        } else if (value instanceof String) {
            assertSafeString((String) value);
        }
    }

    private static boolean hasSecretMarkup(String html) {
        String lower = html.toLowerCase(Locale.ROOT);
        if (lower.contains("set-cookie") || lower.contains("authorization:")
                || lower.contains("type=\"password\"") || lower.contains("type='password'")) {
            return true;
        }
        String normalized = normalizeToken(html);
        for (String fragment : FORBIDDEN_KEY_FRAGMENTS) {
            if (normalized.contains(fragment)) return true;
        }
        return false;
    }

    private static String registerManifestPath(Map<String, String> referencedPaths, String owner,
                                               String rawPath) throws Exception {
        String path = canonicalFixturePath(rawPath);
        String previous = referencedPaths.put(path, owner);
        assertTrue("fixture path referenced multiple times: " + path, previous == null);
        return path;
    }

    private static String canonicalFixturePath(String rawPath) throws Exception {
        assertFalse("fixture path must not be empty", rawPath == null || rawPath.trim().isEmpty());
        assertFalse("fixture path must use forward slashes: " + rawPath, rawPath.contains("\\"));
        assertFalse("fixture path must be relative: " + rawPath,
                rawPath.startsWith("/") || rawPath.matches("^[A-Za-z]:.*"));
        for (String part : rawPath.split("/")) {
            assertFalse("fixture path must not contain traversal: " + rawPath, part.equals(".."));
        }
        Path normalized = Paths.get(rawPath).normalize();
        String path = normalized.toString().replace('\\', '/');
        assertFalse("fixture path must stay under golden/v1: " + rawPath,
                path.equals("..") || path.startsWith("../") || path.contains("/../"));
        assertFalse("fixture path must not start with ./ : " + rawPath, path.startsWith("./"));
        assertFalse("fixture path must point to a file: " + rawPath, path.endsWith("/"));
        return path;
    }

    private static Set<String> expectedFixtureFiles() throws Exception {
        List<Path> files;
        try (java.util.stream.Stream<Path> stream = Files.walk(GOLDEN_ROOT)) {
            files = stream.filter(Files::isRegularFile).collect(Collectors.toList());
        }
        List<String> fixtureFiles = new ArrayList<>();
        for (Path file : files) {
            String relative = GOLDEN_ROOT.relativize(file).toString().replace('\\', '/');
            assertFalse("unexpected root file: " + relative,
                    relative.indexOf('/') < 0 && !ALLOWED_ROOT_FILES.contains(relative));
            if (relative.equals("README.md") || relative.equals("manifest.json")) continue;

            String text = new String(Files.readAllBytes(file), StandardCharsets.UTF_8);
            if (relative.endsWith(".json")) {
                JSONObject json = new JSONObject(text);
                assertNoForbiddenKeys(json);
                if (!relative.endsWith("/expected.json")) assertNoExpectedOnlyKeys(json);
            } else if (relative.endsWith(".html")) {
                assertFalse("HTML fixture contains a secret field: " + relative,
                        hasSecretMarkup(text));
            }
            fixtureFiles.add(relative);
        }
        return new HashSet<>(fixtureFiles);
    }

    private static Path locateGoldenRoot() {
        Path current = Paths.get("").toAbsolutePath().normalize();
        while (current != null) {
            Path candidate = current.resolve(Paths.get("contract-fixtures", "golden", "v1"));
            if (Files.isDirectory(candidate)) return candidate;
            current = current.getParent();
        }
        throw new IllegalStateException("Cannot locate contract-fixtures/golden/v1 from "
                + Paths.get("").toAbsolutePath());
    }

    private static void assertSafeString(String value) {
        String normalized = normalizeToken(value);
        if (ALLOWED_VALUE_TOKENS.contains(normalized)) return;
        assertFalse("forbidden fixture value: " + value, normalized.contains("authorizationbearer"));
        assertFalse("forbidden fixture value: " + value, normalized.contains("setcookie"));
    }

    private static String normalizeToken(String value) {
        return value == null ? "" : value.replaceAll("[^A-Za-z0-9\\u4e00-\\u9fa5]", "")
                .toLowerCase(Locale.ROOT);
    }
}
