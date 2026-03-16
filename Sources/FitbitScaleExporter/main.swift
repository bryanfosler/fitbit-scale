import FitbitScaleCore
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct FitbitScaleExporter {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data((render(error) + "\n").utf8))
            exit(1)
        }
    }

    private static func run() async throws {
        let parser = try CLIParser(arguments: Array(CommandLine.arguments.dropFirst()))
        let command = try parser.command()

        switch command {
        case "help":
            print(Self.helpText)
        case "auth-url":
            try runAuthURL(parser: parser)
        case "exchange-code":
            try await runExchangeCode(parser: parser)
        case "export":
            try await runExport(parser: parser)
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func runAuthURL(parser: CLIParser) throws {
        let clientID = try parser.string(named: "client-id", env: "FITBIT_CLIENT_ID")
        let clientSecret = parser.optionalString(named: "client-secret", env: "FITBIT_CLIENT_SECRET")
        let redirectURI = try parser.url(
            named: "redirect-uri",
            default: FitbitOAuthConfiguration.defaultRedirectURI.absoluteString
        )
        let scopes = parser.optionalString(named: "scopes")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? ["weight", "profile"]
        let usePKCE = parser.flag(named: "pkce")
        let state = parser.optionalString(named: "state") ?? UUID().uuidString
        let pkce = usePKCE ? PKCEChallenge.generate() : nil

        let configuration = FitbitOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes
        )
        let url = try configuration.authorizationURL(
            state: state,
            codeChallenge: pkce?.challenge
        )

        print("Open this URL in a browser:")
        print(url.absoluteString)
        print("")
        print("State:")
        print(state)

        if let pkce {
            print("")
            print("PKCE verifier:")
            print(pkce.verifier)
            print("")
            print("Use that verifier with the `exchange-code` command.")
        }
    }

    private static func runExchangeCode(parser: CLIParser) async throws {
        let clientID = try parser.string(named: "client-id", env: "FITBIT_CLIENT_ID")
        let clientSecret = parser.optionalString(named: "client-secret", env: "FITBIT_CLIENT_SECRET")
        let redirectURI = try parser.url(
            named: "redirect-uri",
            default: FitbitOAuthConfiguration.defaultRedirectURI.absoluteString
        )
        let code = try parser.string(named: "code")
        let codeVerifier = parser.optionalString(named: "code-verifier")
        let tokenFile = try parser.path(named: "token-file")

        let configuration = FitbitOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )
        let apiClient = FitbitAPIClient()
        let token = try await apiClient.exchangeCode(
            code,
            codeVerifier: codeVerifier,
            configuration: configuration
        )

        try TokenFileStore(path: tokenFile).save(token)
        print("Saved Fitbit token to \(tokenFile.path)")
    }

    private static func runExport(parser: CLIParser) async throws {
        let clientID = try parser.string(named: "client-id", env: "FITBIT_CLIENT_ID")
        let clientSecret = parser.optionalString(named: "client-secret", env: "FITBIT_CLIENT_SECRET")
        let redirectURI = try parser.url(
            named: "redirect-uri",
            default: FitbitOAuthConfiguration.defaultRedirectURI.absoluteString
        )
        let tokenFilePath = try parser.path(named: "token-file")
        let outputPath = try parser.path(named: "output")
        let days = try parser.int(named: "days", default: 14)
        let unit = try parser.massUnit(named: "weight-unit", default: .pounds)
        let latestOnly = parser.flag(named: "latest-only")

        let tokenStore = TokenFileStore(path: tokenFilePath)
        var token: FitbitToken

        if FileManager.default.fileExists(atPath: tokenFilePath.path) {
            token = try tokenStore.load()
        } else if let refreshToken = parser.optionalString(named: "refresh-token", env: "FITBIT_REFRESH_TOKEN"),
                  !refreshToken.isEmpty {
            token = FitbitToken(
                accessToken: "",
                refreshToken: refreshToken,
                scope: "",
                tokenType: "Bearer",
                userID: nil,
                expiresAt: .distantPast
            )
        } else {
            throw CLIError.validation("No token file was found at \(tokenFilePath.path). Provide --refresh-token for the first run or bootstrap one with `exchange-code`.")
        }

        let configuration = FitbitOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )
        let apiClient = FitbitAPIClient()
        token = try await apiClient.refreshToken(token, configuration: configuration)
        try tokenStore.save(token)

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -(max(days, 1) - 1), to: endDate) else {
            throw CLIError.validation("Could not compute a start date from --days.")
        }

        var weights = try await apiClient.fetchWeights(
            startDate: startDate,
            endDate: endDate,
            token: token,
            unit: unit
        )

        if latestOnly, let latest = weights.last {
            weights = [latest]
        }

        let payload = ExportPayload(
            generatedAt: endDate,
            unit: unit,
            weights: weights.map(ExportWeight.init)
        )
        try ExportWriter(path: outputPath).write(payload)

        print("Exported \(weights.count) Fitbit weight entr\(weights.count == 1 ? "y" : "ies") to \(outputPath.path)")
    }

    private static func render(_ error: Error) -> String {
        if let cliError = error as? CLIError {
            return cliError.localizedDescription
        }

        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }

    private static let helpText = """
    Commands:
      auth-url
        Print a Fitbit authorization URL. Use --pkce to generate a PKCE verifier/challenge pair.

      exchange-code --client-id <id> --code <code> --token-file <path> [--client-secret <secret>] [--redirect-uri <uri>] [--code-verifier <verifier>]
        Exchange a Fitbit authorization code for access and refresh tokens, then save them to a token file.

      export --client-id <id> --token-file <path> --output <path> [--refresh-token <token>] [--client-secret <secret>] [--redirect-uri <uri>] [--days <n>] [--weight-unit pounds|kilograms|stones] [--latest-only]
        Refresh the Fitbit token, fetch recent weight logs, and write JSON output for Shortcut ingestion.

    Environment variables:
      FITBIT_CLIENT_ID
      FITBIT_CLIENT_SECRET
      FITBIT_REFRESH_TOKEN
    """
}

