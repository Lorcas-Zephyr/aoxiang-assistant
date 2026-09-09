import Foundation
import AoxiangCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Transport-independent source of portal responses. The iOS app supplies a
/// URLSession adapter backed by the visible WebView cookie store; tests can
/// provide deterministic response bytes.
public protocol PortalCollectionTransport {
    func send(_ request: StableHTTPCollectionRequest) async throws -> (Data, HTTPURLResponse)
}

public struct PortalCollectionTransportAdapter: PortalCollectionTransport {
    private let port: StableHTTPCollectionPort

    public init(port: StableHTTPCollectionPort) { self.port = port }

    public func send(_ request: StableHTTPCollectionRequest) async throws -> (Data, HTTPURLResponse) {
        try await port.send(request)
    }
}

private struct ScheduleSemesterRecord {
    let candidate: PortalCollectionParsers.ScheduleSemesterCandidate
    let object: [String: Any]
}

/// Performs the stable education requests serially, then maps the raw
/// responses through the shared Foundation parser. Electricity remains a
/// visible-page capability until the portal exposes a stable HTTP contract.
public struct PortalForegroundCollector {
    private let transport: PortalCollectionTransport
    private let electricityProvider: () async throws -> Double
    private let portraitProvider: (() async throws -> String?)?
    private let visibleEducationProvider: (() async throws -> PortalVisibleEducationData)?

    public init(
        transport: PortalCollectionTransport,
        electricityProvider: @escaping () async throws -> Double,
        portraitProvider: (() async throws -> String?)? = nil,
        visibleEducationProvider: (() async throws -> PortalVisibleEducationData)? = nil
    ) {
        self.transport = transport
        self.electricityProvider = electricityProvider
        self.portraitProvider = portraitProvider
        self.visibleEducationProvider = visibleEducationProvider
    }

