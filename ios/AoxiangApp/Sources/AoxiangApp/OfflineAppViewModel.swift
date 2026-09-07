import Foundation
import AoxiangCore

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

    public let authenticationStore: AuthenticationSessionStore
    private let controller: OfflineDataController
    private let snapshotWriter: WidgetSnapshotWriter

    public init(
        controller: OfflineDataController,
        snapshotWriter: WidgetSnapshotWriter,
        authenticationStore: AuthenticationSessionStore = AuthenticationSessionStore(),
        initialErrorMessage: String? = nil
    ) {
        self.controller = controller
        self.state = controller.state
        self.snapshotWriter = snapshotWriter
        self.authenticationStore = authenticationStore
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
        return OfflineAppViewModel(
            controller: controller,
            snapshotWriter: AoxiangSharedContainer.widgetSnapshotStore(fileManager: fileManager),
            authenticationStore: authenticationStore,
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

    public func writeWidgetSnapshot(now: Date = Date()) {
        do {
            let snapshot = try WidgetSnapshotBuilder().makeSnapshot(from: state, now: now)
            try snapshotWriter.write(snapshot)
        } catch {
            if let offlineError = error as? OfflineDataError,
               offlineError == .sharedContainerUnavailable {
                errorMessage = "小组件共享容器不可用；本地数据已保存，但小组件不会更新。"
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
#endif
