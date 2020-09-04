import BuildArtifacts
import DI
import DeveloperDirModels
import Foundation
import DateProvider
import DeveloperDirLocator
import Logging
import PluginSupport
import RunnerModels
import LocalHostDeterminer
import Runner
import SimulatorPoolModels
import WorkerCapabilitiesModels
//import QueueClient
import QueueModels
import SimulatorPool
import PluginManager
import ResourceLocationResolver
import TemporaryStuff
import Types
import FileSystem

// MARK: - Run Tests

public final class RunTestsBucketPayload: BucketPayload {
    public let buildArtifacts: BuildArtifacts
    public let developerDir: DeveloperDir
    public let pluginLocations: Set<PluginLocation>
    public let simulatorControlTool: SimulatorControlTool
    public let simulatorOperationTimeouts: SimulatorOperationTimeouts
    public let simulatorSettings: SimulatorSettings
    public let testDestination: TestDestination
    public let testEntries: [TestEntry]
    public let testExecutionBehavior: TestExecutionBehavior
    public let testRunnerTool: TestRunnerTool
    public let testTimeoutConfiguration: TestTimeoutConfiguration
    public let testType: TestType
    
    public var bucketId: BucketId { "TODO remove this" }
    
    public init(
        buildArtifacts: BuildArtifacts,
        developerDir: DeveloperDir,
        pluginLocations: Set<PluginLocation>,
        simulatorControlTool: SimulatorControlTool,
        simulatorOperationTimeouts: SimulatorOperationTimeouts,
        simulatorSettings: SimulatorSettings,
        testDestination: TestDestination,
        testEntries: [TestEntry],
        testExecutionBehavior: TestExecutionBehavior,
        testRunnerTool: TestRunnerTool,
        testTimeoutConfiguration: TestTimeoutConfiguration,
        testType: TestType
    ) {
        self.buildArtifacts = buildArtifacts
        self.developerDir = developerDir
        self.pluginLocations = pluginLocations
        self.simulatorControlTool = simulatorControlTool
        self.simulatorOperationTimeouts = simulatorOperationTimeouts
        self.simulatorSettings = simulatorSettings
        self.testDestination = testDestination
        self.testEntries = testEntries
        self.testExecutionBehavior = testExecutionBehavior
        self.testRunnerTool = testRunnerTool
        self.testTimeoutConfiguration = testTimeoutConfiguration
        self.testType = testType
    }
    
    public func createBucketProcessor(di: DI) throws -> BucketProcessor {
        return try RunTestsBucketProcessor(di: di, payload: self)
    }
}

public final class RunTestsBucketProcessor: BucketProcessor {
    private let di: DI
    private let payload: RunTestsBucketPayload
    
    private let callbackQueue = DispatchQueue(label: "DistWorker.callbackQueue", qos: .default)
    
    public init(
        di: DI,
        payload: RunTestsBucketPayload
    ) throws {
        self.di = di
        self.payload = payload
    }
    
    public func execute(
        completion: @escaping (Result<BucketResult, Error>) -> ()
    ) {
        let testingResult = execute()
        didReceiveTestResult(
            testingResult: testingResult,
            completion: completion
        )
    }
    
    
    private func execute() -> TestingResult {
        let startedAt = Date()
        do {
            return try runRetrying()
        } catch {
            Logger.error("Failed to execute bucket \(payload.bucketId): \(error)")
            return TestingResult(
                testDestination: payload.testDestination,
                unfilteredResults: payload.testEntries.map { testEntry -> TestEntryResult in
                    TestEntryResult.withResult(
                        testEntry: testEntry,
                        testRunResult: TestRunResult(
                            succeeded: false,
                            exceptions: [
                                TestException(
                                    reason: "Emcee failed to execute this test: \(error)",
                                    filePathInProject: #file,
                                    lineNumber: #line
                                )
                            ],
                            duration: Date().timeIntervalSince(startedAt),
                            startTime: startedAt.timeIntervalSince1970,
                            hostName: LocalHostDeterminer.currentHostAddress,
                            simulatorId: UDID(value: "undefined")
                        )
                    )
                }
            )
        }
    }
    
    /**
     Runs tests in a given Bucket, retrying failed tests multiple times if necessary.
     */
    private func runRetrying() throws -> TestingResult {
        let firstRun = try runBucketOnce(testsToRun: payload.testEntries)
        
        guard payload.testExecutionBehavior.numberOfRetries > 0 else {
            Logger.debug("numberOfRetries == 0, will not retry failed tests.")
            return firstRun
        }
        
        var lastRunResults = firstRun
        var results = [firstRun]
        for retryNumber in 0 ..< payload.testExecutionBehavior.numberOfRetries {
            let failedTestEntriesAfterLastRun = lastRunResults.failedTests.map { $0.testEntry }
            if failedTestEntriesAfterLastRun.isEmpty {
                Logger.debug("No failed tests after last retry, so nothing to run.")
                break
            }
            Logger.debug("After last run \(failedTestEntriesAfterLastRun.count) tests have failed: \(failedTestEntriesAfterLastRun).")
            Logger.debug("Retrying them, attempt #\(retryNumber + 1) of maximum \(payload.testExecutionBehavior.numberOfRetries) attempts")
            lastRunResults = try runBucketOnce(testsToRun: failedTestEntriesAfterLastRun)
            results.append(lastRunResults)
        }
        return try combine(runResults: results)
    }
    
