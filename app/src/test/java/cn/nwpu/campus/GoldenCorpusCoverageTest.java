package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Fails closed when a golden scenario is added without an Android behavior test.
 * The method map is intentionally explicit and scenario-scoped: adding a
 * fixture requires adding a named test method for its schema version and id.
 */
public class GoldenCorpusCoverageTest {
    private static final Pattern VERSION_PATTERN = Pattern.compile("^v([1-9][0-9]*)$");
    private static final Map<String, String> ANDROID_BEHAVIOR_TESTS =
            buildAndroidBehaviorTestRegistry();

    /**
     * The registry key deliberately includes both parts of the fixture identity.
     * A kind is a behavior category, not a unique test case: two scenarios may
     * share a kind while exercising different inputs or outputs.
     */
    private static Map<String, String> buildAndroidBehaviorTestRegistry() {
        Map<String, String> registry = new LinkedHashMap<>();
        register(registry, 1, "grades-api-response",
                "cn.nwpu.campus.GoldenGradesFixtureTest#gradesApiFixtureProducesThePublishedRowsAndGpa");
        register(registry, 1, "grades-component-html",
                "cn.nwpu.campus.GoldenGradeEdgeFixtureTest#componentHtmlFixtureUsesTheSharedSanitizedDetail");
        register(registry, 1, "grades-gpa-portrait-fallback",
                "cn.nwpu.campus.GoldenGradeEdgeFixtureTest#missingApiGpaFallsBackToThePortraitFixture");
        register(registry, 1, "grades-retake-same-name",
                "cn.nwpu.campus.GoldenGradeEdgeFixtureTest#sameNameRetakeFixtureKeepsTheHighestScore");
        register(registry, 1, "schedule-empty",
                "cn.nwpu.campus.GoldenScheduleFixtureTest#emptyScheduleFixturePreservesTheExplicitSemesterEnd");
        register(registry, 1, "schedule-mixed-repeat",
                "cn.nwpu.campus.GoldenScheduleFixtureTest#mixedRepeatFixtureKeepsARepeatRulePerWeekPart");
        register(registry, 1, "schedule-non-contiguous",
                "cn.nwpu.campus.GoldenScheduleFixtureTest#nonContiguousWeekFixtureDoesNotInventIntermediateWeeks");
        register(registry, 1, "schedule-friendship-summer",
                "cn.nwpu.campus.GoldenScheduleFixtureTest#friendshipSummerFixtureUsesSummerSectionTimes");
        register(registry, 1, "schedule-friendship-winter",
                "cn.nwpu.campus.GoldenScheduleFixtureTest#friendshipWinterFixtureUsesWinterSectionTimes");
        register(registry, 1, "schedule-teachers-locations",
                "cn.nwpu.campus.GoldenScheduleFixtureTest#multipleTeachersAndLocationsStayOnTheirOwnMeetings");
        register(registry, 1, "schedule-online-filter",
                "cn.nwpu.campus.GoldenScheduleFixtureTest#onlineScheduleFixtureIsFilteredBeforeExport");
        register(registry, 1, "electricity-settlement",
                "cn.nwpu.campus.GoldenOperationalFixtureTest#settlementFixtureFreezesTheAsiaShanghaiWindow");
        register(registry, 1, "electricity-anomaly",
                "cn.nwpu.campus.GoldenOperationalFixtureTest#electricityAnomalyFixtureFailsClosed");
        register(registry, 1, "auth-states",
                "cn.nwpu.campus.GoldenOperationalFixtureTest#authenticationFixtureFreezesOnlyObservableStates");
        register(registry, 1, "update-diff-notifications",
                "cn.nwpu.campus.GoldenOperationalFixtureTest#updateDiffFixtureFreezesNamesAndNotificationText");
        return Collections.unmodifiableMap(registry);
    }

    private static void register(Map<String, String> registry, int schemaVersion,
                                 String scenarioId, String testMethod) {
        String key = scenarioKey(schemaVersion, scenarioId);
        String previous = registry.put(key, testMethod);
        if (previous != null) {
            throw new IllegalStateException("Duplicate Android behavior test registration: " + key);
        }
    }

