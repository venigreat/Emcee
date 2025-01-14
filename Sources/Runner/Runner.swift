import AtomicModels
import DateProvider
import DeveloperDirLocator
import DeveloperDirModels
import EventBus
import FileSystem
import Foundation
import LocalHostDeterminer
import EmceeLogging
import Metrics
import MetricsExtensions
import PathLib
import PluginManager
import ProcessController
import QueueModels
import ResourceLocationResolver
import RunnerModels
import SimulatorPoolModels
import SynchronousWaiter
import Tmp
import TestsWorkingDirectorySupport

public final class Runner {
    private let configuration: RunnerConfiguration
    private let dateProvider: DateProvider
    private let developerDirLocator: DeveloperDirLocator
    private let fileSystem: FileSystem
    private let logger: ContextualLogger
    private let persistentMetricsJobId: String?
    private let pluginEventBusProvider: PluginEventBusProvider
    private let pluginTearDownQueue = OperationQueue()
    private let resourceLocationResolver: ResourceLocationResolver
    private let specificMetricRecorder: SpecificMetricRecorder
    private let tempFolder: TemporaryFolder
    private let testRunnerProvider: TestRunnerProvider
    private let testTimeoutCheckInterval: DispatchTimeInterval
    private let version: Version
    private let waiter: Waiter
    
    public init(
        configuration: RunnerConfiguration,
        dateProvider: DateProvider,
        developerDirLocator: DeveloperDirLocator,
        fileSystem: FileSystem,
        logger: ContextualLogger,
        persistentMetricsJobId: String?,
        pluginEventBusProvider: PluginEventBusProvider,
        resourceLocationResolver: ResourceLocationResolver,
        specificMetricRecorder: SpecificMetricRecorder,
        tempFolder: TemporaryFolder,
        testRunnerProvider: TestRunnerProvider,
        testTimeoutCheckInterval: DispatchTimeInterval = .seconds(1),
        version: Version,
        waiter: Waiter
    ) {
        self.configuration = configuration
        self.dateProvider = dateProvider
        self.developerDirLocator = developerDirLocator
        self.fileSystem = fileSystem
        self.logger = logger
        self.persistentMetricsJobId = persistentMetricsJobId
        self.pluginEventBusProvider = pluginEventBusProvider
        self.resourceLocationResolver = resourceLocationResolver
        self.specificMetricRecorder = specificMetricRecorder
        self.tempFolder = tempFolder
        self.testRunnerProvider = testRunnerProvider
        self.testTimeoutCheckInterval = testTimeoutCheckInterval
        self.version = version
        self.waiter = waiter
    }
    
    /** Runs the given tests, attempting to restart the runner in case of crash. */
    public func run(
        entries: [TestEntry],
        developerDir: DeveloperDir,
        simulator: Simulator
    ) throws -> RunnerRunResult {
        if entries.isEmpty {
            return RunnerRunResult(
                entriesToRun: entries,
                testEntryResults: []
            )
        }
        
        let runResult = RunResult()
        
        // To not retry forever.
        // It is unlikely that multiple revives would provide any results, so we leave only a single retry.
        let numberOfAttemptsToRevive = 1
        
        // Something may crash (xcodebuild/xctest), many tests may be not started. Some external code that uses Runner
        // may have its own logic for restarting particular tests, but here at Runner we deal with crashes of bunches
        // of tests, many of which can be even not started. Simplifying this: if something that runs tests is crashed,
        // we should retry running tests more than if some test fails. External code will treat failed tests as it
        // is promblem in them, not in infrastructure.
        
        var reviveAttempt = 0

        while runResult.nonLostTestEntryResults.count < entries.count, reviveAttempt <= numberOfAttemptsToRevive {
            let entriesToRun = missingEntriesForScheduledEntries(
                expectedEntriesToRun: entries,
                collectedResults: runResult
            )
            let runResults = try runOnce(
                entriesToRun: entriesToRun,
                developerDir: developerDir,
                simulator: simulator
            )
            
            runResult.append(testEntryResults: runResults.testEntryResults)
            
            if runResults.testEntryResults.filter({ !$0.isLost }).isEmpty {
                // Here, if we do not receive events at all, we will get 0 results. We try to revive a limited number of times.
                reviveAttempt += 1
                logger.warning("Got no results. Attempting to revive #\(reviveAttempt) out of allowed \(numberOfAttemptsToRevive) attempts to revive")
            } else {
                // Here, we actually got events, so we could reset revive attempts.
                reviveAttempt = 0
            }
        }
        
        return RunnerRunResult(
            entriesToRun: entries,
            testEntryResults: testEntryResults(
                runResult: runResult,
                simulatorId: simulator.udid
            )
        )
    }
    
