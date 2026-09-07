import Foundation
import XCTest
@testable import AoxiangCore

final class GoldenFixtureContractTests: XCTestCase {
    func testSharedRepositoryFixtureCorpusPassesFoundationValidation() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )

        XCTAssertEqual(manifests.map(\.schemaVersion), [1])
        XCTAssertEqual(manifests.first?.suite, "aoxiang-assistant.golden")
        XCTAssertEqual(manifests.first?.businessTimeZone, "Asia/Shanghai")
        XCTAssertEqual(manifests.first?.scenarios.count, 15)
    }

    func testCapabilityReportNamesEveryManifestKindWithoutClaimingBusinessCoverage() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()

        try ContractCapabilityRegistry.validate(report, against: manifests)

        let manifestKinds = Set(manifests.flatMap(\.scenarios).map(\.kind))
        XCTAssertEqual(Set(report.pendingFixtureKinds), manifestKinds)
        XCTAssertTrue(report.coveredFixtureKinds.isEmpty)
        XCTAssertEqual(report.pendingFixtureKinds.count, 15)
    }

    func testCapabilityReportDeclaresEveryDiscoveredFixtureVersion() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()

        XCTAssertEqual(
            GoldenFixtureContract.supportedSchemaVersions,
            Set(manifests.map(\.schemaVersion))
        )
        XCTAssertEqual(
            Set(report.fixtureSchemaVersions),
            Set(manifests.map(\.schemaVersion))
        )
    }

    func testCapabilityReportRejectsDuplicateFixtureSchemaVersion() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()
        let duplicatedReport = ContractCapabilityReport(
            reportVersion: report.reportVersion,
            fixtureSchemaVersions: [1, 1],
            infrastructureCapabilities: report.infrastructureCapabilities,
            fixtureKinds: report.fixtureKinds,
            policy: report.policy
        )

        XCTAssertThrowsError(
            try ContractCapabilityRegistry.validate(duplicatedReport, against: manifests)
        ) { error in
            XCTAssertEqual(
                error as? ContractCapabilityError,
                .duplicateFixtureSchemaVersion(1)
            )
        }
    }

    func testSingleManifestValidationRejectsUndeclaredExtraFixtureVersion() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()
        let widenedReport = ContractCapabilityReport(
            reportVersion: report.reportVersion,
            fixtureSchemaVersions: [1, 2],
            infrastructureCapabilities: report.infrastructureCapabilities,
            fixtureKinds: report.fixtureKinds,
            policy: report.policy
        )

        XCTAssertThrowsError(
            try ContractCapabilityRegistry.validate(
                widenedReport,
                against: try XCTUnwrap(manifests.first)
            )
        ) { error in
            XCTAssertEqual(
                error as? ContractCapabilityError,
                .fixtureSchemaVersionMismatch(missing: [], unknown: [2])
            )
        }
    }

    func testCapabilityReportRejectsMissingScenarioKey() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()
        let original = try XCTUnwrap(report.fixtureKinds.first)
        let missingScenario = FixtureKindCapability(
            kind: original.kind,
            scenarioKeys: [],
            status: original.status,
            adapter: original.adapter,
            reason: original.reason
        )
        let modifiedReport = ContractCapabilityReport(
            reportVersion: report.reportVersion,
            fixtureSchemaVersions: report.fixtureSchemaVersions,
            infrastructureCapabilities: report.infrastructureCapabilities,
            fixtureKinds: [missingScenario] + Array(report.fixtureKinds.dropFirst()),
            policy: report.policy
        )

        XCTAssertThrowsError(
            try ContractCapabilityRegistry.validate(modifiedReport, against: manifests)
        ) { error in
            XCTAssertEqual(
                error as? ContractCapabilityError,
                .fixtureScenarioMismatch(
                    kind: original.kind,
                    missing: original.scenarioKeys,
                    unknown: []
                )
            )
        }
    }

    func testCompleteBusinessCoverageGateFailsWhileAdaptersArePending() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()

        XCTAssertThrowsError(
            try ContractCapabilityRegistry.requireCompleteBusinessCoverage(
                report,
                against: manifests
            )
        ) { error in
            guard case ContractCapabilityError.pendingFixtureKinds(let kinds) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(kinds.count, 15)
        }
    }

    func testCapabilityReportCannotClaimCoveredWithoutRegisteredAdapter() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()
        let original = try XCTUnwrap(report.fixtureKinds.first)
        let fakeCoverage = FixtureKindCapability(
            kind: original.kind,
            scenarioKeys: original.scenarioKeys,
            status: .covered,
            adapter: "UnimplementedAdapter",
            reason: nil
        )
        let modifiedReport = ContractCapabilityReport(
            reportVersion: report.reportVersion,
            fixtureSchemaVersions: report.fixtureSchemaVersions,
            infrastructureCapabilities: report.infrastructureCapabilities,
            fixtureKinds: [fakeCoverage] + Array(report.fixtureKinds.dropFirst()),
            policy: report.policy
        )

        XCTAssertThrowsError(
            try ContractCapabilityRegistry.validate(modifiedReport, against: manifests)
        ) { error in
            XCTAssertEqual(
                error as? ContractCapabilityError,
                .coveredFixtureKindNotRegistered(original.kind)
            )
        }
    }

    func testConfiguredReleaseGateRejectsPendingBusinessAdapters() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()

        XCTAssertNoThrow(
            try ContractCapabilityRegistry.enforceConfiguredCoverage(
                report,
                against: manifests,
                environment: [:]
            )
        )
        XCTAssertThrowsError(
            try ContractCapabilityRegistry.enforceConfiguredCoverage(
                report,
                against: manifests,
                environment: ["AOXIANG_REQUIRE_IOS_BUSINESS_COVERAGE": "1"]
            )
        )
    }

    func testEnvironmentControlledCoverageGate() throws {
        let manifests = try GoldenFixtureContract.loadAndValidateCorpus(
            corpusDirectory: Self.fixtureCorpusDirectory
        )
        let report = try ContractCapabilityRegistry.loadBundledReport()

        try ContractCapabilityRegistry.enforceConfiguredCoverage(
            report,
            against: manifests
        )
    }

    func testUnsupportedSchemaVersionFailsClosed() throws {
        let directory = try makeFixtureDirectory(schemaVersion: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try GoldenFixtureContract.loadAndValidate(fixtureDirectory: directory)
        ) { error in
            XCTAssertEqual(error as? GoldenFixtureContractError, .unsupportedSchemaVersion(2))
        }
    }

    func testTraversalFixturePathFailsBeforeReadingOutsideCorpus() throws {
        let directory = try makeFixtureDirectory(inputPath: "../outside.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try GoldenFixtureContract.loadAndValidate(fixtureDirectory: directory)
        ) { error in
            XCTAssertEqual(
                error as? GoldenFixtureContractError,
                .invalidFixturePath("../outside.json")
            )
        }
    }

    func testNonPortableFixturePathFailsClosed() throws {
        let directory = try makeFixtureDirectory(inputPath: "sample:input.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try GoldenFixtureContract.loadAndValidate(fixtureDirectory: directory)
        ) { error in
            XCTAssertEqual(
                error as? GoldenFixtureContractError,
                .invalidFixturePath("sample:input.json")
            )
        }
    }

    func testSecretLikeInputKeyFailsClosed() throws {
        let directory = try makeFixtureDirectory(input: ["password": "fictional"])
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try GoldenFixtureContract.loadAndValidate(fixtureDirectory: directory)
        ) { error in
            XCTAssertEqual(
                error as? GoldenFixtureContractError,
                .forbiddenFixtureKey("password")
            )
        }
    }

    func testNullFixtureRootFailsClosed() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("null".utf8).write(
            to: directory.appendingPathComponent("sample/input.json")
        )

        XCTAssertThrowsError(
            try GoldenFixtureContract.loadAndValidate(fixtureDirectory: directory)
        ) { error in
            XCTAssertEqual(
                error as? GoldenFixtureContractError,
                .invalidJSONFixture("sample/input.json")
            )
        }
    }

    private static var packageDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var fixtureCorpusDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["AOXIANG_GOLDEN_FIXTURES"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return packageDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contract-fixtures/golden", isDirectory: true)
    }

    private func makeFixtureDirectory(
        schemaVersion: Int = 1,
        inputPath: String = "sample/input.json",
        input: [String: Any] = ["value": "safe"]
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sample = root.appendingPathComponent("sample", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sample,
            withIntermediateDirectories: true
        )

        let manifest: [String: Any] = [
            "schemaVersion": schemaVersion,
            "suite": "aoxiang-assistant.golden",
            "businessTimeZone": "Asia/Shanghai",
            "scenarios": [[
                "id": "sample",
                "kind": "sample",
                "input": inputPath,
                "expected": "sample/expected.json",
            ]],
        ]
        try writeJSON(manifest, to: root.appendingPathComponent("manifest.json"))
        try writeJSON(input, to: sample.appendingPathComponent("input.json"))
        try writeJSON(["value": "safe"], to: sample.appendingPathComponent("expected.json"))
        return root
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: url)
    }
}