    private static String scenarioKey(int schemaVersion, String scenarioId) {
        return "v" + schemaVersion + "/" + scenarioId;
    }

    @Test
    public void everyGoldenVersionHasExplicitAndroidBehaviorCoverage() throws Exception {
        Path corpus = locateGoldenCorpus();
        List<Path> versions;
        try (java.util.stream.Stream<Path> stream = Files.list(corpus)) {
            versions = stream.filter(Files::isDirectory)
                    .filter(path -> VERSION_PATTERN.matcher(path.getFileName().toString()).matches())
                    .sorted((left, right) -> Integer.compare(version(left), version(right)))
                    .collect(Collectors.toList());
        }

        assertFalse("golden corpus must contain v1", versions.isEmpty());
        List<Integer> actualVersions = versions.stream()
                .map(GoldenCorpusCoverageTest::version)
                .collect(Collectors.toList());
        List<Integer> expectedVersions = new ArrayList<>();
        for (int i = 1; i <= actualVersions.get(actualVersions.size() - 1); i++) {
            expectedVersions.add(i);
        }
        assertEquals("golden versions must be contiguous from v1", expectedVersions, actualVersions);

        Set<String> manifestScenarioKeys = new HashSet<>();
        for (Path versionDirectory : versions) {
            JSONObject manifest = readJson(versionDirectory.resolve("manifest.json"));
            int directoryVersion = version(versionDirectory);
            assertEquals("manifest schemaVersion must match its directory", directoryVersion,
                    manifest.getInt("schemaVersion"));
            JSONArray scenarios = manifest.getJSONArray("scenarios");
            for (int i = 0; i < scenarios.length(); i++) {
                JSONObject scenario = scenarios.getJSONObject(i);
                String id = scenario.getString("id");
                String key = scenarioKey(directoryVersion, id);
                assertTrue("duplicate golden scenario key: " + key,
                        manifestScenarioKeys.add(key));
                assertRegisteredTestMethod(directoryVersion, id);
            }
        }
        assertEquals("Android coverage registry must match corpus schemaVersion/id entries",
                ANDROID_BEHAVIOR_TESTS.keySet(), manifestScenarioKeys);
    }

    @Test
    public void androidBehaviorRegistryIsScenarioScoped() {
        assertTrue("registry must use schemaVersion/id keys",
                ANDROID_BEHAVIOR_TESTS.containsKey(scenarioKey(1, "grades-api-response")));
        assertFalse("registry must not fall back to kind-only keys",
                ANDROID_BEHAVIOR_TESTS.containsKey("grades-api"));
    }

    private static void assertRegisteredTestMethod(int schemaVersion, String scenarioId)
            throws Exception {
        String key = scenarioKey(schemaVersion, scenarioId);
        String registration = ANDROID_BEHAVIOR_TESTS.get(key);
        assertNotNull("Missing Android behavior test registration for " + key, registration);
        int separator = registration.indexOf('#');
        assertTrue("Invalid Android behavior test registration: " + registration, separator > 0);
        Class<?> testClass = Class.forName(registration.substring(0, separator));
        Method method = testClass.getDeclaredMethod(registration.substring(separator + 1));
        assertNotNull(method);
    }

    private static JSONObject readJson(Path path) throws Exception {
        assertTrue("Missing golden manifest: " + path, Files.isRegularFile(path));
        return new JSONObject(new String(Files.readAllBytes(path), StandardCharsets.UTF_8));
    }

    private static int version(Path path) {
        Matcher matcher = VERSION_PATTERN.matcher(path.getFileName().toString());
        assertTrue("Invalid golden version directory: " + path, matcher.matches());
        return Integer.parseInt(matcher.group(1));
    }

    private static Path locateGoldenCorpus() {
        Path current = Paths.get("").toAbsolutePath().normalize();
        while (current != null) {
            Path candidate = current.resolve(Paths.get("contract-fixtures", "golden"));
            if (Files.isDirectory(candidate)) return candidate;
            current = current.getParent();
        }
        throw new IllegalStateException("Cannot locate contract-fixtures/golden from "
                + Paths.get("").toAbsolutePath());
    }
}
