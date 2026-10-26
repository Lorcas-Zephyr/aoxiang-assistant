import Foundation
import XCTest
@testable import AoxiangCore

final class CommuterBusContractTests: XCTestCase {
    func testAndroidPayloadMapsRoutesTripsAndAppointments() throws {
        let payload = """
        {
          "routesComplete": true,
          "reservationsComplete": true,
          "tripsComplete": true,
          "routes": {
            "isSuccess": true,
            "data": {
              "filteredBusRoutes": [{
                "Objid": "route-1", "Type": "通勤车", "Name": "友谊到长安",
                "StartStation": "友谊校区", "EndStation": "长安校区",
                "StudentCharge": "5", "TeacherStaffCharge": "0"
              }],
              "reservationDays": { "TQYYXZTS": "2" }
            }
          },
          "reservations": {
            "isSuccess": true,
            "data": { "list": [{
              "yydh": "order-1", "yyzt": "待核验", "xlmc": "友谊到长安",
              "ccrq": "2026/10/27", "fcsj": "8:05", "fy": "5"
            }] }
          },
          "tripGroups": [{
            "date": "2026-10-27", "routeId": "route-1", "routeName": "友谊到长安",
            "items": [{
              "objId": "trip-1", "fcsj": "08:15", "yyrs": "17", "kyyrs": "20",
              "sfkyy": true, "yyjzxx": "06:10截止预约", "tsxx": "距离发车时间还有1天",
              "bcms": "校车班次"
            }]
          }]
        }
        """

        let result = try CommuterBusSyncMerger.merge(
            payload: Data(payload.utf8),
            previous: CommuterBusSnapshot(),
            updatedAt: 1_798_000_000_000,
            today: "2026-10-26"
        )

        XCTAssertTrue(result.hasUpdate)
        XCTAssertEqual(result.snapshot.reserveDays, 2)
        XCTAssertEqual(result.snapshot.routes.first?.name, "友谊到长安")
        XCTAssertEqual(result.snapshot.routes.first?.stationText, "友谊校区 → 长安校区")
        XCTAssertEqual(result.snapshot.trips.first?.remainingSeats, 3)
        XCTAssertTrue(result.snapshot.trips.first?.isReservable == true)
        XCTAssertEqual(result.snapshot.reservations.first?.date, "2026-10-27")
        XCTAssertEqual(result.snapshot.reservations.first?.departureTime, "08:05")
        XCTAssertEqual(result.snapshot.reservations.first?.status, "待核验")
    }

    func testPartialResponsesKeepCachedSectionsAndSuccessfulEmptyListClearsAppointments() throws {
        let previous = CommuterBusSnapshot(
            updatedAt: 100,
            reserveDays: 4,
            routes: [CommuterBusRoute(id: "old-route", name: "旧路线")],
            trips: [CommuterBusTrip(
                id: "old-trip", date: "2026-10-27", routeID: "old-route",
                routeName: "旧路线", departureTime: "08:00", isReservable: true
            )],
            reservations: [CommuterBusReservation(
                id: "old-order", status: "待核验", routeName: "旧路线",
                date: "2026-10-27", departureTime: "08:00"
            )]
        )
        let payload = """
        {
          "routesComplete": true,
          "reservationsComplete": false,
          "tripsComplete": false,
          "routes": {
            "isSuccess": true,
            "data": {
              "filteredBusRoutes": [{ "Objid": "new-route", "Name": "新路线" }],
              "reservationDays": { "TQYYXZTS": "3" }
            }
          },
          "reservations": { "isSuccess": false, "data": { "list": [] } },
          "tripGroups": []
        }
        """

        let partial = try CommuterBusSyncMerger.merge(
            payload: Data(payload.utf8), previous: previous,
            updatedAt: 200, today: "2026-10-26"
        )

        XCTAssertTrue(partial.hasUpdate)
        XCTAssertEqual(partial.snapshot.routes.map(\.id), ["new-route"])
        XCTAssertEqual(partial.snapshot.reserveDays, 3)
        XCTAssertEqual(partial.snapshot.trips.map(\.id), ["old-trip"])
        XCTAssertEqual(partial.snapshot.reservations.map(\.id), ["old-order"])
        XCTAssertFalse(partial.reservationsComplete)
        XCTAssertFalse(partial.tripsComplete)

        let emptyReservationsPayload = """
        {
          "reservationsComplete": true,
          "reservations": { "isSuccess": true, "data": { "list": [] } }
        }
        """
        let cleared = try CommuterBusSyncMerger.merge(
            payload: Data(emptyReservationsPayload.utf8), previous: previous,
            updatedAt: 300, today: "2026-10-26"
        )
        XCTAssertTrue(cleared.reservationsComplete)
        XCTAssertTrue(cleared.snapshot.reservations.isEmpty)
        XCTAssertEqual(cleared.snapshot.trips.map(\.id), ["old-trip"])
    }

