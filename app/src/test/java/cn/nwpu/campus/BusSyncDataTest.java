package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.time.LocalDate;

/** Partial bus responses must never erase unrelated cached sections. */
public class BusSyncDataTest {
    private static BusModels.Snapshot cachedSnapshot() {
        BusModels.Snapshot cached = new BusModels.Snapshot();
        cached.reserveDays = 2;

        BusModels.Route route = new BusModels.Route();
        route.objId = "old-route";
        route.name = "友谊到长安";
        cached.routes.add(route);

        BusModels.Reservation reservation = new BusModels.Reservation();
        reservation.orderNo = "old-reservation";
        reservation.routeName = "友谊到长安";
        reservation.date = LocalDate.now().plusDays(1).toString();
        reservation.departTime = "10:00";
        cached.reservations.add(reservation);

        BusModels.Trip trip = new BusModels.Trip();
        trip.objId = "old-trip";
        trip.date = LocalDate.now().plusDays(1).toString();
        trip.departTime = "10:00";
        cached.trips.add(trip);
        return cached;
    }

    @Test public void failedReservationsPreserveCachedReservations() throws Exception {
        JSONObject payload = new JSONObject()
                .put("routesComplete", false)
                .put("reservationsComplete", false)
                .put("tripsComplete", false);

        BusSyncData.Result result = BusSyncData.merge(
                payload, cachedSnapshot(), 123L, LocalDate.now());

        assertFalse(result.hasUpdate());
        assertEquals("old-reservation", result.snapshot.reservations.get(0).orderNo);
    }

    @Test public void completeEmptyReservationsClearCachedReservations() throws Exception {
        JSONObject emptyReservations = new JSONObject()
                .put("isSuccess", true)
                .put("data", new JSONObject().put("list", new JSONArray()));
        JSONObject payload = new JSONObject()
                .put("routesComplete", false)
                .put("reservationsComplete", true)
                .put("tripsComplete", false)
                .put("reservations", emptyReservations);

        BusSyncData.Result result = BusSyncData.merge(
                payload, cachedSnapshot(), 123L, LocalDate.now());

        assertTrue(result.hasUpdate());
        assertTrue(result.snapshot.reservations.isEmpty());
        assertEquals("old-trip", result.snapshot.trips.get(0).objId);
    }

    @Test public void failedTripsPreserveCachedTrips() throws Exception {
        JSONObject payload = new JSONObject()
                .put("routesComplete", false)
                .put("reservationsComplete", false)
                .put("tripsComplete", false)
                .put("tripGroups", new JSONArray());

        BusSyncData.Result result = BusSyncData.merge(
                payload, cachedSnapshot(), 123L, LocalDate.now());

        assertEquals("old-trip", result.snapshot.trips.get(0).objId);
    }

    @Test public void routeOnlyUpdatePreservesReservationsAndTrips() throws Exception {
        JSONObject newRoute = new JSONObject()
                .put("Objid", "new-route")
                .put("Name", "长安到友谊");
        JSONObject routes = new JSONObject()
                .put("isSuccess", true)
                .put("data", new JSONObject()
                        .put("filteredBusRoutes", new JSONArray().put(newRoute))
                        .put("reservationDays", new JSONObject().put("TQYYXZTS", 3)));
        JSONObject payload = new JSONObject()
                .put("routesComplete", true)
                .put("reservationsComplete", false)
                .put("tripsComplete", false)
                .put("routes", routes);

        BusSyncData.Result result = BusSyncData.merge(
                payload, cachedSnapshot(), 123L, LocalDate.now());

        assertEquals("new-route", result.snapshot.routes.get(0).objId);
        assertEquals(3, result.snapshot.reserveDays);
        assertEquals("old-reservation", result.snapshot.reservations.get(0).orderNo);
        assertEquals("old-trip", result.snapshot.trips.get(0).objId);
    }
}
