package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;

/** 校车提醒判定测试：边界、去重键与文案。 */
public class BusReminderPolicyTest {
    private static final long NOW = 1_760_000_000_000L;

    private static BusModels.Reservation reservationAt(String date, String time, String status) {
        BusModels.Reservation reservation = new BusModels.Reservation();
        reservation.orderNo = "YY1";
        reservation.routeName = "友谊到长安";
        reservation.date = date;
        reservation.departTime = time;
        reservation.status = status;
        return reservation;
    }

    @Test public void remindsOnlyInsideTheDepartureWindow() {
        LocalDateTime now = LocalDateTime.of(2026, 9, 24, 9, 0);
        long nowMillis = now.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli();

        assertTrue(BusReminderPolicy.shouldRemindDeparture(
                LocalDateTime.of(2026, 9, 24, 9, 30), nowMillis));
        assertTrue(BusReminderPolicy.shouldRemindDeparture(
                LocalDateTime.of(2026, 9, 24, 9, 0), nowMillis));
        assertFalse(BusReminderPolicy.shouldRemindDeparture(
                LocalDateTime.of(2026, 9, 24, 9, 31), nowMillis));
        assertFalse(BusReminderPolicy.shouldRemindDeparture(
                LocalDateTime.of(2026, 9, 24, 8, 59), nowMillis));
        assertFalse(BusReminderPolicy.shouldRemindDeparture(null, nowMillis));
    }

    @Test public void statusReminderSkipsFirstSightAndPendingStates() {
        assertFalse(BusReminderPolicy.shouldRemindStatus("", "已通过"));
        assertFalse(BusReminderPolicy.shouldRemindStatus("待核验", "待核验"));
        assertFalse(BusReminderPolicy.shouldRemindStatus("待核验", "待审核"));
        assertTrue(BusReminderPolicy.shouldRemindStatus("待核验", "已通过"));
        assertTrue(BusReminderPolicy.shouldRemindStatus("已通过", "已取消"));
        assertFalse(BusReminderPolicy.shouldRemindStatus("待核验", ""));
    }

    @Test public void keysAreStableAndDistinct() {
        BusModels.Reservation reservation = reservationAt("2026-09-24", "10:00", "待核验");
        assertEquals("departure:YY1|2026-09-24|10:00",
                BusReminderPolicy.departureKey(reservation));
        assertEquals("status:YY1|待核验", BusReminderPolicy.statusKey(reservation));
        BusModels.Reservation changed = reservationAt("2026-09-24", "10:00", "已通过");
        assertFalse(BusReminderPolicy.departureKey(reservation)
                .equals(BusReminderPolicy.statusKey(changed)));
    }

    @Test public void departureTextUsesMinutesAndDisplayDate() {
        LocalDateTime departure = LocalDateTime.now().plusMinutes(20);
        BusModels.Reservation reservation = reservationAt(
                departure.toLocalDate().toString(),
                departure.toLocalTime().withSecond(0).withNano(0).toString(),
                "待核验");
        long now = System.currentTimeMillis();
        String text = BusReminderPolicy.departureText(reservation, now);
        assertTrue(text, text.contains("分钟后发车") || text.contains("即将发车"));
    }

    @Test public void scarceSeatTextOnlyForOpenAndFewSeats() {
        BusModels.Trip trip = new BusModels.Trip();
        trip.date = LocalDate.now().plusDays(1).toString();
        trip.departTime = "10:00";
        trip.capacity = 40;
        trip.remaining = 3;
        trip.open = true;
        assertTrue(BusReminderPolicy.scarceSeatText(trip).contains("仅剩 3"));

        trip.remaining = 30;
        assertEquals("", BusReminderPolicy.scarceSeatText(trip));

        trip.remaining = 0;
        trip.open = false;
        assertEquals("", BusReminderPolicy.scarceSeatText(trip));
    }

    @Test public void nextReservationPrefersTheEarliestFutureOne() {
        BusModels.Snapshot snapshot = new BusModels.Snapshot();
        snapshot.reservations.add(reservationAt(
                LocalDate.now().plusDays(2).toString(), "10:00", "待核验"));
        snapshot.reservations.add(reservationAt(
                LocalDate.now().plusDays(1).toString(), "08:00", "待核验"));
        BusModels.Reservation next = snapshot.nextReservation();
        assertEquals(LocalDate.now().plusDays(1).toString(), next.date);
    }

    @Test public void pastReservationsStillRenderWhenNothingIsUpcoming() {
        BusModels.Snapshot snapshot = new BusModels.Snapshot();
        snapshot.reservations.add(reservationAt("2020-01-01", "10:00", "已通过"));
        assertTrue(snapshot.nextReservation() != null);
        assertTrue(snapshot.nextOpenTrip() == null);
    }

    @Test public void parseHelpersAcceptBothDateFormats() {
        assertEquals(LocalDate.of(2026, 9, 24), BusModels.parseDate("2026/9/24"));
        assertEquals(LocalDate.of(2026, 9, 24), BusModels.parseDate("2026-09-24"));
        assertEquals(LocalDate.of(2026, 9, 24), BusModels.parseDate("2026/9/24 10:00"));
        assertTrue(BusModels.parseDate("") == null);
        assertEquals(LocalTime.of(10, 0), BusModels.parseTime("10:00"));
        assertEquals(LocalTime.of(9, 5), BusModels.parseTime("9:05"));
        assertTrue(BusModels.parseTime("--") == null);
    }
}