    /// Runs the given tests once without any attempts to restart the failed or crashed tests.
    public func runOnce(
        entriesToRun: [TestEntry],
        developerDir: DeveloperDir,
        simulator: Simulator
    ) throws -> RunnerRunResult {
        if entriesToRun.isEmpty {
            return RunnerRunResult(
                entriesToRun: entriesToRun,
                testEntryResults: []
            )
        }

        var collectedTestStoppedEvents = [TestStoppedEvent]()
        var collectedTestExceptions = [TestException]()
        
        let testContext = try createTestContext(
            developerDir: developerDir,
            simulator: simulator
        )
        
        let eventBus = try pluginEventBusProvider.createEventBus(
            fileSystem: fileSystem,
            pluginLocations: configuration.pluginLocations
        )
        defer {
            pluginTearDownQueue.addOperation(eventBus.tearDown)
        }
        
        var logger = self.logger
        logger.debug("Will run \(entriesToRun.count) tests on simulator \(simulator)")
        
        let singleTestMaximumDuration = configuration.testTimeoutConfiguration.singleTestMaximumDuration
        
        let testRunner = try testRunnerProvider.testRunner(
            testRunnerTool: configuration.testRunnerTool
        )
        
        let testRunnerRunningInvocationContainer = AtomicValue<TestRunnerRunningInvocation?>(nil)
        let streamClosedCallback: CallbackWaiter<()> = waiter.createCallbackWaiter()
        
        let testRunnerStream = CompositeTestRunnerStream(
            testRunnerStreams: [
                EventBusReportingTestRunnerStream(
                    entriesToRun: entriesToRun,
                    eventBus: eventBus,
                    logger: { logger },
                    testContext: testContext,
                    resultsProvider: {
                        Runner.prepareResults(
                            collectedTestStoppedEvents: collectedTestStoppedEvents,
                            requestedEntriesToRun: entriesToRun,
                            simulatorId: simulator.udid
                        )
                    }
                ),
                TestTimeoutTrackingTestRunnerSream(
                    dateProvider: dateProvider,
                    detectedLongRunningTest: { [dateProvider] testName, testStartedAt in
                        logger.debug("Detected long running test \(testName)")
                        collectedTestStoppedEvents.append(
                            TestStoppedEvent(
                                testName: testName,
                                result: .failure,
                                testDuration: dateProvider.currentDate().timeIntervalSince(testStartedAt),
                                testExceptions: [
                                    RunnerConstants.testTimeout(singleTestMaximumDuration).testException
                                ],
                                testStartTimestamp: testStartedAt.timeIntervalSince1970
                            )
                        )
                        
                        testRunnerRunningInvocationContainer.currentValue()?.cancel()
                    },
                    logger: { logger },
                    maximumTestDuration: singleTestMaximumDuration,
                    pollPeriod: testTimeoutCheckInterval
                ),
                MetricReportingTestRunnerStream(
                    dateProvider: dateProvider,
                    version: version,
                    host: LocalHostDeterminer.currentHostAddress,
                    persistentMetricsJobId: persistentMetricsJobId,
                    specificMetricRecorder: specificMetricRecorder
                ),
                TestRunnerStreamWrapper(
                    onOpenStream: {
                        logger.debug("Started executing tests")
                    },
                    onTestStarted: { testName in
                        collectedTestExceptions = []
                        logger.debug("Test started: \(testName)")
                    },
                    onTestException: { testException in
                        collectedTestExceptions.append(testException)
                        logger.debug("Caught test exception: \(testException)")
                    },
                    onTestStopped: { testStoppedEvent in
                        let testStoppedEvent = testStoppedEvent.byMergingTestExceptions(testExceptions: collectedTestExceptions)
                        collectedTestStoppedEvents.append(testStoppedEvent)
                        collectedTestExceptions = []
                        logger.debug("Test stopped: \(testStoppedEvent.testName), \(testStoppedEvent.result)")
                    },
                    onCloseStream: {
                        logger.debug("Finished executing tests")
                        streamClosedCallback.set(result: ())
                    }
                ),
                PreflightPostflightTimeoutTrackingTestRunnerStream(
                    dateProvider: dateProvider,
                    onPreflightTimeout: {
                        logger.debug("Detected preflight timeout")
                        testRunnerRunningInvocationContainer.currentValue()?.cancel()
                    },
                    onPostflightTimeout: { testName in
                        logger.debug("Detected postflight timeout, last finished test was \(testName)")
                        testRunnerRunningInvocationContainer.currentValue()?.cancel()
                    },
                    maximumPreflightDuration: configuration.testTimeoutConfiguration.testRunnerMaximumSilenceDuration,
                    maximumPostflightDuration: configuration.testTimeoutConfiguration.testRunnerMaximumSilenceDuration,
                    pollPeriod: testTimeoutCheckInterval
                )
            ]
        )
        
        let runningInvocation: TestRunnerRunningInvocation
        do {
            runningInvocation = try runTestsViaTestRunner(
                testRunner: testRunner,
                entriesToRun: entriesToRun,
                logger: logger,
                simulator: simulator,
                testContext: testContext,
                testRunnerStream: testRunnerStream
            ).startExecutingTests()
        } catch {
            runningInvocation = try generateTestFailuresBecauseOfRunnerFailure(
                runnerError: error,
                entriesToRun: entriesToRun,
                testRunnerStream: testRunnerStream
            ).startExecutingTests()
        }
        logger = logger
            .withMetadata(key: .subprocessId, value: "\(runningInvocation.pidInfo.pid)")
            .withMetadata(key: .subprocessName, value: "\(runningInvocation.pidInfo.name)")
        testRunnerRunningInvocationContainer.set(runningInvocation)
        defer {
            // since we refer this in closures, we must clean up to ensure no retain cycles will occur
            testRunnerRunningInvocationContainer.set(nil)
        }
        try streamClosedCallback.wait(timeout: .infinity, description: "Test Runner Stream Close")
        
        let result = Runner.prepareResults(
            collectedTestStoppedEvents: collectedTestStoppedEvents,
            requestedEntriesToRun: entriesToRun,
            simulatorId: simulator.udid
        )
        
        logger.debug("Attempted to run \(entriesToRun.count) tests on simulator \(simulator): \(entriesToRun)")
        logger.debug("Did get \(result.count) results: \(result)")
        
        return RunnerRunResult(
            entriesToRun: entriesToRun,
            testEntryResults: result
        )
    }
    
