import Foundation

/// Shared file location used by the main iOS app and its Widget extension.
/// The portable package keeps the path contract in one place; it does not
/// expose credentials, cookies, authentication state, or network clients.
public enum AoxiangSharedContainer {
    /// The source default is useful for the project's own provisioning setup.
    /// Re-signers may use a team-owned App Group; the Xcode targets stamp that
    /// value into both Info.plists so the binary and signed entitlement agree.
    public static let defaultAppGroupIdentifier = "group.cn.nwpu.aoxiang-assistant"
    public static let snapshotFileName = "widget-snapshot.json"

    /// The bundle value is the runtime contract for the shared container. A
    /// re-signer that changes the App Group must update this Info.plist value
    /// together with both signed entitlements; iOS does not expose a supported
    /// public API for reading another target's application-groups entitlement.
    public static var appGroupIdentifier: String {
        configuredAppGroupIdentifier() ?? defaultAppGroupIdentifier
    }

    /// Orders possible group identifiers without touching the filesystem.
    /// `nil` means that no signed-entitlement list is available to the caller
    /// (for example on a host test). The helper remains pure so tests and
    /// packaging tools can resolve a deterministic candidate order without
    /// depending on platform security APIs.
    static func appGroupCandidates(
        configuredIdentifier: String?,
        entitledIdentifiers: [String]?,
        bundleIdentifier: String? = nil
    ) -> [String] {
        let configured = configuredIdentifier.flatMap(normalizeGroupIdentifier)
        let entitled = entitledIdentifiers?.compactMap(normalizeGroupIdentifier) ?? []
        var candidates: [String] = []

        func append(_ value: String?) {
            guard let value, !candidates.contains(value) else { return }
            candidates.append(value)
        }

        if entitledIdentifiers != nil {
            // When the signed entitlement is available, a stale plist value
            // is deliberately ignored unless the signer actually authorized
            // it. This is what lets common sideloaders use their team-owned
            // App Group without requiring a plist rewrite.
            if let configured, entitled.contains(configured) {
                append(configured)
            }
            entitled.forEach { append($0) }
        } else {
            append(configured)
            append(derivedGroupIdentifier(from: bundleIdentifier))
            append(defaultAppGroupIdentifier)
        }
        return candidates
    }

    /// Returns the App Group location exclusively. A missing entitlement,
    /// provisioning capability, or non-iOS host must be treated as unavailable
    /// instead of falling back to either target's private sandbox.
    public static func sharedSnapshotURL(
        fileManager: FileManager = .default
    ) -> URL? {
        #if os(iOS)
        for identifier in appGroupCandidates(
            configuredIdentifier: configuredAppGroupIdentifier(),
            entitledIdentifiers: nil,
            bundleIdentifier: Bundle.main.bundleIdentifier
        ) {
            if let container = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            ) {
                return container.appendingPathComponent(snapshotFileName)
            }
        }
        return nil
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

    private static func configuredAppGroupIdentifier() -> String? {
        guard let configured = Bundle.main.object(
            forInfoDictionaryKey: "AoxiangAppGroupIdentifier"
        ) as? String else {
            return nil
        }
        return normalizeGroupIdentifier(configured)
    }

    private static func normalizeGroupIdentifier(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("group."), !normalized.contains("$(") else {
            return nil
        }
        return normalized
    }

    /// Many sideload tools rewrite both bundle identifiers and signed
    /// entitlements, but leave the build-time App Group plist placeholder
    /// unchanged. When the entitlement list cannot be inspected through a
    /// public API, derive the conventional team-owned group as a candidate;
    /// `containerURL` remains the authority and rejects unauthorized values.
    private static func derivedGroupIdentifier(from bundleIdentifier: String?) -> String? {
        guard var normalized = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty,
              !normalized.contains("$("),
              !normalized.contains(" ") else {
            return nil
        }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: true)
        if parts.last?.lowercased() == "widget" {
            normalized = parts.dropLast().joined(separator: ".")
        }
        guard !normalized.isEmpty else { return nil }
        return normalizeGroupIdentifier("group.\(normalized)")
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
