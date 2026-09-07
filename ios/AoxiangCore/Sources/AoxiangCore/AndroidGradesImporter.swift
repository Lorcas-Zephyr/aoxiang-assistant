import Foundation

/// Grades are Android-local data, not part of the shareable schedule backup.
/// This importer is intentionally separate so a caller cannot accidentally
/// widen `AndroidBackupExporter` to include credentials or session state.
public struct AndroidGradesImporter {
    public init() {}

    public func importData(_ data: Data) throws -> [OfflineGrade] {
        guard !data.isEmpty else { throw OfflineDataError.emptyBackup }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw OfflineDataError.malformedBackup(error.localizedDescription)
        }
        if let items = raw as? [[String: Any]] {
            return try decodeItems(items)
        }
        guard let envelope = raw as? [String: Any] else {
            throw OfflineDataError.malformedBackup("grades root must be an array or object")
        }
        for key in envelope.keys where !["schemaVersion", "items"].contains(key) {
            if Self.isSensitiveKey(key) { throw OfflineDataError.sensitiveField(key) }
            throw OfflineDataError.unknownField(key)
        }
        guard let schema = envelope["schemaVersion"] as? NSNumber,
              String(cString: schema.objCType) != "c",
              schema.intValue == 1,
              schema.doubleValue == 1 else {
            throw OfflineDataError.unsupportedSchemaVersion(
                (envelope["schemaVersion"] as? NSNumber)?.intValue ?? -1
            )
        }
        guard let items = envelope["items"] as? [[String: Any]] else {
            throw OfflineDataError.missingField("items")
        }
        return try decodeItems(items)
    }

    private func decodeItems(_ items: [[String: Any]]) throws -> [OfflineGrade] {
        try items.enumerated().map { index, item in
            let allowed: Set<String> = ["course", "credits", "point", "score", "category", "detail"]
            for key in item.keys where !allowed.contains(key) {
                if Self.isSensitiveKey(key) { throw OfflineDataError.sensitiveField(key) }
                throw OfflineDataError.unknownField("grades[\(index)].\(key)")
            }
            let course = item["course"] as? String ?? ""
            guard !course.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OfflineDataError.invalidField("grades[\(index)].course")
            }
            guard let credits = number(item["credits"]) else {
                throw OfflineDataError.invalidField("grades[\(index)].credits")
            }
            let point = try optionalNumber(item, key: "point", index: index)
            let score = try optionalNumber(item, key: "score", index: index)
            if credits < 0 || !credits.isFinite
                || point.map({ !$0.isFinite || $0 < 0 || $0 > 5 }) == true
                || score.map({ !$0.isFinite || $0 < 0 || $0 > 100 }) == true {
                throw OfflineDataError.invalidField("grades[\(index)]")
            }
            if let category = item["category"], !(category is String) {
                throw OfflineDataError.invalidField("grades[\(index)].category")
            }
            if let detail = item["detail"], !(detail is String) {
                throw OfflineDataError.invalidField("grades[\(index)].detail")
            }
            return OfflineGrade(
                id: "grade-\(index)",
                course: course,
                credits: credits,
                point: point,
                score: score,
                category: item["category"] as? String ?? "课程",
                detail: item["detail"] as? String ?? ""
            )
        }
    }

    private func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, String(cString: value.objCType) != "c" else { return nil }
        return value.doubleValue
    }

    private func optionalNumber(
        _ item: [String: Any],
        key: String,
        index: Int
    ) throws -> Double? {
        guard let value = item[key] else { return nil }
        if value is NSNull { return nil }
        guard let number = number(value) else {
            throw OfflineDataError.invalidField("grades[\(index)].\(key)")
        }
        return number
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        return [
            "password", "passwd", "pwd", "credential", "token", "cookie", "session",
            "authorization", "auth", "secret", "account", "username", "studentid",
            "userid", "identity", "sms", "captcha", "verification", "login",
        ].contains { normalized.contains($0) }
    }
}
