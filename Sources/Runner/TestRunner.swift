import BuildArtifacts
import DeveloperDirLocator
import Foundation
import EmceeLogging
import ProcessController
import RunnerModels
import SimulatorPoolModels
import Tmp

public protocol TestRunnerRunningInvocation {
    var pidInfo: PidInfo { get }
    func cancel()
    func wait()
}

public protocol TestRunnerInvocation {
    func startExecutingTests() throws -> TestRunnerRunningInvocation
}

public protocol TestRunner {
    func prepareTestRun(
        buildArtifacts: BuildArtifacts,
        developerDirLocator: DeveloperDirLocator,
        entriesToRun: [TestEntry],
        logger: ContextualLogger,
        runnerWasteCollector: RunnerWasteCollector,
        simulator: Simulator,
        temporaryFolder: TemporaryFolder,
        testContext: TestContext,
        testRunnerStream: TestRunnerStream,
        testType: TestType
    ) throws -> TestRunnerInvocation
}