    private func createTestContext(
        developerDir: DeveloperDir,
        simulator: Simulator
    ) throws -> TestContext {
        let contextUuid = UUID()
        let testsWorkingDirectory = try tempFolder.pathByCreatingDirectories(
            components: ["testsWorkingDir", contextUuid.uuidString]
        )

        var environment = configuration.environment
        environment[TestsWorkingDirectorySupport.envTestsWorkingDirectory] = testsWorkingDirectory.pathString
        environment = try developerDirLocator.suitableEnvironment(forDeveloperDir: developerDir, byUpdatingEnvironment: environment)

        return TestContext(
            contextUuid: contextUuid,
            developerDir: developerDir,
            environment: environment,
            simulatorPath: simulator.path.fileUrl,
            simulatorUdid: simulator.udid,
            testDestination: simulator.testDestination
        )
    }
    
    private func runTestsViaTestRunner(
        testRunner: TestRunner,
        entriesToRun: [TestEntry],
        logger: ContextualLogger,
        simulator: Simulator,
        testContext: TestContext,
        testRunnerStream: TestRunnerStream
    ) throws -> TestRunnerInvocation {
        cleanUpDeadCache(
            logger: logger,
            simulator: simulator
        )
        return try testRunner.prepareTestRun(
            buildArtifacts: configuration.buildArtifacts,
            developerDirLocator: developerDirLocator,
            entriesToRun: entriesToRun,
            logger: logger,
            simulator: simulator,
            temporaryFolder: tempFolder,
            testContext: testContext,
            testRunnerStream: testRunnerStream,
            testType: configuration.testType
        )
    }
    
    private func cleanUpDeadCache(
        logger: ContextualLogger,
        simulator: Simulator
    ) {
        let deadCachePath = simulator.path.appending(relativePath: RelativePath("data/Library/Caches/com.apple.containermanagerd/Dead"))
        do {
            if fileSystem.properties(forFileAtPath: deadCachePath).exists() {
                logger.debug("Will attempt to clean up simulator dead cache at: \(deadCachePath)")
                try fileSystem.delete(fileAtPath: deadCachePath)
            }
        } catch {
            logger.warning("Failed to delete dead cache at \(deadCachePath): \(error)")
        }
    }
    
    private func generateTestFailuresBecauseOfRunnerFailure(
        runnerError: Error,
        entriesToRun: [TestEntry],
        testRunnerStream: TestRunnerStream
    ) -> TestRunnerInvocation {
        testRunnerStream.openStream()
        for testEntry in entriesToRun {
            testRunnerStream.testStarted(testName: testEntry.testName)
            testRunnerStream.testStopped(
                testStoppedEvent: TestStoppedEvent(
                    testName: testEntry.testName,
                    result: .lost,
                    testDuration: 0,
                    testExceptions: [
                        RunnerConstants.failedToStartTestRunner(runnerError).testException
                    ],
                    testStartTimestamp: dateProvider.currentDate().timeIntervalSince1970
                )
            )
        }
        testRunnerStream.closeStream()
        return NoOpTestRunnerInvocation()
    }
    
