import Foundation

public enum ContractCapabilityStatus: String, Codable, Equatable {
    case covered
    case pending
}

public struct InfrastructureCapability: Codable, Equatable {
    public let id: String
    public let status: ContractCapabilityStatus
}

public struct FixtureKindCapability: Codable, Equatable {
    public let kind: String
    public let scenarioKeys: [String]
    public let status: ContractCapabilityStatus
    public let adapter: String?
    public let reason: String?
}

public struct ContractCoveragePolicy: Codable, Equatable {
    public let unknownFixtureKind: String
    public let missingFixtureKind: String
    public let coveredRequiresAdapter: Bool
}

public struct ContractCapabilityReport: Codable, Equatable {
    public let reportVersion: Int
    public let fixtureSchemaVersions: [Int]
    public let infrastructureCapabilities: [InfrastructureCapability]
    public let fixtureKinds: [FixtureKindCapability]
    public let policy: ContractCoveragePolicy

    public var coveredFixtureKinds: [String] {
        fixtureKinds.filter { $0.status == .covered }.map(\.kind).sorted()
    }

    public var pendingFixtureKinds: [String] {
        fixtureKinds.filter { $0.status == .pending }.map(\.kind).sorted()
    }
}

public enum ContractCapabilityError: Error, Equatable {
    case bundledReportMissing
    case reportUnreadable(String)
    case unsupportedReportVersion(Int)
    case invalidPolicy
    case duplicateInfrastructureCapability(String)
    case missingInfrastructureCapabilities([String])
    case infrastructureCapabilityNotCovered(String)
    case duplicateFixtureKind(String)
    case duplicateFixtureScenarioKey(kind: String, key: String)
    case duplicateFixtureSchemaVersion(Int)
    case fixtureKindMismatch(missing: [String], unknown: [String])
    case fixtureScenarioMismatch(kind: String, missing: [String], unknown: [String])
    case fixtureSchemaVersionMismatch(missing: [Int], unknown: [Int])
    case coveredFixtureKindMissingAdapter(String)
    case coveredFixtureKindNotRegistered(String)
    case pendingFixtureKindHasAdapter(String)
    case pendingFixtureKindMissingReason(String)
    case registeredFixtureKindStillPending(String)
    case unknownRegisteredFixtureKind(String)
    case pendingFixtureKinds([String])
}

extension ContractCapabilityError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bundledReportMissing:
            return "Bundled contract capability report is missing"
        case .reportUnreadable(let reason):
            return "Contract capability report is unreadable: \(reason)"
        case .unsupportedReportVersion(let version):
            return "Unsupported contract capability report version: \(version)"
        case .invalidPolicy:
            return "Contract capability report must fail on unknown and missing fixture kinds"
        case .duplicateInfrastructureCapability(let id):
            return "Duplicate infrastructure capability: \(id)"
        case .missingInfrastructureCapabilities(let ids):
            return "Missing infrastructure capabilities: \(ids.joined(separator: ", "))"
        case .infrastructureCapabilityNotCovered(let id):
            return "Infrastructure capability is not covered: \(id)"
        case .duplicateFixtureKind(let kind):
            return "Duplicate fixture kind capability: \(kind)"
        case .duplicateFixtureScenarioKey(let kind, let key):
            return "Duplicate fixture scenario key for \(kind): \(key)"
        case .duplicateFixtureSchemaVersion(let version):
            return "Duplicate fixture schema version declaration: \(version)"
        case .fixtureKindMismatch(let missing, let unknown):
            return "Fixture kind report mismatch; missing=\(missing), unknown=\(unknown)"
        case .fixtureScenarioMismatch(let kind, let missing, let unknown):
            return "Fixture scenario report mismatch for \(kind); missing=\(missing), unknown=\(unknown)"
        case .fixtureSchemaVersionMismatch(let missing, let unknown):
            return "Fixture schema version report mismatch; missing=\(missing), unknown=\(unknown)"
        case .coveredFixtureKindMissingAdapter(let kind):
            return "Covered fixture kind has no Swift adapter: \(kind)"
        case .coveredFixtureKindNotRegistered(let kind):
            return "Covered fixture kind has no matching registered Swift adapter: \(kind)"
        case .pendingFixtureKindHasAdapter(let kind):
            return "Pending fixture kind must not name a completed adapter: \(kind)"
        case .pendingFixtureKindMissingReason(let kind):
            return "Pending fixture kind must explain the missing Swift adapter: \(kind)"
        case .registeredFixtureKindStillPending(let kind):
            return "Registered Swift adapter is still reported as pending: \(kind)"
        case .unknownRegisteredFixtureKind(let kind):
            return "Registered Swift adapter has no manifest fixture kind: \(kind)"
        case .pendingFixtureKinds(let kinds):
            return "iOS business fixture kinds are still pending: \(kinds.joined(separator: ", "))"
        }
    }
}

