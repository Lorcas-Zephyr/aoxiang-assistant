package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/** Builds a bus snapshot without replacing valid cached sections after a partial request failure. */
final class BusSyncData {
    private BusSyncData() {}

    static final class Result {
        final BusModels.Snapshot snapshot;
        final boolean routesComplete;
        final boolean reservationsComplete;
        final boolean tripsComplete;

        Result(BusModels.Snapshot snapshot, boolean routesComplete,
               boolean reservationsComplete, boolean tripsComplete) {
            this.snapshot = snapshot;
            this.routesComplete = routesComplete;
            this.reservationsComplete = reservationsComplete;
            this.tripsComplete = tripsComplete;
        }

        boolean hasUpdate() {
            return routesComplete || reservationsComplete || tripsComplete;
        }
    }

    static Result merge(JSONObject payload, BusModels.Snapshot previous, long updatedAt,
                        LocalDate today) {
        BusModels.Snapshot cached = previous == null ? new BusModels.Snapshot() : previous;
        JSONObject routesResponse = payload == null ? null : payload.optJSONObject("routes");
        JSONObject reservationsResponse = payload == null ? null : payload.optJSONObject("reservations");
        boolean routesComplete = payload != null && payload.optBoolean(
                "routesComplete", BusApiParsers.isSuccess(routesResponse));
        boolean reservationsComplete = payload != null && payload.optBoolean(
                "reservationsComplete", BusApiParsers.isSuccess(reservationsResponse));
        boolean tripsComplete = payload != null && payload.optBoolean(
                "tripsComplete", payload.has("tripGroups"));

        BusModels.Snapshot next = new BusModels.Snapshot();
        next.updatedAt = updatedAt;
        next.reserveDays = routesComplete
                ? BusApiParsers.reserveDays(routesResponse) : cached.reserveDays;
        next.routes = routesComplete
                ? BusApiParsers.routes(routesResponse) : new ArrayList<>(cached.routes);
        next.reservations = reservationsComplete
                ? BusApiParsers.reservations(reservationsResponse)
                : new ArrayList<>(cached.reservations);
        next.trips = tripsComplete
                ? parseTrips(payload.optJSONArray("tripGroups"))
                : new ArrayList<>(cached.trips);
        BusStorage.pruneTrips(next, today == null ? LocalDate.now() : today);
        return new Result(next, routesComplete, reservationsComplete, tripsComplete);
    }

    private static List<BusModels.Trip> parseTrips(JSONArray groups) {
        List<BusModels.Trip> trips = new ArrayList<>();
        if (groups == null) return trips;
        for (int i = 0; i < groups.length(); i++) {
            JSONObject group = groups.optJSONObject(i);
            if (group == null) continue;
            BusModels.Route route = new BusModels.Route();
            route.objId = group.optString("routeId");
            route.name = group.optString("routeName");
            JSONObject wrapped = new JSONObject();
            try {
                wrapped.put("isSuccess", true);
                wrapped.put("data", group.optJSONArray("items"));
            } catch (Exception ignored) {
                continue;
            }
            trips.addAll(BusApiParsers.trips(wrapped, group.optString("date"), route));
        }
        return trips;
    }
}