    private static func prepareResults(
        collectedTestStoppedEvents: [TestStoppedEvent],
        requestedEntriesToRun: [TestEntry],
        simulatorId: UDID
    ) -> [TestEntryResult] {
        return requestedEntriesToRun.map { requestedEntryToRun in
            prepareResult(
                requestedEntryToRun: requestedEntryToRun,
                simulatorId: simulatorId,
                collectedTestStoppedEvents: collectedTestStoppedEvents
            )
        }
    }
    
    private static func prepareResult(
        requestedEntryToRun: TestEntry,
        simulatorId: UDID,
        collectedTestStoppedEvents: [TestStoppedEvent]
    ) -> TestEntryResult {
        let correspondingTestStoppedEvents = testStoppedEvents(
            testName: requestedEntryToRun.testName,
            collectedTestStoppedEvents: collectedTestStoppedEvents
        )
        return testEntryResultForFinishedTest(
            simulatorId: simulatorId,
            testEntry: requestedEntryToRun,
            testStoppedEvents: correspondingTestStoppedEvents
        )
    }
    
    private static func testEntryResultForFinishedTest(
        simulatorId: UDID,
        testEntry: TestEntry,
        testStoppedEvents: [TestStoppedEvent]
    ) -> TestEntryResult {
        guard !testStoppedEvents.isEmpty else {
            return .lost(testEntry: testEntry)
        }
        return TestEntryResult.withResults(
            testEntry: testEntry,
            testRunResults: testStoppedEvents.map { testStoppedEvent -> TestRunResult in
                TestRunResult(
                    succeeded: testStoppedEvent.succeeded,
                    exceptions: testStoppedEvent.testExceptions,
                    duration: testStoppedEvent.testDuration,
                    startTime: testStoppedEvent.testStartTimestamp,
                    hostName: LocalHostDeterminer.currentHostAddress,
                    simulatorId: simulatorId
                )
            }
        )
    }
    
    private static func testStoppedEvents(
        testName: TestName,
        collectedTestStoppedEvents: [TestStoppedEvent]
    ) -> [TestStoppedEvent] {
        return collectedTestStoppedEvents.filter { $0.testName == testName }
    }
    
    private func missingEntriesForScheduledEntries(
        expectedEntriesToRun: [TestEntry],
        collectedResults: RunResult)
        -> [TestEntry]
    {
        let receivedTestEntries = Set(collectedResults.nonLostTestEntryResults.map { $0.testEntry })
        return expectedEntriesToRun.filter { !receivedTestEntries.contains($0) }
    }
    
    private func testEntryResults(
        runResult: RunResult,
        simulatorId: UDID
    ) -> [TestEntryResult] {
        return runResult.testEntryResults.map {
            if $0.isLost {
                return resultForSingleTestThatDidNotRun(
                    simulatorId: simulatorId,
                    testEntry: $0.testEntry
                )
            } else {
                return $0
            }
        }
    }
    
    private func resultForSingleTestThatDidNotRun(
        simulatorId: UDID,
        testEntry: TestEntry
    ) -> TestEntryResult {
        return .withResult(
            testEntry: testEntry,
            testRunResult: TestRunResult(
                succeeded: false,
                exceptions: [
                    RunnerConstants.testDidNotRun(testEntry.testName).testException
                ],
                duration: 0,
                startTime: dateProvider.currentDate().timeIntervalSince1970,
                hostName: LocalHostDeterminer.currentHostAddress,
                simulatorId: simulatorId
            )
        )
    }
}

private extension TestStoppedEvent {
    func byMergingTestExceptions(
        testExceptions: [TestException]
    ) -> TestStoppedEvent {
        return TestStoppedEvent(
            testName: testName,
            result: result,
            testDuration: testDuration,
            testExceptions: testExceptions + self.testExceptions,
            testStartTimestamp: testStartTimestamp
        )
    }
}

private class NoOpTestRunnerInvocation: TestRunnerInvocation {
    private class NoOpTestRunnerRunningInvocation: TestRunnerRunningInvocation {
        init() {}
        let pidInfo = PidInfo(pid: 0, name: "no-op process")
        func cancel() {}
        func wait() {}
    }
    
    init() {}
    
    func startExecutingTests() -> TestRunnerRunningInvocation { NoOpTestRunnerRunningInvocation() }
}
