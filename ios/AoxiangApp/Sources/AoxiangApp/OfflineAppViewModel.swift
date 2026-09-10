import Foundation
import AoxiangCore

#if os(iOS) && canImport(WidgetKit)
import WidgetKit
#endif

public protocol WidgetTimelineReloader {
    func reloadAllTimelines()
}

public struct NoopWidgetTimelineReloader: WidgetTimelineReloader {
    public init() {}
    public func reloadAllTimelines() {}
}

#if os(iOS) && canImport(WidgetKit)
public struct WidgetKitTimelineReloader: WidgetTimelineReloader {
    public init() {}
    public func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI

@MainActor
public final class OfflineAppViewModel: ObservableObject {
    public enum Tab: String, CaseIterable, Identifiable {
        case home = "首页"
        case grades = "成绩"
        case schedule = "课表"
        case management = "管理"
        public var id: String { rawValue }
    }

    @Published public private(set) var state: OfflineAppState
    @Published public var selectedTab: Tab = .home
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastImportSucceeded = false
    @Published public private(set) var lastPortalCollectionWarnings: [PortalCollectionWarning] = []
    /// A Widget/App Group failure is independent from the main app commit.
    /// Keep it observable without presenting a successful collection as an
    /// operation error.
    @Published public private(set) var lastWidgetSnapshotWarning: String?

    public let authenticationStore: AuthenticationSessionStore
    private let controller: OfflineDataController
    private let snapshotWriter: ReversibleWidgetSnapshotStore
    private let widgetTimelineReloader: WidgetTimelineReloader

    public init(
        controller: OfflineDataController,
        snapshotWriter: ReversibleWidgetSnapshotStore,
        authenticationStore: AuthenticationSessionStore = AuthenticationSessionStore(),
        widgetTimelineReloader: WidgetTimelineReloader = NoopWidgetTimelineReloader(),
        initialErrorMessage: String? = nil
    ) {
        self.controller = controller
        self.state = controller.state
        self.snapshotWriter = snapshotWriter
        self.authenticationStore = authenticationStore
        self.widgetTimelineReloader = widgetTimelineReloader
        self.errorMessage = initialErrorMessage
    }

    public static func makeDefault(
        fileManager: FileManager = .default,
        authenticationStore: AuthenticationSessionStore = AuthenticationSessionStore()
    ) -> OfflineAppViewModel {
        let stateURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline-state.json")
        let store = FileOfflineStateStore(fileURL: stateURL, fileManager: fileManager)
        let controller: OfflineDataController
        var initialErrors: [String] = []
        do {
            controller = try OfflineDataController(store: store)
        } catch {
            // Never replace an unreadable on-disk state with an empty one.
            // Only a validated Android backup may clear this recovery gate.
            controller = OfflineDataController.recoveryController(store: store)
            initialErrors.append("本地数据无法读取；原文件未被覆盖。请先导入 Android 备份恢复后再编辑。")
        }
        if AoxiangSharedContainer.sharedSnapshotURL(fileManager: fileManager) == nil {
            initialErrors.append("小组件共享容器不可用；本地数据仍可使用，但小组件不会更新。")
        }
        #if os(iOS) && canImport(WidgetKit)
        let timelineReloader: WidgetTimelineReloader = WidgetKitTimelineReloader()
        #else
        let timelineReloader: WidgetTimelineReloader = NoopWidgetTimelineReloader()
        #endif
        return OfflineAppViewModel(
            controller: controller,
            snapshotWriter: AoxiangSharedContainer.widgetSnapshotStore(fileManager: fileManager),
            authenticationStore: authenticationStore,
            widgetTimelineReloader: timelineReloader,
            initialErrorMessage: initialErrors.isEmpty ? nil : initialErrors.joined(separator: "\n")
        )
    }

    public func importBackup(data: Data) {
        do {
            _ = try controller.importAndroidBackup(data)
            state = controller.state
            errorMessage = nil
            lastImportSucceeded = true
            writeWidgetSnapshot()
        } catch {
            lastImportSucceeded = false
            errorMessage = error.localizedDescription
        }
    }

