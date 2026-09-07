import Foundation

public struct GoldenFixtureManifest: Codable, Equatable {
    public let schemaVersion: Int
    public let suite: String
    public let businessTimeZone: String
    public let scenarios: [GoldenFixtureScenario]
}

public struct GoldenFixtureScenario: Codable, Equatable {
    public let id: String
    public let kind: String
    public let input: String
    public let html: String?
    public let expected: String
}

public enum GoldenFixtureContractError: Error, Equatable {
    case fixtureCorpusMissing(String)
    case fixtureCorpusUnreadable(String)
    case invalidFixtureVersionEntry(String)
    case nonContiguousFixtureVersions([Int])
    case fixtureVersionMismatch(directoryVersion: Int, schemaVersion: Int)
    case fixtureDirectoryMissing(String)
    case manifestUnreadable(String)
    case unsupportedSchemaVersion(Int)
    case invalidSuite(String)
    case invalidBusinessTimeZone(String)
    case duplicateScenarioID(String)
    case emptyScenarioField(String)
    case invalidFixturePath(String)
    case duplicateFixturePath(String)
    case missingFixture(String)
    case unreadableFixture(String)
    case invalidJSONFixture(String)
    case forbiddenFixtureKey(String)
    case forbiddenFixtureValue(String)
    case expectedValueInInput(String)
    case forbiddenHTMLContent(String)
    case unexpectedRootFile(String)
    case unreferencedFixtureFiles([String])
}

extension GoldenFixtureContractError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fixtureCorpusMissing(let path):
            return "Golden fixture corpus directory is missing: \(path)"
        case .fixtureCorpusUnreadable(let reason):
            return "Golden fixture corpus cannot be enumerated: \(reason)"
        case .invalidFixtureVersionEntry(let name):
            return "Golden fixture corpus contains an invalid version entry: \(name)"
        case .nonContiguousFixtureVersions(let versions):
            return "Golden fixture versions must be contiguous from v1: \(versions)"
        case .fixtureVersionMismatch(let directoryVersion, let schemaVersion):
            return "Golden fixture v\(directoryVersion) declares schemaVersion \(schemaVersion)"
        case .fixtureDirectoryMissing(let path):
            return "Golden fixture directory is missing: \(path)"
        case .manifestUnreadable(let reason):
            return "Golden manifest is unreadable: \(reason)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported golden fixture schema version: \(version)"
        case .invalidSuite(let suite):
            return "Unexpected golden fixture suite: \(suite)"
        case .invalidBusinessTimeZone(let timeZone):
            return "Unexpected golden fixture business time zone: \(timeZone)"
        case .duplicateScenarioID(let id):
            return "Duplicate golden fixture scenario id: \(id)"
        case .emptyScenarioField(let field):
            return "Golden fixture scenario field is empty: \(field)"
        case .invalidFixturePath(let path):
            return "Unsafe golden fixture path: \(path)"
        case .duplicateFixturePath(let path):
            return "Golden fixture path is referenced more than once: \(path)"
        case .missingFixture(let path):
            return "Golden fixture is missing: \(path)"
        case .unreadableFixture(let path):
            return "Golden fixture cannot be read as UTF-8: \(path)"
        case .invalidJSONFixture(let path):
            return "Golden fixture is not valid JSON: \(path)"
        case .forbiddenFixtureKey(let key):
            return "Golden fixture contains a forbidden key: \(key)"
        case .forbiddenFixtureValue(let value):
            return "Golden fixture contains a forbidden value: \(value)"
        case .expectedValueInInput(let key):
            return "Golden input contains an expected-output key: \(key)"
        case .forbiddenHTMLContent(let path):
            return "Golden HTML fixture contains secret-like content: \(path)"
        case .unexpectedRootFile(let path):
            return "Golden fixture root contains an unexpected file: \(path)"
        case .unreferencedFixtureFiles(let paths):
            return "Golden fixture files are not indexed by the manifest: \(paths.joined(separator: ", "))"
        }
    }
}

/// Foundation-only validation shared by the future iOS domain adapters.
///
/// This validates the fixture contract itself. It deliberately does not claim
/// that any Android business behavior has been implemented in Swift.
public enum GoldenFixtureContract {
    public static let supportedSchemaVersions: Set<Int> = [1]
    public static let requiredSuite = "aoxiang-assistant.golden"
    public static let requiredBusinessTimeZone = "Asia/Shanghai"

