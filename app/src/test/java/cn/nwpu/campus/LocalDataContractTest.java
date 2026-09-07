package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public class LocalDataContractTest {
    @Test public void readsLegacyBareArrayWithoutChangingItsItems() throws Exception {
        LocalDataContract.DecodedArray decoded = LocalDataContract.decodeArray(
                "[{\"course\":\"课程A\"}]");

        assertTrue(decoded.legacy);
        assertEquals(LocalDataContract.LEGACY_SCHEMA_VERSION, decoded.sourceVersion);
        assertEquals("课程A", decoded.items.getJSONObject(0).getString("course"));
    }

    @Test public void writesAndReadsVersionOneEnvelope() throws Exception {
        JSONArray items = new JSONArray().put(new JSONObject().put("value", 7));

        LocalDataContract.DecodedArray decoded = LocalDataContract.decodeArray(
                LocalDataContract.encodeArray(items));

        assertFalse(decoded.legacy);
        assertEquals(LocalDataContract.CURRENT_SCHEMA_VERSION, decoded.sourceVersion);
        assertEquals(7, decoded.items.getJSONObject(0).getInt("value"));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsAnEnvelopeWithoutSchemaVersion() throws Exception {
        LocalDataContract.decodeArray("{\"items\":[]}");
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsAnUnknownFutureSchema() throws Exception {
        LocalDataContract.decodeArray("{\"schemaVersion\":99,\"items\":[]}");
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsUnknownEnvelopeFieldsBeforeARewriteCouldDropThem() throws Exception {
        LocalDataContract.decodeArray(
                "{\"schemaVersion\":1,\"items\":[],\"futureField\":\"must-survive\"}");
    }

    @Test public void permitsReplacingOnlyRecognizedArrayShapes() {
        assertTrue(LocalDataContract.canSafelyReplace(""));
        assertTrue(LocalDataContract.canSafelyReplace("[]"));
        assertTrue(LocalDataContract.canSafelyReplace(
                "{\"schemaVersion\":1,\"items\":[]}"));
        assertFalse(LocalDataContract.canSafelyReplace(
                "{\"schemaVersion\":99,\"items\":[]}"));
        assertFalse(LocalDataContract.canSafelyReplace("not json"));
    }
}