    private func runBucketOnce(testsToRun: [TestEntry]) throws -> TestingResult {
        let simulatorPool = try di.get(OnDemandSimulatorPool.self).pool(
            key: OnDemandSimulatorPoolKey(
                developerDir: payload.developerDir,
                testDestination: payload.testDestination,
                simulatorControlTool: payload.simulatorControlTool
            )
        )

        let allocatedSimulator = try simulatorPool.allocateSimulator(
            dateProvider: try di.get(),
            simulatorOperationTimeouts: payload.simulatorOperationTimeouts,
            version: try di.get()
        )
        defer { allocatedSimulator.releaseSimulator() }
        
        try di.get(SimulatorSettingsModifier.self).apply(
            developerDir: payload.developerDir,
            simulatorSettings: payload.simulatorSettings,
            toSimulator: allocatedSimulator.simulator
        )
        
        let runner = Runner(
            configuration: RunnerConfiguration(
                buildArtifacts: payload.buildArtifacts,
                environment: payload.testExecutionBehavior.environment,
                pluginLocations: payload.pluginLocations,
                simulatorSettings: payload.simulatorSettings,
                testRunnerTool: payload.testRunnerTool,
                testTimeoutConfiguration: payload.testTimeoutConfiguration,
                testType: payload.testType
            ),
            dateProvider: try di.get(),
            developerDirLocator: try di.get(),
            fileSystem: try di.get(),
            pluginEventBusProvider: try di.get(),
            resourceLocationResolver: try di.get(),
            tempFolder: try di.get(),
            testRunnerProvider: try di.get(),
            version: try di.get()
        )

        let runnerResult = try runner.run(
            entries: testsToRun,
            developerDir: payload.developerDir,
            simulator: allocatedSimulator.simulator
        )
        
        if !runnerResult.testEntryResults.filter({ $0.isLost }).isEmpty {
            Logger.warning("Some test results are lost")
            runnerResult.dumpStandardStreams()
        }
        
        return TestingResult(
            testDestination: payload.testDestination,
            unfilteredResults: runnerResult.testEntryResults
        )
    }
    
    // MARK: - Utility Methods
    
    /**
     Combines several TestingResult objects of the same Bucket, after running and retrying tests,
     so if some tests become green, the resulting combined object will have it in a green state.
     */
    private func combine(runResults: [TestingResult]) throws -> TestingResult {
        // All successful tests should be merged into a single array.
        // Last run's `failedTests` contains all tests that failed after all attempts to rerun failed tests.
        Logger.verboseDebug("Combining the following results from \(runResults.count) runs:")
        runResults.forEach {
            Logger.verboseDebug("Result: \($0)")
        }
        let result = try TestingResult.byMerging(testingResults: runResults)
        Logger.verboseDebug("Combined result: \(result)")
        return result
    }
    
    private func didReceiveTestResult(
        testingResult: TestingResult,
        completion: @escaping (Result<BucketResult, Error>) -> ()
    ) {
//        do {
//            try di.get(BucketResultSender.self).send(
//                bucketId: payload.bucketId,
//                testingResult: testingResult,
//                workerId: try self.di.get(WorkerId.self),
//                payloadSignature: try self.di.get(PayloadSignature.self),
//                callbackQueue: self.callbackQueue,
//                completion: { [payload] (result: Either<BucketId, Error>) in
//                    do {
//                        _ = try result.dematerialize()
//                        completion(nil)
//                        Logger.debug("Successfully sent test run result for bucket \(payload.bucketId)")
//                    } catch {
//                        Logger.error("Server response for results of bucket \(payload.bucketId) has error: \(error)")
//                        completion(error)
//                    }
//                }
//            )
//        } catch {
//            Logger.error("Failed to send test run result for bucket \(payload.bucketId): \(error)")
//            completion(error)
//        }
    }
}

public enum RunTestsBucketProcessorError: Error, CustomStringConvertible {
    case noRequestIdForBucketId(BucketId)
    case unexpectedAcceptedBucketId(actual: BucketId, expected: BucketId)
    case missingPayloadSignature
    
    public var description: String {
        switch self {
        case .noRequestIdForBucketId(let bucketId):
            return "No matching requestId found for bucket id: \(bucketId)."
        case .unexpectedAcceptedBucketId(let actual, let expected):
            return "Server said it accepted bucket with id '\(actual)', but testing result had bucket id '\(expected)'"
        case .missingPayloadSignature:
            return "Payload signature has not been obtained yet but is already required"
        }
    }
}
