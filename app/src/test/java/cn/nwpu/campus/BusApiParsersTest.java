package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.util.List;

/**
 * 校车接口解析测试。
 *
 * 样例取自 docs/HQ_BUS_API.md 记录的真实响应结构，数值已脱敏。
 */
public class BusApiParsersTest {
    private static JSONObject routeByTypeResponse() throws Exception {
        JSONObject routeA = new JSONObject()
                .put("Objid", "route-a")
                .put("Type", "通勤车")
                .put("Name", "友谊到长安")
                .put("StartStation", "友谊校区")
                .put("EndStation", "长安校区")
                .put("StudentCharge", "5")
                .put("TeacherStaffCharge", "0");
        JSONObject routeB = new JSONObject()
                .put("Objid", "route-b")
                .put("Type", "通勤车")
                .put("Name", "长安到友谊")
                .put("StudentCharge", "5");
        return new JSONObject()
                .put("isSuccess", true)
                .put("data", new JSONObject()
                        .put("filteredBusRoutes", new JSONArray().put(routeA).put(routeB))
                        .put("reservationDays", new JSONObject().put("TQYYXZTS", "2"))
                        .put("isNeedServerTime", true))
                .put("IsOpenDialog", false);
    }

    @Test public void parsesRoutesAndReserveDays() throws Exception {
        JSONObject response = routeByTypeResponse();
        List<BusModels.Route> routes = BusApiParsers.routes(response);

        assertTrue(BusApiParsers.isSuccess(response));
        assertEquals(2, routes.size());
        assertEquals("route-a", routes.get(0).objId);
        assertEquals("友谊到长安", routes.get(0).name);
        assertEquals("友谊校区 → 长安校区", routes.get(0).stationText());
        assertEquals("学生 5 元 · 教职工 0 元", routes.get(0).chargeText());
        assertEquals(2, BusApiParsers.reserveDays(response));
    }

    @Test public void tripsTreatKyyrsAsCapacityAndSfkyyAsOpenFlag() throws Exception {
        JSONObject closed = new JSONObject()
                .put("objId", "trip-closed").put("fcsj", "06:40")
                .put("yyrs", 30).put("kyyrs", "30").put("sfkyy", false);
        JSONObject scarce = new JSONObject()
                .put("objId", "trip-scarce").put("fcsj", "20:00")
                .put("yyrs", 68).put("kyyrs", "70").put("sfkyy", true)
                .put("yyjzxx", "2026-09-24 19:30截止预约");
        JSONObject response = new JSONObject()
                .put("isSuccess", true)
                .put("data", new JSONArray().put(closed).put(scarce));

        BusModels.Route route = new BusModels.Route();
        route.objId = "route-a";
        route.name = "友谊到长安";
        List<BusModels.Trip> trips = BusApiParsers.trips(response, "2026-09-24", route);

        assertEquals(2, trips.size());
        assertEquals("友谊到长安", trips.get(0).routeName);
        assertEquals("2026-09-24", trips.get(0).date);
        assertEquals(0, trips.get(0).remaining);
        assertFalse(trips.get(0).open);
        assertEquals(2, trips.get(1).remaining);
        assertTrue(trips.get(1).open);
        assertTrue(trips.get(1).scarce());
        assertEquals("余 2 / 70", trips.get(1).seatText());
    }

    @Test public void tripsWithoutSeatFieldsStayUnknown() throws Exception {
        JSONObject response = new JSONObject()
                .put("data", new JSONArray().put(new JSONObject()
                        .put("objId", "trip-x").put("fcsj", "9:05")));
        List<BusModels.Trip> trips = BusApiParsers.trips(response, "2026-09-24", null);

        assertEquals(1, trips.size());
        assertEquals(-1, trips.get(0).remaining);
        assertEquals("已截止", trips.get(0).seatText());
    }

    @Test public void parsesReservationsByCandidateKeys() throws Exception {
        JSONObject item = new JSONObject()
                .put("yydh", "YY20260924001")
                .put("yyzt", "待核验")
                .put("xlmc", "友谊到长安")
                .put("ccrq", "2026/9/24")
                .put("fcsj", "10:00")
                .put("fy", "5");
        JSONObject response = new JSONObject()
                .put("isSuccess", true)
                .put("data", new JSONObject().put("list", new JSONArray().put(item)));

        List<BusModels.Reservation> reservations = BusApiParsers.reservations(response);

        assertEquals(1, reservations.size());
        BusModels.Reservation reservation = reservations.get(0);
        assertEquals("YY20260924001", reservation.orderNo);
        assertEquals("待核验", reservation.status);
        assertEquals("友谊到长安", reservation.title());
        assertTrue(reservation.pending());
        assertFalse(reservation.rejected());
        assertEquals("2026-09-24", reservation.date);
        assertTrue(reservation.departureAt() != null);
        assertTrue(reservation.summary.contains("yydh") || reservation.summary.contains("fy"));
    }

    @Test public void emptyOrBrokenPayloadsDoNotThrow() {
        assertTrue(BusApiParsers.routes(null).isEmpty());
        assertTrue(BusApiParsers.reservations(new JSONObject()).isEmpty());
        assertTrue(BusApiParsers.trips(null, "2026-09-24", null).isEmpty());
        assertEquals(0, BusApiParsers.reserveDays(new JSONObject()));
        assertFalse(BusApiParsers.isSuccess(new JSONObject()));
    }
}