    public func collect(
        state: AuthenticationState,
        portraitHTML: String? = nil,
        isCancelled: @escaping () -> Bool = { false },
        today: String? = nil
    ) async throws -> PortalCollectedData {
        if state != .readyToCollect {
            switch state {
            case .needsLogin, .needsUserAttention: throw PortalCollectionFailure.authenticationRequired
            case .needsSMS: throw PortalCollectionFailure.smsRequired
            case .retryableFailure(let failure): throw PortalCollectionFailure.retryable(failure.reason)
            case .authenticated: throw PortalCollectionFailure.invalidResponse("collection not prepared")
            case .readyToCollect: break
            }
        }
        guard !isCancelled() else { throw PortalCollectionFailure.cancelled }

        // Android performs education requests in the authenticated WebView.
        // Prefer the same-origin path whenever the app supplies it; this keeps
        // SSO cookies and redirects inside WebKit instead of reconstructing a
        // fragile cross-domain URLSession session.
        if let visibleEducationProvider {
            do {
                let education = try await visibleEducationProvider()
                guard !isCancelled() else { throw PortalCollectionFailure.cancelled }
                // A page can finish loading while its client-side grade list is
                // still empty or its DOM shape is not recognized. Do not treat
                // that as a successful empty collection: fall through to the
                // allow-listed response path so existing grades cannot be
                // replaced by an empty list.
                guard !education.grades.isEmpty else {
                    throw PortalCollectionFailure.invalidResponse("grade rows unavailable")
                }
                var portraitGPA = portraitHTML.flatMap(PortalCollectionParsers.parsePortraitGPA)
                if education.gpa == nil, portraitGPA == nil, let portraitProvider {
                    do {
                        portraitGPA = try await portraitProvider().flatMap(PortalCollectionParsers.parsePortraitGPA)
                    } catch let failure as PortalCollectionFailure {
                        if case .invalidResponse = failure {
                            portraitGPA = nil
                        } else {
                            throw failure
                        }
                    }
                }
                var electricity: Double?
                var warnings: [PortalCollectionWarning] = []
                do {
                    let value = try await electricityProvider()
                    guard value.isFinite, value >= 0, value < 100000 else {
                        throw PortalCollectionFailure.invalidResponse("electricity balance invalid")
                    }
                    electricity = value
                } catch let failure as PortalCollectionFailure {
                    switch failure {
                    case .cancelled:
                        throw failure
                    case .authenticationRequired, .smsRequired, .retryable, .invalidResponse:
                        warnings.append(.electricityUnavailable)
                    }
                } catch {
                    warnings.append(.electricityUnavailable)
                }
                return PortalCollectedData(
                    grades: PortalCollectionParsers.keepHighest(education.grades),
                    gpa: PortalCollectionParsers.selectGPA(api: education.gpa, portrait: portraitGPA),
                    schedule: education.schedule,
                    electricityBalance: electricity,
                    warnings: warnings,
                    scheduleAvailable: education.scheduleAvailable
                )
            } catch let failure as PortalCollectionFailure {
                switch failure {
                case .retryable, .invalidResponse:
                    // A visible page may be loading or expose a changed portal
                    // shape. Keep the authenticated cookie store and fall back
                    // to the allow-listed HTTP path before failing the run.
                    break
                case .authenticationRequired, .smsRequired, .cancelled:
                    throw failure
                }
            }
        }

        let gradeSheet = try await send(PortalEndpoints.gradeSheet())
        let sheetData = gradeSheet.0
        let sheetText = String(decoding: sheetData, as: UTF8.self)
        let sheetObject = (try? jsonObject(sheetData)) ?? [:]
        var resolvedStudentID = firstString(
            sheetObject["studentId"], sheetObject["studentID"], sheetObject["studentAssoc"]
        )
        if resolvedStudentID.isEmpty {
            resolvedStudentID = PortalCollectionParsers.discoverStudentID(from: sheetText) ?? ""
        }
        var studentInfoObject: [String: Any] = [:]
        if resolvedStudentID.isEmpty {
            do {
                let studentInfo = try await send(PortalEndpoints.studentInfo())
                studentInfoObject = (try? jsonObject(studentInfo.0)) ?? [:]
                resolvedStudentID = firstString(
                    studentInfoObject["studentId"],
                    studentInfoObject["studentID"],
                    studentInfoObject["studentAssoc"],
                    studentInfoObject["id"],
                    (studentInfoObject["student"] as? [String: Any])?["id"],
                    (studentInfoObject["student"] as? [String: Any])?["studentId"],
                    (studentInfoObject["data"] as? [String: Any])?["id"]
                )
            } catch let failure as PortalCollectionFailure {
                if case .invalidResponse = failure {
                    // The page HTML remains a supported discovery fallback.
                } else {
                    throw failure
                }
            }
        }
        guard !resolvedStudentID.isEmpty else {
            if isAuthenticationHTML(sheetText) {
                throw PortalCollectionFailure.authenticationRequired
            }
            throw PortalCollectionFailure.invalidResponse("student identifier unavailable")
        }

        let sheetSemesterIDs = extractSemesterIDs(from: sheetObject)
        let infoSemesterIDs = extractSemesterIDs(from: studentInfoObject)
        let semesterIDs = !sheetSemesterIDs.isEmpty
            ? sheetSemesterIDs
            : (!infoSemesterIDs.isEmpty
                ? infoSemesterIDs
                : PortalCollectionParsers.discoverSemesterIDs(from: sheetText))
        var gradeResponses: [[String: Any]] = []
        for offset in stride(from: 0, to: semesterIDs.count, by: 4) {
            for semesterID in semesterIDs[offset..<min(offset + 4, semesterIDs.count)] {
                guard !isCancelled() else { throw PortalCollectionFailure.cancelled }
                do {
                    let response = try await send(try PortalEndpoints.gradeInfo(studentID: resolvedStudentID, semesterID: semesterID))
                    if let object = try? jsonObject(response.0) { gradeResponses.append(object) }
                } catch let failure as PortalCollectionFailure {
                    if case .invalidResponse = failure {
                        continue
                    }
                    throw failure
                }
            }
        }
        guard !gradeResponses.isEmpty else {
            if isAuthenticationHTML(sheetText) {
                throw PortalCollectionFailure.authenticationRequired
            }
            throw PortalCollectionFailure.invalidResponse("grade response unavailable")
        }
        var gradeEnvelope: [String: Any] = ["gradeResponses": gradeResponses]
        do {
            let gpaResponse = try await send(try PortalEndpoints.gpa(studentID: resolvedStudentID))
            if let object = try? jsonObject(gpaResponse.0) {
                gradeEnvelope["gpaResponse"] = object
            }
        } catch let failure as PortalCollectionFailure {
            if case .invalidResponse = failure {
                // A missing GPA must not discard otherwise valid grade rows.
            } else {
                throw failure
            }
        }
        let parsedGrades = try PortalCollectionParsers.parseGradeAPI(try jsonData(gradeEnvelope))
        guard !parsedGrades.grades.isEmpty else {
            throw PortalCollectionFailure.invalidResponse("grade rows unavailable")
        }
        var portraitGPA = portraitHTML.flatMap(PortalCollectionParsers.parsePortraitGPA)
        if parsedGrades.apiGPA == nil, portraitGPA == nil, let portraitProvider {
            do {
                let html = try await portraitProvider()
                portraitGPA = html.flatMap(PortalCollectionParsers.parsePortraitGPA)
            } catch let failure as PortalCollectionFailure {
                // A malformed/empty portrait is a missing optional GPA, but
                // authentication and transport failures must stop the commit.
                if case .invalidResponse = failure {
                    portraitGPA = nil
                } else {
                    throw failure
                }
            }
        }
        let selectedGPA = PortalCollectionParsers.selectGPA(
            api: parsedGrades.apiGPA,
            portrait: portraitGPA
        )

        guard !isCancelled() else { throw PortalCollectionFailure.cancelled }
        let tableResponse: (Data, HTTPURLResponse)
        do {
            tableResponse = try await send(PortalEndpoints.courseTable())
        } catch let failure as PortalCollectionFailure {
            // Grades are already valid and independently useful when the
            // course-table route is temporarily unavailable. Commit them with
            // an empty schedule instead of masking the success with a generic
            // grade error; the next foreground run can refresh the schedule.
            switch failure {
            case .authenticationRequired, .smsRequired, .cancelled:
                throw failure
            case .retryable, .invalidResponse:
                return PortalCollectedData(
                    grades: PortalCollectionParsers.keepHighest(parsedGrades.grades),
                    gpa: selectedGPA,
                    schedule: emptySchedulePayload(),
                    electricityBalance: try await optionalElectricityBalance(),
                    warnings: [.scheduleUnavailable],
                    scheduleAvailable: false
                )
            }
        }
        let tableData = tableResponse.0
        let tableText = String(decoding: tableData, as: UTF8.self)
        let tableObject = (try? jsonObject(tableData)) ?? [:]
        let semesterRecords = scheduleSemesterRecords(object: tableObject, html: tableText)
        guard !semesterRecords.isEmpty else {
            return try await partialResult(
                grades: parsedGrades.grades,
                gpa: selectedGPA,
                warnings: [.scheduleUnavailable]
            )
        }
        // Semester boundaries are a campus-local wire contract, not the
        // device's or UTC calendar. Keep this aligned with offline schedule
        // evaluation so a midnight boundary cannot select the wrong term.
        let collectionDate = today ?? currentBusinessDate()
        guard let selection = PortalCollectionParsers.selectScheduleSemester(
            from: semesterRecords.map(\.candidate), today: collectionDate
        ) else {
            return try await partialResult(
                grades: parsedGrades.grades,
                gpa: selectedGPA,
                warnings: [.scheduleUnavailable]
            )
        }

        var selectedRecordIndex = selection.initialIndex
        var remainingRecords = semesterRecords
        let orderedRecords = selection.ordered.compactMap { candidate -> ScheduleSemesterRecord? in
            guard let index = remainingRecords.firstIndex(where: { $0.candidate == candidate }) else {
                return nil
            }
            return remainingRecords.remove(at: index)
        }
        guard orderedRecords.count == selection.ordered.count,
              selectedRecordIndex < orderedRecords.count else {
            return try await partialResult(
                grades: parsedGrades.grades,
                gpa: selectedGPA,
                warnings: [.scheduleUnavailable]
            )
        }

        var semesterObject: [String: Any]
        var printData: Data
        while true {
            let record = orderedRecords[selectedRecordIndex]
            let scheduleID = record.candidate.id
            semesterObject = record.object
            do {
                let response = try await send(try PortalEndpoints.semester(id: scheduleID))
                if let object = try? jsonObject(response.0) {
                    semesterObject = object
                }
            } catch let failure as PortalCollectionFailure {
                switch failure {
                case .invalidResponse:
                    // Keep the course-table semester object when the enrichment endpoint is absent.
                    break
                case .authenticationRequired, .smsRequired, .cancelled:
                    throw failure
                case .retryable:
                    return try await partialResult(
                        grades: parsedGrades.grades,
                        gpa: selectedGPA,
                        warnings: [.scheduleUnavailable]
                    )
                }
            }
            do {
                printData = try await send(
                    try PortalEndpoints.printData(studentID: resolvedStudentID, semesterID: scheduleID)
                ).0
            } catch let failure as PortalCollectionFailure {
                switch failure {
                case .authenticationRequired, .smsRequired, .cancelled:
                    throw failure
                case .retryable, .invalidResponse:
                    return try await partialResult(
                        grades: parsedGrades.grades,
                        gpa: selectedGPA,
                        warnings: [.scheduleUnavailable]
                    )
                }
            }
            let effectiveEnd = PortalCollectionParsers.effectiveScheduleEndDate(
                startDate: firstString(semesterObject["startDate"], record.candidate.startDate),
                printData: printData
            )
            if effectiveEnd == nil || collectionDate <= effectiveEnd! || selectedRecordIndex >= orderedRecords.count - 1 {
                break
            }
            selectedRecordIndex += 1
        }
        let schedule: PortalCollectionParsers.SchedulePayload
        do {
            schedule = try PortalCollectionParsers.parseSchedulePayload(try jsonData([
                "semester": semesterObject,
                "printData": try jsonObject(printData),
            ]))
        } catch {
            return try await partialResult(
                grades: parsedGrades.grades,
                gpa: selectedGPA,
                warnings: [.scheduleUnavailable]
            )
        }

        var electricity: Double?
        var warnings: [PortalCollectionWarning] = []
        do {
            let value = try await electricityProvider()
            guard value.isFinite, value >= 0, value < 100000 else {
                throw PortalCollectionFailure.invalidResponse("electricity balance invalid")
            }
            electricity = value
        } catch let failure as PortalCollectionFailure {
            switch failure {
            case .cancelled:
                throw failure
            case .authenticationRequired, .smsRequired, .retryable, .invalidResponse:
                warnings.append(.electricityUnavailable)
            }
        } catch {
            warnings.append(.electricityUnavailable)
        }
        return PortalCollectedData(
            grades: PortalCollectionParsers.keepHighest(parsedGrades.grades),
            gpa: selectedGPA,
            schedule: schedule,
            electricityBalance: electricity,
            warnings: warnings
        )
    }

