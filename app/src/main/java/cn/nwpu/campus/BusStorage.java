package cn.nwpu.campus;

import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/** 校车快照、已提醒记录与上次预约状态的持久化。 */
public final class BusStorage {
    private BusStorage() {}

    public static final String KEY_SNAPSHOT = "bus_snapshot";
    public static final String KEY_REMINDED = "bus_reminded";
    public static final String KEY_STATUSES = "bus_reservation_status";
    public static final String KEY_NO = "bus_no";
    /** 从 hq-bus 带到页面上的身份参数；首次采集后缓存下来。 */
    public static final String KEY_LAST_SYNC = "bus_last_sync";

    public static BusModels.Snapshot load(SharedPreferences store) {
        BusModels.Snapshot snapshot = new BusModels.Snapshot();
        try {
            String raw = store.getString(KEY_SNAPSHOT, "");
            if (raw == null || raw.isEmpty()) return snapshot;
            JSONObject json = new JSONObject(raw);
            snapshot.updatedAt = json.optLong("updatedAt", 0L);
            snapshot.reserveDays = json.optInt("reserveDays", 0);
            JSONArray routes = json.optJSONArray("routes");
            if (routes != null) {
                for (int i = 0; i < routes.length(); i++) {
                    JSONObject item = routes.optJSONObject(i);
                    if (item == null) continue;
                    BusModels.Route route = new BusModels.Route();
                    route.objId = item.optString("objId");
                    route.type = item.optString("type");
                    route.name = item.optString("name");
                    route.startStation = item.optString("startStation");
                    route.endStation = item.optString("endStation");
                    route.studentCharge = item.optString("studentCharge");
                    route.staffCharge = item.optString("staffCharge");
                    snapshot.routes.add(route);
                }
            }
            JSONArray trips = json.optJSONArray("trips");
            if (trips != null) {
                for (int i = 0; i < trips.length(); i++) {
                    JSONObject item = trips.optJSONObject(i);
                    if (item == null) continue;
                    BusModels.Trip trip = new BusModels.Trip();
                    trip.date = item.optString("date");
                    trip.routeId = item.optString("routeId");
                    trip.routeName = item.optString("routeName");
                    trip.objId = item.optString("objId");
                    trip.departTime = item.optString("departTime");
                    trip.capacity = item.optInt("capacity");
                    trip.booked = item.optInt("booked");
                    trip.remaining = item.optInt("remaining", -1);
                    trip.open = item.optBoolean("open");
                    trip.deadline = item.optString("deadline");
                    trip.hint = item.optString("hint");
                    trip.note = item.optString("note");
                    snapshot.trips.add(trip);
                }
            }
            JSONArray reservations = json.optJSONArray("reservations");
            if (reservations != null) {
                for (int i = 0; i < reservations.length(); i++) {
                    JSONObject item = reservations.optJSONObject(i);
                    if (item == null) continue;
                    BusModels.Reservation reservation = new BusModels.Reservation();
                    reservation.orderNo = item.optString("orderNo");
                    reservation.status = item.optString("status");
                    reservation.reviewer = item.optString("reviewer");
                    reservation.routeName = item.optString("routeName");
                    reservation.date = item.optString("date");
                    reservation.departTime = item.optString("departTime");
                    reservation.driverPhone = item.optString("driverPhone");
                    reservation.fee = item.optString("fee");
                    reservation.noticeUrl = item.optString("noticeUrl");
                    reservation.summary = item.optString("summary");
                    snapshot.reservations.add(reservation);
                }
            }
        } catch (Exception ignored) {
            return new BusModels.Snapshot();
        }
        return snapshot;
    }

