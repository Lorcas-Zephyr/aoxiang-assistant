package cn.nwpu.campus;

import static org.junit.Assert.assertNotNull;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.stream.Collectors;

final class GoldenFixtureSupport {
    private GoldenFixtureSupport() {}

    static JSONObject readJson(String path) throws Exception {
        InputStream stream = GoldenFixtureSupport.class.getClassLoader().getResourceAsStream(path);
        assertNotNull("Missing golden fixture: " + path, stream);
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            return new JSONObject(reader.lines().collect(Collectors.joining("\n")));
        }
    }

    static String readText(String path) throws Exception {
        InputStream stream = GoldenFixtureSupport.class.getClassLoader().getResourceAsStream(path);
        assertNotNull("Missing golden fixture: " + path, stream);
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            return reader.lines().collect(Collectors.joining("\n"));
        }
    }
}