    func testSnapshotIsBackwardCompatiblePrivateStateAndSurvivesPortableImport() throws {
        let snapshot = CommuterBusSnapshot(
            updatedAt: 500,
            reserveDays: 2,
            routes: [CommuterBusRoute(id: "route-1", name: "友谊到长安")]
        )
        let state = OfflineAppState(commuterBus: snapshot)
        let localData = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(OfflineAppState.self, from: localData)
        XCTAssertEqual(decoded.commuterBus, snapshot)

        let oldState = try JSONDecoder().decode(
            OfflineAppState.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(oldState.commuterBus, CommuterBusSnapshot())

        let portable = try AndroidBackupExporter().exportData(from: state)
        let portableText = String(decoding: portable, as: UTF8.self)
        XCTAssertFalse(portableText.contains("commuterBus"))
        XCTAssertFalse(portableText.contains("友谊到长安"))

        let previous = OfflineAppState(commuterBus: snapshot)
        let controller = try OfflineDataController(store: InMemoryOfflineStateStore(value: previous))
        let replacement = try AndroidBackupExporter().exportData(from: OfflineAppState(
            courses: [OfflineCourse(id: "course-new", name: "新课程", semesterId: "term-new")],
            semesters: [OfflineSemester(id: "term-new", startDate: "2026-09-01", endDate: "2027-01-31")],
            selectedSemesterId: "term-new"
        ))
        _ = try controller.importAndroidBackup(replacement)
        XCTAssertEqual(controller.state.commuterBus, snapshot)
    }

    func testReminderPolicySuppressesInitialAndPendingStatusesAndAlertsBeforeDeparture() {
        let previous = CommuterBusReservation(
            id: "order-1", status: "待核验", routeName: "友谊到长安",
            date: "2026-10-27", departureTime: "08:00"
        )
        let approved = CommuterBusReservation(
            id: "order-1", status: "已通过", routeName: "友谊到长安",
            date: "2026-10-27", departureTime: "08:00"
        )
        let stillPending = CommuterBusReservation(
            id: "order-1", status: "待审核", routeName: "友谊到长安",
            date: "2026-10-27", departureTime: "08:00"
        )

        XCTAssertEqual(
            CommuterBusReminderPolicy.statusChanges(previous: [], current: [approved]),
            []
        )
        XCTAssertEqual(
            CommuterBusReminderPolicy.statusChanges(previous: [previous], current: [stillPending]),
            []
        )
        XCTAssertEqual(
            CommuterBusReminderPolicy.statusChanges(previous: [previous], current: [approved]),
            [approved]
        )

        let now = Date(timeIntervalSince1970: 1_798_000_000)
        XCTAssertTrue(CommuterBusReminderPolicy.shouldRemindDeparture(at: now.addingTimeInterval(30 * 60), now: now))
        XCTAssertTrue(CommuterBusReminderPolicy.shouldRemindDeparture(at: now, now: now))
        XCTAssertFalse(CommuterBusReminderPolicy.shouldRemindDeparture(at: now.addingTimeInterval(-1), now: now))
        XCTAssertFalse(CommuterBusReminderPolicy.shouldRemindDeparture(at: now.addingTimeInterval(30 * 60 + 1), now: now))
        XCTAssertTrue(CommuterBusReminderPolicy.canRemindDeparture(for: approved))
        XCTAssertFalse(CommuterBusReminderPolicy.canRemindDeparture(for: stillPending))
        XCTAssertTrue(CommuterBusReminderPolicy.canRemindDeparture(for: CommuterBusReservation(
            id: "order-1", status: "待乘车", routeName: "友谊到长安",
            date: "2026-10-27", departureTime: "08:00"
        )))
        XCTAssertEqual(
            CommuterBusReminderPolicy.departureReminderDate(for: approved),
            approved.departureDate()?.addingTimeInterval(-30 * 60)
        )
    }
}