private struct ExportPayload: Encodable {
    let generatedAt: Date
    let unit: MassUnit
    let weights: [ExportWeight]
}

private struct ExportWeight: Encodable {
    let logID: String
    let timestamp: Date
    let value: Double
    let kilograms: Double
    let source: String?

    init(measurement: FitbitWeightMeasurement) {
        logID = measurement.logID
        timestamp = measurement.timestamp
        value = measurement.value
        kilograms = measurement.kilograms
        source = measurement.source
    }
}

private struct ExportWriter {
    let path: URL

    func write(_ payload: ExportPayload) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)

        if path.path == "/dev/stdout" {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: path, options: .atomic)
    }
}

private struct TokenFileStore {
    let path: URL

    func load() throws -> FitbitToken {
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FitbitToken.self, from: data)
    }

    func save(_ token: FitbitToken) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(token)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: path, options: .atomic)
    }
}

private struct CLIParser {
    private let commandName: String?
    private let options: [String: String]
    private let flags: Set<String>

    init(arguments: [String]) throws {
        var commandName: String?
        var options: [String: String] = [:]
        var flags: Set<String> = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            if !argument.hasPrefix("--"), commandName == nil {
                commandName = argument
                index += 1
                continue
            }

            guard argument.hasPrefix("--") else {
                throw CLIError.validation("Unexpected argument: \(argument)")
            }

            let name = String(argument.dropFirst(2))

            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                options[name] = arguments[index + 1]
                index += 2
            } else {
                flags.insert(name)
                index += 1
            }
        }

        self.commandName = commandName
        self.options = options
        self.flags = flags
    }

    func command() throws -> String {
        commandName ?? "help"
    }

    func flag(named name: String) -> Bool {
        flags.contains(name)
    }

    func optionalString(named name: String, env: String? = nil) -> String? {
        if let value = options[name] {
            return value
        }

        if let env, let value = ProcessInfo.processInfo.environment[env], !value.isEmpty {
            return value
        }

        return nil
    }

    func string(named name: String, env: String? = nil) throws -> String {
        guard let value = optionalString(named: name, env: env), !value.isEmpty else {
            throw CLIError.missingOption(name)
        }

        return value
    }

    func int(named name: String, default defaultValue: Int) throws -> Int {
        guard let value = optionalString(named: name) else {
            return defaultValue
        }

        guard let parsed = Int(value) else {
            throw CLIError.validation("Option --\(name) must be an integer.")
        }

        return parsed
    }

    func url(named name: String, default defaultValue: String) throws -> URL {
        let value = optionalString(named: name) ?? defaultValue

        guard let url = URL(string: value) else {
            throw CLIError.validation("Option --\(name) must be a valid URL.")
        }

        return url
    }

    func path(named name: String) throws -> URL {
        let rawPath = try string(named: name)
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }

    func massUnit(named name: String, default defaultValue: MassUnit) throws -> MassUnit {
        guard let rawValue = optionalString(named: name) else {
            return defaultValue
        }

        guard let unit = MassUnit(rawValue: rawValue) else {
            throw CLIError.validation("Option --\(name) must be one of: \(MassUnit.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        return unit
    }
}

private enum CLIError: LocalizedError {
    case missingOption(String)
    case unknownCommand(String)
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .missingOption(let name):
            return "Missing required option --\(name). Run `swift run fitbit-scale-exporter help` for usage."
        case .unknownCommand(let command):
            return "Unknown command `\(command)`. Run `swift run fitbit-scale-exporter help` for usage."
        case .validation(let message):
            return message
        }
    }
}
