import Foundation
import LocalQueueServerRunner
import Logging
import Models
import ResourceLocationResolver

final class ArgumentsReader {
    private init() {}
    
    private static let decoderWithSnakeCaseSupport: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private static let strictDecoder = JSONDecoder()
    
    public static func environment(_ file: String?, key: ArgumentDescription) throws -> [String: String] {
        return try decodeModelsFromFile(file, defaultValueIfFileIsMissing: [:], key: key, jsonDecoder: strictDecoder)
    }
    
    public static func testArgFile(_ file: String?, key: ArgumentDescription) throws -> TestArgFile {
        return try decodeModelsFromFile(file, key: key, jsonDecoder: strictDecoder)
    }
    
    public static func testDestinations(_ file: String?, key: ArgumentDescription) throws -> [TestDestinationConfiguration] {
        return try decodeModelsFromFile(file, key: key, jsonDecoder: decoderWithSnakeCaseSupport)
    }
    
    public static func deploymentDestinations(_ file: String?, key: ArgumentDescription) throws -> [DeploymentDestination] {
        return try decodeModelsFromFile(file, key: key, jsonDecoder: decoderWithSnakeCaseSupport)
    }
    
    public static func simulatorSettings(
        localizationFile: String?,
        localizationKey: ArgumentDescription,
        watchdogFile: String?,
        watchdogKey: ArgumentDescription
    ) throws -> SimulatorSettings {
        return SimulatorSettings(
            simulatorLocalizationSettings: SimulatorLocalizationLocation(try validateResourceLocationOrNil(localizationFile, key: localizationKey)),
            watchdogSettings: WatchdogSettingsLocation(try validateResourceLocationOrNil(watchdogFile, key: watchdogKey))
        )
    }
    
    public static func queueServerRunConfiguration(
        _ value: String?,
        key: ArgumentDescription,
        resourceLocationResolver: ResourceLocationResolver
    ) throws -> QueueServerRunConfiguration {
        let location = try ArgumentsReader.validateResourceLocation(value, key: key)
        let resolvingResult = try resourceLocationResolver.resolvePath(resourceLocation: location)
        return try decodeModelsFromFile(
            try resolvingResult.directlyAccessibleResourcePath(),
            key: key,
            jsonDecoder: decoderWithSnakeCaseSupport
        )
    }
    
    private static func decodeModelsFromFile<T>(
        _ file: String?,
        defaultValueIfFileIsMissing: T? = nil,
        key: ArgumentDescription,
        jsonDecoder: JSONDecoder
    ) throws -> T where T: Decodable {
        if file == nil, let defaultValue = defaultValueIfFileIsMissing {
            return defaultValue
        }
        let path = try validateFileExists(file, key: key)
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            Logger.error("Unable to read or decode file '\(path)': \(error)")
            throw ArgumentsError.argumentValueCannotBeUsed(key, error)
        }
    }
    
    public static func socketAddress(_ value: String?, key: ArgumentDescription) throws -> SocketAddress {
        let stringValue = try validateNotNil(value, key: key)
        return try SocketAddress.from(string: stringValue)
    }
    
    public static func validateNotNil<T>(_ value: T?, key: ArgumentDescription) throws -> T {
        guard let value = value else { throw ArgumentsError.argumentIsMissing(key) }
        return value
    }
    
    public static func validateResourceLocation(_ value: String?, key: ArgumentDescription) throws -> ResourceLocation {
        let string = try validateNotNil(value, key: key)
        return try ResourceLocation.from(string)
    }
    
    public static func validateResourceLocationOrNil(_ value: String?, key: ArgumentDescription) throws -> ResourceLocation? {
        guard let string = value else { return nil }
        return try ResourceLocation.from(string)
    }
    
    public static func validateResourceLocations(_ values: [String], key: ArgumentDescription) throws -> [ResourceLocation] {
        return try values.map { value in
            let string = try validateNotNil(value, key: key)
            return try ResourceLocation.from(string)
        }
    }
    
    public static func validateFileExists(_ value: String?, key: ArgumentDescription) throws -> String {
        let path = try validateNotNil(value, key: key)
        if !FileManager.default.fileExists(atPath: path) {
            throw ArgumentsError.argumentValueCannotBeUsed(key, AdditionalArgumentValidationError.notFound(path))
        }
        return path
    }
}