    private static let allowedRootFiles: Set<String> = ["README.md", "manifest.json"]
    private static let forbiddenKeyFragments = [
        "password", "cookie", "token", "account", "studentid", "studentno",
        "captcha", "smscode", "verificationcode", "authorization", "setcookie",
        "session", "secret",
    ]
    private static let expectedOnlyKeys: Set<String> = [
        "expected", "settlement", "deferexpected", "overdueexpected",
        "authexited", "credentialsvalid", "interactivelogin",
        "explicitcredentialerror", "gradechangednames", "schedulechangednames",
        "gradenotification", "schedulenotification", "selectedgpa",
    ]
    private static let allowedValueTokens: Set<String> = ["sessionexpired"]

    public static func loadAndValidateCorpus(
        corpusDirectory: URL,
        supportedSchemaVersions: Set<Int> = supportedSchemaVersions,
        fileManager: FileManager = .default
    ) throws -> [GoldenFixtureManifest] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: corpusDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GoldenFixtureContractError.fixtureCorpusMissing(corpusDirectory.path)
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: corpusDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw GoldenFixtureContractError.fixtureCorpusUnreadable(error.localizedDescription)
        }

        var versionDirectories: [(version: Int, url: URL)] = []
        for entry in entries {
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
            } catch {
                throw GoldenFixtureContractError.fixtureCorpusUnreadable(
                    error.localizedDescription
                )
            }
            guard values.isSymbolicLink != true,
                  values.isDirectory == true,
                  let version = fixtureVersion(from: entry.lastPathComponent) else {
                throw GoldenFixtureContractError.invalidFixtureVersionEntry(
                    entry.lastPathComponent
                )
            }
            versionDirectories.append((version, entry))
        }

        versionDirectories.sort { $0.version < $1.version }
        let versions = versionDirectories.map(\.version)
        let expectedVersions = versions.last.map { Array(1...$0) } ?? []
        guard !versions.isEmpty, versions == expectedVersions else {
            throw GoldenFixtureContractError.nonContiguousFixtureVersions(versions)
        }

        return try versionDirectories.map { item in
            let manifest = try loadAndValidate(
                fixtureDirectory: item.url,
                supportedSchemaVersions: supportedSchemaVersions,
                fileManager: fileManager
            )
            guard manifest.schemaVersion == item.version else {
                throw GoldenFixtureContractError.fixtureVersionMismatch(
                    directoryVersion: item.version,
                    schemaVersion: manifest.schemaVersion
                )
            }
            return manifest
        }
    }

    public static func loadAndValidate(
        fixtureDirectory: URL,
        supportedSchemaVersions: Set<Int> = GoldenFixtureContract.supportedSchemaVersions,
        fileManager: FileManager = .default
    ) throws -> GoldenFixtureManifest {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fixtureDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GoldenFixtureContractError.fixtureDirectoryMissing(fixtureDirectory.path)
        }

        let manifestURL = fixtureDirectory.appendingPathComponent("manifest.json", isDirectory: false)
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw GoldenFixtureContractError.manifestUnreadable(error.localizedDescription)
        }

        let manifest: GoldenFixtureManifest
        do {
            manifest = try JSONDecoder().decode(GoldenFixtureManifest.self, from: manifestData)
        } catch {
            throw GoldenFixtureContractError.manifestUnreadable(error.localizedDescription)
        }

        guard supportedSchemaVersions.contains(manifest.schemaVersion) else {
            throw GoldenFixtureContractError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard manifest.suite == requiredSuite else {
            throw GoldenFixtureContractError.invalidSuite(manifest.suite)
        }
        guard manifest.businessTimeZone == requiredBusinessTimeZone else {
            throw GoldenFixtureContractError.invalidBusinessTimeZone(manifest.businessTimeZone)
        }

        try validateManifestSecurity(manifestData)
        try validateScenarios(
            manifest.scenarios,
            fixtureDirectory: fixtureDirectory,
            fileManager: fileManager
        )
        return manifest
    }

    private static func validateManifestSecurity(_ data: Data) throws {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GoldenFixtureContractError.manifestUnreadable(error.localizedDescription)
        }
        try validateJSONValue(value, rejectExpectedOnlyKeys: false)
    }

    private static func validateScenarios(
        _ scenarios: [GoldenFixtureScenario],
        fixtureDirectory: URL,
        fileManager: FileManager
    ) throws {
        var scenarioIDs = Set<String>()
        var referencedPaths = Set<String>()

        for scenario in scenarios {
            guard !scenario.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GoldenFixtureContractError.emptyScenarioField("id")
            }
            guard !scenario.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GoldenFixtureContractError.emptyScenarioField("\(scenario.id).kind")
            }
            guard scenarioIDs.insert(scenario.id).inserted else {
                throw GoldenFixtureContractError.duplicateScenarioID(scenario.id)
            }

            try validateJSONFixture(
                scenario.input,
                expectedOnlyKeysAreForbidden: true,
                fixtureDirectory: fixtureDirectory,
                referencedPaths: &referencedPaths,
                fileManager: fileManager
            )
            try validateJSONFixture(
                scenario.expected,
                expectedOnlyKeysAreForbidden: false,
                fixtureDirectory: fixtureDirectory,
                referencedPaths: &referencedPaths,
                fileManager: fileManager
            )
            if let html = scenario.html {
                try validateHTMLFixture(
                    html,
                    fixtureDirectory: fixtureDirectory,
                    referencedPaths: &referencedPaths,
                    fileManager: fileManager
                )
            }
        }

        let actualFixtureFiles = try fixtureFiles(
            under: fixtureDirectory,
            fileManager: fileManager
        )
        let unreferenced = actualFixtureFiles.subtracting(referencedPaths).sorted()
        guard unreferenced.isEmpty else {
            throw GoldenFixtureContractError.unreferencedFixtureFiles(unreferenced)
        }
    }

    private static func validateJSONFixture(
        _ rawPath: String,
        expectedOnlyKeysAreForbidden: Bool,
        fixtureDirectory: URL,
        referencedPaths: inout Set<String>,
        fileManager: FileManager
    ) throws {
        let path = try register(
            rawPath,
            requiredExtension: "json",
            fixtureDirectory: fixtureDirectory,
            referencedPaths: &referencedPaths,
            fileManager: fileManager
        )
        let data = try fixtureData(
            at: path,
            fixtureDirectory: fixtureDirectory,
            fileManager: fileManager
        )
        guard String(data: data, encoding: .utf8) != nil else {
            throw GoldenFixtureContractError.unreadableFixture(path)
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GoldenFixtureContractError.invalidJSONFixture(path)
        }
        guard value is [String: Any] || value is [Any] else {
            throw GoldenFixtureContractError.invalidJSONFixture(path)
        }
        try validateJSONValue(value, rejectExpectedOnlyKeys: expectedOnlyKeysAreForbidden)
    }

    private static func validateHTMLFixture(
        _ rawPath: String,
        fixtureDirectory: URL,
        referencedPaths: inout Set<String>,
        fileManager: FileManager
    ) throws {
        let path = try register(
            rawPath,
            requiredExtension: "html",
            fixtureDirectory: fixtureDirectory,
            referencedPaths: &referencedPaths,
            fileManager: fileManager
        )
        let data = try fixtureData(
            at: path,
            fixtureDirectory: fixtureDirectory,
            fileManager: fileManager
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw GoldenFixtureContractError.unreadableFixture(path)
        }
        let lowercased = html.lowercased()
        let normalized = normalizedToken(html)
        let hasExplicitSecretMarkup = lowercased.contains("set-cookie")
            || lowercased.contains("authorization:")
            || lowercased.contains("type=\"password\"")
            || lowercased.contains("type='password'")
        let hasForbiddenToken = forbiddenKeyFragments.contains { normalized.contains($0) }
        guard !hasExplicitSecretMarkup, !hasForbiddenToken else {
            throw GoldenFixtureContractError.forbiddenHTMLContent(path)
        }
    }

    private static func register(
        _ rawPath: String,
        requiredExtension: String,
        fixtureDirectory: URL,
        referencedPaths: inout Set<String>,
        fileManager: FileManager
    ) throws -> String {
        let path = try validatedRelativePath(
            rawPath,
            fixtureDirectory: fixtureDirectory,
            fileManager: fileManager
        )
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == requiredExtension else {
            throw GoldenFixtureContractError.invalidFixturePath(rawPath)
        }
        guard referencedPaths.insert(path).inserted else {
            throw GoldenFixtureContractError.duplicateFixturePath(path)
        }
        return path
    }

    private static func validatedRelativePath(
        _ rawPath: String,
        fixtureDirectory: URL,
        fileManager: FileManager
    ) throws -> String {
        guard rawPath == rawPath.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty,
              !rawPath.contains("\\"),
              !rawPath.hasPrefix("/"),
              !rawPath.hasSuffix("/") else {
            throw GoldenFixtureContractError.invalidFixturePath(rawPath)
        }

        let components = rawPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ component in
                  !component.isEmpty
                      && component != "."
                      && component != ".."
                      && !component.contains(":")
                      && component.unicodeScalars.allSatisfy {
                          !CharacterSet.controlCharacters.contains($0)
                      }
              }) else {
            throw GoldenFixtureContractError.invalidFixturePath(rawPath)
        }

        let root = fixtureDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root
            .appendingPathComponent(rawPath, isDirectory: false)
            .standardizedFileURL
        guard isContained(candidate, by: root) else {
            throw GoldenFixtureContractError.invalidFixturePath(rawPath)
        }

        guard fileManager.fileExists(atPath: candidate.path) else {
            throw GoldenFixtureContractError.missingFixture(rawPath)
        }
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard isContained(resolvedCandidate, by: root) else {
            throw GoldenFixtureContractError.invalidFixturePath(rawPath)
        }
        return components.map(String.init).joined(separator: "/")
    }

    private static func isContained(_ candidate: URL, by root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(rootPath)
    }

    private static func fixtureData(
        at path: String,
        fixtureDirectory: URL,
        fileManager: FileManager
    ) throws -> Data {
        let url = fixtureDirectory.appendingPathComponent(path, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else {
            throw GoldenFixtureContractError.missingFixture(path)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw GoldenFixtureContractError.unreadableFixture(path)
        }
    }

    private static func fixtureFiles(
        under fixtureDirectory: URL,
        fileManager: FileManager
    ) throws -> Set<String> {
        let root = fixtureDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            throw GoldenFixtureContractError.fixtureDirectoryMissing(root.path)
        }

        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var files = Set<String>()
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            guard fileURL.path.hasPrefix(rootPrefix) else {
                throw GoldenFixtureContractError.invalidFixturePath(fileURL.path)
            }
            let relativePath = String(fileURL.path.dropFirst(rootPrefix.count))
                .replacingOccurrences(of: "\\", with: "/")
            if !relativePath.contains("/") {
                guard allowedRootFiles.contains(relativePath) else {
                    throw GoldenFixtureContractError.unexpectedRootFile(relativePath)
                }
                continue
            }
            files.insert(relativePath)
        }
        return files
    }

    private static func validateJSONValue(
        _ value: Any,
        rejectExpectedOnlyKeys: Bool
    ) throws {
        if let object = value as? [String: Any] {
            for (key, child) in object {
                let normalizedKey = normalizedToken(key)
                if forbiddenKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    throw GoldenFixtureContractError.forbiddenFixtureKey(key)
                }
                if rejectExpectedOnlyKeys, expectedOnlyKeys.contains(key.lowercased()) {
                    throw GoldenFixtureContractError.expectedValueInInput(key)
                }
                try validateJSONValue(child, rejectExpectedOnlyKeys: rejectExpectedOnlyKeys)
            }
        } else if let array = value as? [Any] {
            for child in array {
                try validateJSONValue(child, rejectExpectedOnlyKeys: rejectExpectedOnlyKeys)
            }
        } else if let string = value as? String {
            let normalized = normalizedToken(string)
            if !allowedValueTokens.contains(normalized),
               normalized.contains("authorizationbearer") || normalized.contains("setcookie") {
                throw GoldenFixtureContractError.forbiddenFixtureValue(string)
            }
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    private static func fixtureVersion(from directoryName: String) -> Int? {
        guard directoryName.first == "v",
              let version = Int(directoryName.dropFirst()),
              version > 0,
              directoryName == "v\(version)" else {
            return nil
        }
        return version
    }
}