    private func emptySchedulePayload() -> PortalCollectionParsers.SchedulePayload {
        PortalCollectionParsers.SchedulePayload(
            semesters: [OfflineSemester(id: "current", name: "当前学期", startDate: "1970-01-01", endDate: "1970-01-01")],
            courses: []
        )
    }

    private func optionalElectricityBalance() async throws -> Double? {
        do {
            let value = try await electricityProvider()
            return value.isFinite && value >= 0 && value < 100000 ? value : nil
        } catch let failure as PortalCollectionFailure {
            switch failure {
            case .cancelled:
                throw failure
            case .authenticationRequired, .smsRequired, .retryable, .invalidResponse:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func partialResult(
        grades: [OfflineGrade],
        gpa: Double?,
        warnings: [PortalCollectionWarning]
    ) async throws -> PortalCollectedData {
        PortalCollectedData(
            grades: PortalCollectionParsers.keepHighest(grades),
            gpa: gpa,
            schedule: emptySchedulePayload(),
            electricityBalance: try await optionalElectricityBalance(),
            warnings: warnings,
            scheduleAvailable: false
        )
    }

    private func send(_ request: StableHTTPCollectionRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let response = try await transport.send(request)
            switch response.1.statusCode {
            case 401, 403:
                throw CollectionTransportError.authenticationRequired
            case 408:
                throw CollectionTransportError.retryable(.serverUnavailable)
            case 429:
                throw CollectionTransportError.retryable(.rateLimited)
            case 500...599:
                throw CollectionTransportError.retryable(.serverUnavailable)
            case 200..<300:
                return response
            default:
                throw CollectionTransportError.nonSuccessStatus(response.1.statusCode)
            }
        }
        catch let error as CollectionTransportError {
            if case .authenticationRequired = error { throw PortalCollectionFailure.authenticationRequired }
            if case .retryable(let reason) = error { throw PortalCollectionFailure.retryable(reason) }
            throw PortalCollectionFailure.invalidResponse(error.localizedDescription)
        }
        catch { throw PortalCollectionFailure.retryable(.networkUnavailable) }
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PortalCollectionFailure.invalidResponse("response root is not an object")
        }
        return object
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }

    private func isAuthenticationHTML(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("统一身份认证")
            || normalized.contains("统一认证")
            || normalized.contains("cas/login")
            || normalized.contains("请输入账号")
            || normalized.contains("请输入密码")
            || normalized.contains("登录信息已失效")
            || normalized.contains("会话已失效")
    }

    private func firstString(_ values: Any?...) -> String {
        for value in values {
            if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return ""
    }

    private func extractSemesterIDs(from object: [String: Any]) -> [String] {
        if let ids = object["semesterIds"] as? [String] { return ids }
        if let semesters = object["semesters"] as? [[String: Any]] {
            return semesters.map { firstString($0["id"], $0["code"]) }.filter { !$0.isEmpty }
        }
        if let map = object["semesterId2studentGrades"] as? [String: Any] {
            return Array(map.keys).sorted()
        }
        return []
    }

    private func scheduleSemesterRecords(object: [String: Any], html: String) -> [ScheduleSemesterRecord] {
        let arrays: [[String: Any]] = [
            object["semesters"] as? [[String: Any]],
            object["semesterList"] as? [[String: Any]],
            object["semesterOptions"] as? [[String: Any]],
            (object["data"] as? [String: Any])?["semesters"] as? [[String: Any]],
        ].compactMap { $0 }.first ?? []
        if !arrays.isEmpty {
            return arrays.compactMap { record in
                makeScheduleSemesterRecord(record)
            }
        }

        let singular = (object["semester"] as? [String: Any])
            ?? (object["currentSemester"] as? [String: Any])
        if let singular, let record = makeScheduleSemesterRecord(singular) {
            return [record]
        }

        return PortalCollectionParsers.discoverScheduleSemesters(from: html).map { candidate in
            ScheduleSemesterRecord(
                candidate: candidate,
                object: [
                    "id": candidate.id,
                    "name": candidate.name,
                    "startDate": candidate.startDate,
                    "endDate": candidate.endDate as Any,
                ]
            )
        }
    }

    private func makeScheduleSemesterRecord(_ object: [String: Any]) -> ScheduleSemesterRecord? {
        let id = firstString(object["id"], object["code"], object["dataSemester"])
        let startDate = firstString(object["startDate"])
        guard !id.isEmpty, !startDate.isEmpty else { return nil }
        let candidate = PortalCollectionParsers.ScheduleSemesterCandidate(
            id: id,
            name: firstString(object["nameZh"], object["name"], object["title"], id),
            startDate: startDate,
            endDate: firstString(object["endDate"]).isEmpty ? nil : firstString(object["endDate"])
        )
        return ScheduleSemesterRecord(candidate: candidate, object: object)
    }

    private func currentBusinessDate() -> String {
        let calendar = OfflineDatePolicy.businessCalendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
