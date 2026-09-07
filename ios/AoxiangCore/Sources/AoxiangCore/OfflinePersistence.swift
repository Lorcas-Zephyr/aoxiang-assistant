import Foundation

public protocol OfflineStateStore {
    func load() throws -> OfflineAppState?
    func save(_ state: OfflineAppState) throws
}

/// File-backed app-private store. It writes a complete validated envelope to a
/// temporary sibling and replaces the old file only after the write succeeds.
public final class FileOfflineStateStore: OfflineStateStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> OfflineAppState? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(OfflineAppState.self, from: data)
            return try state.validated()
        } catch let error as OfflineDataError {
            throw error
        } catch {
            throw OfflineDataError.persistenceFailed(error.localizedDescription)
        }
    }

    public func save(_ state: OfflineAppState) throws {
        let validated = try state.validated()
        let data: Data
        do {
            data = try JSONEncoder().encode(validated)
        } catch {
            throw OfflineDataError.persistenceFailed(error.localizedDescription)
        }
        let parent = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let temporaryURL = parent.appendingPathComponent(
                ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
            )
            defer { try? fileManager.removeItem(at: temporaryURL) }
            try data.write(to: temporaryURL, options: [.atomic])
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            throw OfflineDataError.persistenceFailed(error.localizedDescription)
        }
    }
}

public final class InMemoryOfflineStateStore: OfflineStateStore {
    public var value: OfflineAppState?
    public var shouldFailWrites = false

    public init(value: OfflineAppState? = nil) {
        self.value = value
    }

    public func load() throws -> OfflineAppState? {
        guard let value else { return nil }
        return try value.validated()
    }

    public func save(_ state: OfflineAppState) throws {
        guard !shouldFailWrites else { throw OfflineDataError.persistenceFailed("injected write failure") }
        value = try state.validated()
    }
}

/// Main-app editing facade. The in-memory state changes only after the store
/// accepts the complete candidate, so a failed save cannot look successful.
public final class OfflineDataController {
    public private(set) var state: OfflineAppState
    public private(set) var isRecoveryRequired: Bool
    private let store: OfflineStateStore

    public init(store: OfflineStateStore, initialState: OfflineAppState = OfflineAppState()) throws {
        self.store = store
        self.state = try store.load() ?? initialState.validated()
        self.isRecoveryRequired = false
    }

    private init(recoveryState: OfflineAppState, store: OfflineStateStore) {
        self.store = store
        self.state = recoveryState
        self.isRecoveryRequired = true
    }

    /// Used only after loading the app-private state fails. It preserves the
    /// unreadable file and blocks ordinary edits until a complete portable
    /// backup has been validated and atomically written in its place.
    public static func recoveryController(store: OfflineStateStore) -> OfflineDataController {
        OfflineDataController(recoveryState: OfflineAppState(), store: store)
    }

    @discardableResult
    public func replace(_ candidate: OfflineAppState) throws -> OfflineAppState {
        try replace(candidate, allowingRecovery: false)
    }

    private func replace(
        _ candidate: OfflineAppState,
        allowingRecovery: Bool
    ) throws -> OfflineAppState {
        guard !isRecoveryRequired || allowingRecovery else {
            throw OfflineDataError.recoveryRequired
        }
        let validated = try candidate.validated()
        try store.save(validated)
        state = validated
        isRecoveryRequired = false
        return state
    }

    @discardableResult
    public func edit(_ mutation: (inout OfflineAppState) throws -> Void) throws -> OfflineAppState {
        var candidate = state
        try mutation(&candidate)
        return try replace(candidate)
    }

    public func importAndroidBackup(_ data: Data) throws -> OfflineAppState {
        let imported = try AndroidBackupImporter().importData(data)
        // The Android portable backup intentionally excludes local grades.
        // Preserve the current private grades instead of treating an omitted
        // field as an instruction to delete them.
        var candidate = imported
        candidate.grades = state.grades
        return try replace(candidate, allowingRecovery: true)
    }

    public func importAndroidGrades(_ data: Data) throws -> OfflineAppState {
        var candidate = state
        candidate.grades = try AndroidGradesImporter().importData(data)
        return try replace(candidate)
    }

    public func addCourse(_ course: OfflineCourse) throws {
        try edit { state in state.courses.append(course) }
    }

    public func updateCourse(_ course: OfflineCourse) throws {
        try edit { state in
            guard let index = state.courses.firstIndex(where: { $0.id == course.id }) else {
                throw OfflineDataError.invalidField("course.id")
            }
            state.courses[index] = course
        }
    }

    public func deleteCourse(id: String) throws {
        try edit { state in state.courses.removeAll { $0.id == id } }
    }

    public func addGrade(_ grade: OfflineGrade) throws {
        try edit { state in state.grades.append(grade) }
    }

    public func updateGrade(_ grade: OfflineGrade) throws {
        try edit { state in
            guard let index = state.grades.firstIndex(where: { $0.id == grade.id }) else {
                throw OfflineDataError.invalidField("grade.id")
            }
            state.grades[index] = grade
        }
    }

    public func deleteGrade(id: String) throws {
        try edit { state in state.grades.removeAll { $0.id == id } }
    }

    public func upsertSemester(_ semester: OfflineSemester) throws {
        try edit { state in
            if let index = state.semesters.firstIndex(where: { $0.id == semester.id }) {
                state.semesters[index] = semester
            } else {
                state.semesters.append(semester)
            }
        }
    }

    public func deleteSemester(id: String) throws {
        try edit { state in
            guard !state.courses.contains(where: { $0.semesterId == id }) else {
                throw OfflineDataError.danglingReference(id)
            }
            state.semesters.removeAll { $0.id == id }
            if state.selectedSemesterId == id { state.selectedSemesterId = "" }
        }
    }
}