    public static void save(SharedPreferences store, BusModels.Snapshot snapshot) {
        if (snapshot == null) return;
        try {
            JSONObject json = new JSONObject();
            json.put("updatedAt", snapshot.updatedAt);
            json.put("reserveDays", snapshot.reserveDays);
            JSONArray routes = new JSONArray();
            for (BusModels.Route route : snapshot.routes) {
                JSONObject item = new JSONObject();
                item.put("objId", route.objId);
                item.put("type", route.type);
                item.put("name", route.name);
                item.put("startStation", route.startStation);
                item.put("endStation", route.endStation);
                item.put("studentCharge", route.studentCharge);
                item.put("staffCharge", route.staffCharge);
                routes.put(item);
            }
            json.put("routes", routes);
            JSONArray trips = new JSONArray();
            for (BusModels.Trip trip : snapshot.trips) {
                JSONObject item = new JSONObject();
                item.put("date", trip.date);
                item.put("routeId", trip.routeId);
                item.put("routeName", trip.routeName);
                item.put("objId", trip.objId);
                item.put("departTime", trip.departTime);
                item.put("capacity", trip.capacity);
                item.put("booked", trip.booked);
                item.put("remaining", trip.remaining);
                item.put("open", trip.open);
                item.put("deadline", trip.deadline);
                item.put("hint", trip.hint);
                item.put("note", trip.note);
                trips.put(item);
            }
            json.put("trips", trips);
            JSONArray reservations = new JSONArray();
            for (BusModels.Reservation reservation : snapshot.reservations) {
                JSONObject item = new JSONObject();
                item.put("orderNo", reservation.orderNo);
                item.put("status", reservation.status);
                item.put("reviewer", reservation.reviewer);
                item.put("routeName", reservation.routeName);
                item.put("date", reservation.date);
                item.put("departTime", reservation.departTime);
                item.put("driverPhone", reservation.driverPhone);
                item.put("fee", reservation.fee);
                item.put("noticeUrl", reservation.noticeUrl);
                item.put("summary", reservation.summary);
                reservations.put(item);
            }
            json.put("reservations", reservations);
            store.edit().putString(KEY_SNAPSHOT, json.toString()).apply();
        } catch (Exception ignored) {}
    }

    public static void clear(SharedPreferences store) {
        store.edit()
                .remove(KEY_SNAPSHOT)
                .remove(KEY_STATUSES)
                .remove(KEY_REMINDED)
                .remove(KEY_LAST_SYNC)
                .apply();
    }

    /** 该提醒键是否已经发过通知。 */
    public static boolean isReminded(SharedPreferences store, String key) {
        return reminded(store).has(key);
    }

    /** 记录已提醒；为防无限增长，超过 200 条时重置。 */
    public static void markReminded(SharedPreferences store, String key) {
        try {
            JSONObject map = reminded(store);
            if (map.length() > 200) map = new JSONObject();
            map.put(key, System.currentTimeMillis());
            store.edit().putString(KEY_REMINDED, map.toString()).apply();
        } catch (Exception ignored) {}
    }

    private static JSONObject reminded(SharedPreferences store) {
        try {
            String raw = store.getString(KEY_REMINDED, "");
            if (raw == null || raw.isEmpty()) return new JSONObject();
            return new JSONObject(raw);
        } catch (Exception ignored) {
            return new JSONObject();
        }
    }

    /** 上次见到的预约状态，键为 Reservation.key()。 */
    public static String previousStatus(SharedPreferences store, BusModels.Reservation reservation) {
        try {
            return statuses(store).optString(reservation.key(), "");
        } catch (Exception ignored) {
            return "";
        }
    }

    public static void saveStatuses(SharedPreferences store, List<BusModels.Reservation> reservations) {
        try {
            JSONObject map = new JSONObject();
            for (BusModels.Reservation reservation : reservations) {
                if (reservation.key().trim().isEmpty()) continue;
                map.put(reservation.key(), reservation.status);
            }
            store.edit().putString(KEY_STATUSES, map.toString()).apply();
        } catch (Exception ignored) {}
    }

    private static JSONObject statuses(SharedPreferences store) {
        try {
            String raw = store.getString(KEY_STATUSES, "");
            if (raw == null || raw.isEmpty()) return new JSONObject();
            return new JSONObject(raw);
        } catch (Exception ignored) {
            return new JSONObject();
        }
    }

    /** 只保留尚未出发的班次，避免历史数据不断堆积。 */
    public static void pruneTrips(BusModels.Snapshot snapshot, java.time.LocalDate today) {
        if (snapshot == null) return;
        List<BusModels.Trip> kept = new ArrayList<>();
        for (BusModels.Trip trip : snapshot.trips) {
            java.time.LocalDate date = BusModels.parseDate(trip.date);
            if (date == null || !date.isBefore(today)) kept.add(trip);
        }
        snapshot.trips = kept;
    }
}
