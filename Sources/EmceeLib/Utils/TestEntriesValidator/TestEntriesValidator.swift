import EventBus
import EmceeLogging
import MetricsExtensions
import ResourceLocationResolver
import RunnerModels
import SimulatorPool
import Tmp
import TestArgFile
import TestDiscovery

public final class TestEntriesValidator {
    private let remoteCache: RuntimeDumpRemoteCache
    private let testArgFileEntries: [TestArgFileEntry]
    private let testDiscoveryQuerier: TestDiscoveryQuerier
    private let analyticsConfiguration: AnalyticsConfiguration
    private let transformer = TestToRunIntoTestEntryTransformer()

    public init(
        remoteCache: RuntimeDumpRemoteCache,
        testArgFileEntries: [TestArgFileEntry],
        testDiscoveryQuerier: TestDiscoveryQuerier,
        analyticsConfiguration: AnalyticsConfiguration
    ) {
        self.remoteCache = remoteCache
        self.testArgFileEntries = testArgFileEntries
        self.testDiscoveryQuerier = testDiscoveryQuerier
        self.analyticsConfiguration = analyticsConfiguration
    }
    
    public func validatedTestEntries(
        logger: ContextualLogger,
        intermediateResult: (TestArgFileEntry, [ValidatedTestEntry]) throws -> ()
    ) throws -> [ValidatedTestEntry] {
        var result = [ValidatedTestEntry]()
        
        for testArgFileEntry in testArgFileEntries {
            let validatedTestEntries = try self.validatedTestEntries(
                logger: logger,
                testArgFileEntry: testArgFileEntry
            )
            try intermediateResult(testArgFileEntry, validatedTestEntries)
            result.append(contentsOf: validatedTestEntries)
        }
        
        return result
    }

    private func validatedTestEntries(
        logger: ContextualLogger,
        testArgFileEntry: TestArgFileEntry
    ) throws -> [ValidatedTestEntry] {
        let configuration = TestDiscoveryConfiguration(
            analyticsConfiguration: analyticsConfiguration,
            developerDir: testArgFileEntry.developerDir,
            pluginLocations: testArgFileEntry.pluginLocations,
            testDiscoveryMode: try TestDiscoveryModeDeterminer.testDiscoveryMode(
                testArgFileEntry: testArgFileEntry
            ),
            simulatorOperationTimeouts: testArgFileEntry.simulatorOperationTimeouts,
            simulatorSettings: testArgFileEntry.simulatorSettings,
            testDestination: testArgFileEntry.testDestination,
            testExecutionBehavior: TestExecutionBehavior(
                environment: testArgFileEntry.environment,
                numberOfRetries: testArgFileEntry.numberOfRetries
            ),
            testRunnerTool: testArgFileEntry.testRunnerTool,
            testTimeoutConfiguration: testTimeoutConfigurationForRuntimeDump,
            testsToValidate: testArgFileEntry.testsToRun,
            xcTestBundleLocation: testArgFileEntry.buildArtifacts.xcTestBundle.location,
            remoteCache: remoteCache,
            logger: logger
        )

        return try transformer.transform(
            buildArtifacts: testArgFileEntry.buildArtifacts,
            testDiscoveryResult: try testDiscoveryQuerier.query(
                configuration: configuration
            )
        )
    }
}