/// Registry and fail-closed coverage gate for cross-platform behavior.
public enum ContractCapabilityRegistry {
    public static let requiredInfrastructureCapabilities: Set<String> = [
        "manifest-decoding",
        "schema-version-gate",
        "fixture-path-containment",
        "fixture-reference-integrity",
        "fixture-secret-scan",
    ]

    /// Keep this registry empty until a real Swift adapter and fixture-driven
    /// output assertion exist. A JSON-only status change must fail validation.
    public static let registeredBusinessAdapters: [String: String] = [:]

    public static func loadBundledReport() throws -> ContractCapabilityReport {
        guard let url = Bundle.module.url(
            forResource: "contract-capabilities",
            withExtension: "json"
        ) else {
            throw ContractCapabilityError.bundledReportMissing
        }
        return try loadReport(from: url)
    }

    public static func loadReport(from url: URL) throws -> ContractCapabilityReport {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ContractCapabilityReport.self, from: data)
        } catch {
            throw ContractCapabilityError.reportUnreadable(error.localizedDescription)
        }
    }

    public static func enforceConfiguredCoverage(
        _ report: ContractCapabilityReport,
        against manifest: GoldenFixtureManifest,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if environment["AOXIANG_REQUIRE_IOS_BUSINESS_COVERAGE"] == "1" {
            try requireCompleteBusinessCoverage(report, against: manifest)
        } else {
            try validate(report, against: manifest)
        }
    }

    public static func enforceConfiguredCoverage(
        _ report: ContractCapabilityReport,
        against manifests: [GoldenFixtureManifest],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if environment["AOXIANG_REQUIRE_IOS_BUSINESS_COVERAGE"] == "1" {
            try requireCompleteBusinessCoverage(report, against: manifests)
        } else {
            try validate(report, against: manifests)
        }
    }

    public static func validate(
        _ report: ContractCapabilityReport,
        against manifests: [GoldenFixtureManifest]
    ) throws {
        let actualVersions = Set(manifests.map(\.schemaVersion))
        try validateDeclaredSchemaVersions(report.fixtureSchemaVersions, against: actualVersions)

        guard !manifests.isEmpty else {
            throw ContractCapabilityError.fixtureSchemaVersionMismatch(
                missing: [],
                unknown: report.fixtureSchemaVersions.sorted()
            )
        }
        try validateReportShape(report)
        try validateFixtureKinds(
            report,
            against: scenarioKeysByKind(manifests)
        )
    }

    public static func validate(
        _ report: ContractCapabilityReport,
        against manifest: GoldenFixtureManifest
    ) throws {
        try validateDeclaredSchemaVersions(
            report.fixtureSchemaVersions,
            against: Set([manifest.schemaVersion])
        )
        try validateReportShape(report)
        try validateFixtureKinds(report, against: scenarioKeysByKind([manifest]))
    }

    private static func validateDeclaredSchemaVersions(
        _ declaredVersions: [Int],
        against actualVersions: Set<Int>
    ) throws {
        var seen = Set<Int>()
        for version in declaredVersions {
            guard seen.insert(version).inserted else {
                throw ContractCapabilityError.duplicateFixtureSchemaVersion(version)
            }
        }
        let declared = Set(declaredVersions)
        let missingVersions = actualVersions.subtracting(declared).sorted()
        let unknownVersions = declared.subtracting(actualVersions).sorted()
        guard missingVersions.isEmpty, unknownVersions.isEmpty else {
            throw ContractCapabilityError.fixtureSchemaVersionMismatch(
                missing: missingVersions,
                unknown: unknownVersions
            )
        }
    }

    private static func validateReportShape(
        _ report: ContractCapabilityReport
    ) throws {
        guard report.reportVersion == 1 else {
            throw ContractCapabilityError.unsupportedReportVersion(report.reportVersion)
        }
        guard report.policy.unknownFixtureKind == "fail",
              report.policy.missingFixtureKind == "fail",
              report.policy.coveredRequiresAdapter else {
            throw ContractCapabilityError.invalidPolicy
        }
        var infrastructureIDs = Set<String>()
        for capability in report.infrastructureCapabilities {
            guard infrastructureIDs.insert(capability.id).inserted else {
                throw ContractCapabilityError.duplicateInfrastructureCapability(capability.id)
            }
            guard capability.status == .covered else {
                throw ContractCapabilityError.infrastructureCapabilityNotCovered(capability.id)
            }
        }
        let missingInfrastructure = requiredInfrastructureCapabilities
            .subtracting(infrastructureIDs)
            .sorted()
        guard missingInfrastructure.isEmpty else {
            throw ContractCapabilityError.missingInfrastructureCapabilities(missingInfrastructure)
        }

    }

    private static func validateFixtureKinds(
        _ report: ContractCapabilityReport,
        against scenariosByKind: [String: Set<String>]
    ) throws {
        var reportKinds = Set<String>()
        for capability in report.fixtureKinds {
            guard reportKinds.insert(capability.kind).inserted else {
                throw ContractCapabilityError.duplicateFixtureKind(capability.kind)
            }
            var reportScenarioKeys = Set<String>()
            for key in capability.scenarioKeys {
                guard reportScenarioKeys.insert(key).inserted else {
                    throw ContractCapabilityError.duplicateFixtureScenarioKey(
                        kind: capability.kind,
                        key: key
                    )
                }
            }
            if let expectedScenarioKeys = scenariosByKind[capability.kind] {
                let missing = expectedScenarioKeys.subtracting(reportScenarioKeys).sorted()
                let unknown = reportScenarioKeys.subtracting(expectedScenarioKeys).sorted()
                guard missing.isEmpty, unknown.isEmpty else {
                    throw ContractCapabilityError.fixtureScenarioMismatch(
                        kind: capability.kind,
                        missing: missing,
                        unknown: unknown
                    )
                }
            }
            switch capability.status {
            case .covered:
                guard let adapter = capability.adapter, !adapter.isEmpty else {
                    throw ContractCapabilityError.coveredFixtureKindMissingAdapter(capability.kind)
                }
                guard registeredBusinessAdapters[capability.kind] == adapter else {
                    throw ContractCapabilityError.coveredFixtureKindNotRegistered(capability.kind)
                }
            case .pending:
                guard capability.adapter == nil else {
                    throw ContractCapabilityError.pendingFixtureKindHasAdapter(capability.kind)
                }
                guard capability.reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    throw ContractCapabilityError.pendingFixtureKindMissingReason(capability.kind)
                }
                guard registeredBusinessAdapters[capability.kind] == nil else {
                    throw ContractCapabilityError.registeredFixtureKindStillPending(capability.kind)
                }
            }
        }

        let manifestKinds = Set(scenariosByKind.keys)
        let missing = manifestKinds.subtracting(reportKinds).sorted()
        let unknown = reportKinds.subtracting(manifestKinds).sorted()
        guard missing.isEmpty, unknown.isEmpty else {
            throw ContractCapabilityError.fixtureKindMismatch(missing: missing, unknown: unknown)
        }
        if let unknownRegisteredKind = registeredBusinessAdapters.keys
            .first(where: { !manifestKinds.contains($0) }) {
            throw ContractCapabilityError.unknownRegisteredFixtureKind(unknownRegisteredKind)
        }
    }

    private static func scenarioKeysByKind(
        _ manifests: [GoldenFixtureManifest]
    ) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for manifest in manifests {
            for scenario in manifest.scenarios {
                let key = "v\(manifest.schemaVersion)/\(scenario.id)"
                result[scenario.kind, default: []].insert(key)
            }
        }
        return result
    }

    /// Use this as the release gate once iOS business adapters begin landing.
    /// It intentionally fails today because all business fixture kinds are pending.
    public static func requireCompleteBusinessCoverage(
        _ report: ContractCapabilityReport,
        against manifest: GoldenFixtureManifest
    ) throws {
        try validate(report, against: manifest)
        let pending = report.pendingFixtureKinds
        guard pending.isEmpty else {
            throw ContractCapabilityError.pendingFixtureKinds(pending)
        }
    }


    public static func requireCompleteBusinessCoverage(
        _ report: ContractCapabilityReport,
        against manifests: [GoldenFixtureManifest]
    ) throws {
        try validate(report, against: manifests)
        let pending = report.pendingFixtureKinds
        guard pending.isEmpty else {
            throw ContractCapabilityError.pendingFixtureKinds(pending)
        }
    }
}
