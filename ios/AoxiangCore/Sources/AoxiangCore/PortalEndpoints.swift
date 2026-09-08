import Foundation

/// The small, allow-listed endpoint surface used by foreground collection.
/// URLs are built here so a future portal change is one contract change and
/// cannot accidentally turn a server-provided value into an arbitrary request.
public enum PortalCollectionTarget: String, Codable, Equatable, CaseIterable {
    case grades
    case schedule
    case electricity
}

public enum PortalEndpointError: Error, Equatable {
    case invalidIdentifier
    case unsupportedHost
    case unsupportedPath
}

public enum PortalEndpoints {
    public static let educationHost = "jwxt.nwpu.edu.cn"
    public static let electricityHost = "yktapp.nwpu.edu.cn"
    public static let educationBaseURL = URL(string: "https://\(educationHost)")!
    public static let electricityBaseURL = URL(string: "https://\(electricityHost)")!
    public static let collectionTimeout: TimeInterval = 12

    public static func gradeSheet() -> StableHTTPCollectionRequest {
        educationRequest(path: "/student/for-std/grade/sheet")
    }

    public static func studentInfo() -> StableHTTPCollectionRequest {
        educationRequest(path: "/student/for-std/student-portrait/getStdInfo")
    }

    public static func gradeInfo(studentID: String, semesterID: String) throws -> StableHTTPCollectionRequest {
        try educationRequest(
            path: "/student/for-std/grade/sheet/info/\(try pathComponent(studentID))",
            query: [URLQueryItem(name: "semester", value: try queryComponent(semesterID))]
        )
    }

    public static func gpa(studentID: String) throws -> StableHTTPCollectionRequest {
        try educationRequest(
            path: "/student/for-std/student-portrait/getMyGpa",
            query: [URLQueryItem(name: "studentAssoc", value: try queryComponent(studentID))]
        )
    }

    public static func courseTable() -> StableHTTPCollectionRequest {
        educationRequest(path: "/student/for-std/course-table")
    }

    public static func semester(id: String) throws -> StableHTTPCollectionRequest {
        try educationRequest(path: "/student/ws/semester/get/\(try pathComponent(id))")
    }

    public static func printData(studentID: String, semesterID: String) throws -> StableHTTPCollectionRequest {
        try educationRequest(
            path: "/student/for-std/course-table/semester/\(try pathComponent(semesterID))/print-data/\(try pathComponent(studentID))"
        )
    }

    /// Electricity is intentionally only a capability marker. The portal uses
    /// page JavaScript/Vue state rather than a stable JSON endpoint, so it must
    /// remain on the visible WebView path until an actual HTTP contract exists.
    public static func electricityPage() -> URL {
        electricityBaseURL.appendingPathComponent("jfdt/charge/feeitem/toAppitem")
    }

    private static func educationRequest(path: String, query: [URLQueryItem] = []) -> StableHTTPCollectionRequest {
        // Use URLComponents so query encoding remains centralized and stable.
        var components = URLComponents(url: educationBaseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        return request(url: components.url!)
    }

    private static func request(url: URL) -> StableHTTPCollectionRequest {
        StableHTTPCollectionRequest(
            url: url,
            headers: [
                "Accept": "application/json",
                "Cache-Control": "no-store",
                "Pragma": "no-cache",
            ],
            timeoutInterval: collectionTimeout
        )
    }

    private static func pathComponent(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("..") else {
            throw PortalEndpointError.invalidIdentifier
        }
        return trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
    }

    private static func queryComponent(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("..") else {
            throw PortalEndpointError.invalidIdentifier
        }
        return trimmed
    }
}