    public func exportBackup() -> Data? {
        do {
            guard !controller.isRecoveryRequired else {
                throw OfflineDataError.recoveryRequired
            }
            errorMessage = nil
            return try AndroidBackupExporter().exportData(from: state)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func importGrades(data: Data) {
        do {
            try controller.importAndroidGrades(data)
            state = controller.state
            errorMessage = nil
            writeWidgetSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies a complete foreground collection result as one main-app state
    /// change. Widget publication is best-effort: a missing or unavailable App
    /// Group must not discard valid grades, schedule, or electricity data.
    @discardableResult
    public func applyPortalCollection(_ result: PortalCollectedData) -> Bool {
        do {
            var candidate = state
            candidate.grades = result.grades
            if let gpa = result.gpa {
                candidate.gpa = gpa
            }
            if result.scheduleAvailable {
                candidate.semesters = result.schedule.semesters
                candidate.courses = result.schedule.courses
                if !candidate.selectedSemesterId.isEmpty,
                   !candidate.semesters.contains(where: { $0.id == candidate.selectedSemesterId }) {
                    candidate.selectedSemesterId = candidate.semesters.first?.id ?? ""
                } else if candidate.selectedSemesterId.isEmpty {
                    candidate.selectedSemesterId = candidate.semesters.first?.id ?? ""
                }
            }
            if let electricityBalance = result.electricityBalance {
                candidate.electricityBalance = electricityBalance
            }
            _ = try controller.replace(candidate)
            state = controller.state
            lastPortalCollectionWarnings = result.warnings
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        do {
            try persistWidgetSnapshot(for: state)
            lastWidgetSnapshotWarning = nil
        } catch {
            // The local commit above is authoritative. Snapshot storage is a
            // separate, atomic file boundary and may be unavailable for a
            // sideloaded target whose App Group was not provisioned.
            lastWidgetSnapshotWarning = widgetSnapshotWarning(for: error)
        }
        return true
    }

    @discardableResult
    public func addGrade(course: String, score: Double?, point: Double?, credits: Double) -> Bool {
        do {
            try controller.addGrade(OfflineGrade(
                course: course.trimmingCharacters(in: .whitespacesAndNewlines),
                credits: credits,
                point: point,
                score: score
            ))
            state = controller.state
            errorMessage = nil
            writeWidgetSnapshot()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func updateGrade(_ grade: OfflineGrade) -> Bool {
        do {
            try controller.updateGrade(grade)
            state = controller.state
            errorMessage = nil
            writeWidgetSnapshot()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func deleteGrade(id: String) {
        do {
            try controller.deleteGrade(id: id)
            state = controller.state
            errorMessage = nil
            writeWidgetSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func addCourse(name: String, semesterId: String) -> Bool {
        do {
            try controller.addCourse(OfflineCourse(
                id: UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                semesterId: semesterId
            ))
            state = controller.state
            errorMessage = nil
            writeWidgetSnapshot()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func updateCourse(_ course: OfflineCourse) -> Bool {
        do {
            try controller.updateCourse(course)
            state = controller.state
            errorMessage = nil
            writeWidgetSnapshot()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func deleteCourse(id: String) {
        do {
            try controller.deleteCourse(id: id)
            state = controller.state
            errorMessage = nil
            writeWidgetSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setSelectedSemester(_ id: String) {
        do {
            try controller.edit { $0.selectedSemesterId = id }
            state = controller.state
            errorMessage = nil
            writeWidgetSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearError() { errorMessage = nil }

    @discardableResult
    public func writeWidgetSnapshot(now: Date = Date()) -> Bool {
        do {
            try persistWidgetSnapshot(for: state, now: now)
            lastWidgetSnapshotWarning = nil
            return true
        } catch {
            let warning = widgetSnapshotWarning(for: error)
            lastWidgetSnapshotWarning = warning
            errorMessage = warning
            return false
        }
    }

    private func widgetSnapshotWarning(for error: Error) -> String {
        if let offlineError = error as? OfflineDataError,
           offlineError == .sharedContainerUnavailable {
            return "小组件共享容器不可用；本地数据已保存，但小组件不会更新。"
        }
        return "小组件快照无法写入；本地数据已保存。"
    }

    private func persistWidgetSnapshot(for value: OfflineAppState, now: Date = Date()) throws {
        let snapshot = try WidgetSnapshotBuilder().makeSnapshot(from: value, now: now)
        try snapshotWriter.write(snapshot)
        widgetTimelineReloader.reloadAllTimelines()
    }
}
#endif
