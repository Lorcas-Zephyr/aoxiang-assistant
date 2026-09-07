import Foundation

/// Shared file location used by the main iOS app and its Widget extension.
/// The portable package keeps the path contract in one place; it does not
/// expose credentials, cookies, authentication state, or network clients.
public enum AoxiangSharedContainer {
    public static let appGroupIdentifier = "group.cn.nwpu.aoxiang-assistant"
    public static let snapshotFileName = "widget-snapshot.json"

    /// Returns the App Group location exclusively. A missing entitlement,
    /// provisioning capability, or non-iOS host must be treated as unavailable
    /// instead of falling back to either target's private sandbox.
    public static func sharedSnapshotURL(
        fileManager: FileManager = .default
    ) -> URL? {
        #if os(iOS)
        return fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )?.appendingPathComponent(snapshotFileName)
        #else
        return nil
        #endif
    }

    /// Creates a store for the sole App Group path. The unavailable store is
    /// intentional: callers can keep their own local state but cannot create a
    /// misleading, target-private Widget snapshot.
    public static func widgetSnapshotStore(
        fileManager: FileManager = .default
    ) -> ReversibleWidgetSnapshotStore {
        guard let fileURL = sharedSnapshotURL(fileManager: fileManager) else {
            return UnavailableWidgetSnapshotStore()
        }
        return FileWidgetSnapshotStore(fileURL: fileURL, fileManager: fileManager)
    }
}

/// Represents an unavailable App Group at the Widget storage boundary. Both
/// reads and writes fail explicitly so neither target can silently consume its
/// own private copy of the snapshot.
public final class UnavailableWidgetSnapshotStore: ReversibleWidgetSnapshotStore {
    public init() {}

    public func read() throws -> WidgetSnapshot? {
        throw OfflineDataError.sharedContainerUnavailable
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        throw OfflineDataError.sharedContainerUnavailable
    }

    public func restore(_ snapshot: WidgetSnapshot?) throws {
        throw OfflineDataError.sharedContainerUnavailable
    }
}
