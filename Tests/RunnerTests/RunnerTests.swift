import BuildArtifacts
import BuildArtifactsTestHelpers
import DateProviderTestHelpers
import DeveloperDirLocatorTestHelpers
import EventBus
import FileSystemTestHelpers
import Foundation
import EmceeLogging
import MetricsExtensions
import MetricsTestHelpers
import PluginManagerTestHelpers
import QueueModels
import ResourceLocationResolverTestHelpers
import Runner
import RunnerModels
import RunnerTestHelpers
import SimulatorPoolModels
import SimulatorPoolTestHelpers
import SynchronousWaiter
import Tmp
import TestHelpers
import XCTest

public final class RunnerTests: XCTestCase {
    lazy var testEntry = TestEntryFixtures.testEntry()
    lazy var noOpPluginEventBusProvider = NoOoPluginEventBusProvider()
    lazy var testTimeout: TimeInterval = 3
    lazy var impactQueue = DispatchQueue(label: "impact queue")
    lazy var resolver = FakeResourceLocationResolver.resolvingTo(path: tempFolder.absolutePath)
    lazy var testRunnerProvider = FakeTestRunnerProvider(tempFolder: tempFolder)
    lazy var tempFolder = assertDoesNotThrow { try TemporaryFolder() }
    lazy var fileSystem = FakeFileSystem(rootPath: tempFolder.absolutePath)
    lazy var dateProvider = DateProviderFixture(Date(timeIntervalSince1970: 100))
    
    func test___running_test_without_output_to_stream___provides_test_did_not_run_results() throws {
        testRunnerProvider.predefinedFakeTestRunner.disableTestStartedTestRunnerStreamEvents()
        testRunnerProvider.predefinedFakeTestRunner.disableTestStoppedTestRunnerStreamEvents()

        let runnerResults = try runTestEntries([testEntry])
        
        XCTAssertEqual(runnerResults.testEntryResults.count, 1)

        guard runnerResults.testEntryResults.count == 1, let testResult = runnerResults.testEntryResults.first else {
            failTest("Unexpected number of test results")
        }

        XCTAssertFalse(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
        XCTAssertEqual(testResult.testRunResults[0].exceptions.first, RunnerConstants.testDidNotRun(testEntry.testName).testException)
    }

    func test___running_test_with_successful_result___provides_successful_results() throws {
        let runnerResults = try runTestEntries([testEntry])

        guard runnerResults.testEntryResults.count == 1, let testResult = runnerResults.testEntryResults.first else {
            failTest("Unexpected number of test results")
        }

        XCTAssertTrue(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
    }

    func test___running_test_with_failing_result___provides_test_failed_result() throws {
        testRunnerProvider.predefinedFakeTestRunner.onExecuteTest = { _ in .failure }

        let runnerResults = try runTestEntries([testEntry])

        guard runnerResults.testEntryResults.count == 1, let testResult = runnerResults.testEntryResults.first else {
            failTest("Unexpected number of test results")
        }

        XCTAssertFalse(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
    }

    func test___running_test_with_lost_result___provides_test_failed_results() throws {
        testRunnerProvider.predefinedFakeTestRunner.onExecuteTest = { _ in .lost }

        let runnerResults = try runTestEntries([testEntry])

        guard runnerResults.testEntryResults.count == 1, let testResult = runnerResults.testEntryResults.first else {
            failTest("Unexpected number of test results")
        }

        XCTAssertFalse(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
    }
    
    func test___running_test___creates_plugin_event_bus() throws {
        _ = try runTestEntries([testEntry])

        XCTAssertEqual(
            noOpPluginEventBusProvider.eventBusRequests,
            1,
            "Runner should have requested event bus"
        )
    }
    
    func test___running_test___tears_down_plugin_event_bus() throws {
        let busTornDownExpectation = expectation(description: "Event Bus has been torn down")
        
        noOpPluginEventBusProvider.eventBus.add(
            stream: BlockBasedEventStream { (busEvent: BusEvent) in
                switch busEvent {
                case .runnerEvent:
                    break
                case .tearDown:
                    busTornDownExpectation.fulfill()
                }
            }
        )
        
        _ = try runTestEntries([testEntry])

        wait(for: [busTornDownExpectation], timeout: 15)
    }

    func test___running_test_without_stop_event_output_to_stream___revives_and_attempts_to_run_it_again() throws {
        testRunnerProvider.predefinedFakeTestRunner.disableTestStoppedTestRunnerStreamEvents()

        var numberOfAttemptsToRunTest = 0
        testRunnerProvider.predefinedFakeTestRunner.onExecuteTest = { _ in
            numberOfAttemptsToRunTest += 1
            return .success
        }

        let runnerResults = try runTestEntries([testEntry])

        XCTAssertEqual(numberOfAttemptsToRunTest, 2)

        guard runnerResults.testEntryResults.count == 1, let testResult = runnerResults.testEntryResults.first else {
            failTest("Unexpected number of test results")
        }

        XCTAssertFalse(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
        XCTAssertEqual(testResult.testRunResults[0].exceptions.first, RunnerConstants.testDidNotRun(testEntry.testName).testException)
    }

    func test___running_test_and_reviving_after_test_stopped_event_loss___provides_back_correct_result() throws {
        var didRevive = false
        testRunnerProvider.predefinedFakeTestRunner.onExecuteTest = { _ in
            didRevive = true
            return .success
        }

        testRunnerProvider.predefinedFakeTestRunner.onTestStopped = { testStoppedEvent, testRunnerStream in
            // simulate situation when first testStoppedEvent gets lost
            if didRevive {
                let handler = FakeTestRunner.testStoppedHandlerForNormalEventStreaming()
                handler(testStoppedEvent, testRunnerStream)
            }
        }

        let runnerResults = try runTestEntries([testEntry])

        guard runnerResults.testEntryResults.count == 1, let testResult = runnerResults.testEntryResults.first else {
            failTest("Unexpected number of test results")
        }

        XCTAssertTrue(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
    }

    func test___if_test_runner_fails_to_run___runner_provides_back_all_tests_as_failed() throws {
        testRunnerProvider.predefinedFakeTestRunner.makeRunThrowErrors()
        
        let runnerResults = try runTestEntries([testEntry])

        guard runnerResults.testEntryResults.count == 1, let testResult = runnerResults.testEntryResults.first else {
            return XCTFail("Unexpected number of test results")
        }

        XCTAssertFalse(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
        XCTAssertEqual(
            testResult.testRunResults[0].exceptions.first,
            RunnerConstants.failedToStartTestRunner(FakeTestRunner.SomeError()).testException
        )
    }
    
    func test___if_test_runner_fails_to_run___test_runner_stream_is_closed() throws {
        let eventExpectation = expectationForDidRunEvent()
        
        _ = try runTestEntries([testEntry])

        wait(for: [eventExpectation], timeout: 15)
    }
    
    func test___if_test_timeout___test_timeout_reason_reported() throws {
        testTimeout = 1
        testRunnerProvider.predefinedFakeTestRunner.disableTestStoppedTestRunnerStreamEvents()
        testRunnerProvider.predefinedFakeTestRunner.onExecuteTest = { _ in
            SynchronousWaiter().wait(
                timeout: self.testTimeout + 3.0,
                description: "Artificial wait to imitate test timeout"
            )
            return .failure
        }
        
        impactQueue.asyncAfter(deadline: .now() + 1.0) {
            self.dateProvider.result += self.testTimeout + 1
        }
        
        let runnerResults = try runTestEntries([testEntry])
        
        guard runnerResults.testEntryResults.count == 1, let testEntryResult = runnerResults.testEntryResults.first else {
            failTest("Unexpected number of results")
        }
        guard testEntryResult.testRunResults.count == 1, let testRunResult = testEntryResult.testRunResults.first else {
            failTest("Unexpected number of results")
        }
        XCTAssertFalse(testRunResult.succeeded)
        XCTAssertEqual(
            testRunResult.exceptions.first,
            RunnerConstants.testTimeout(testTimeout).testException
        )
    }
    
    func test___runner_waits_for_stream_to_close() throws {
        let streamIsStillOpenExpectation = expectationForDidRunEvent()
        streamIsStillOpenExpectation.expectationDescription = "Stream is still open (hasn't been closed)"
        streamIsStillOpenExpectation.isInverted = true
        
        let streamClosedExpectation = expectationForDidRunEvent()
        
        
        let handlerInvokedExpectation = XCTestExpectation(description: "stream close handler called")
        
        testRunnerProvider.predefinedFakeTestRunner.onStreamClose = { testRunnerStream in
            self.wait(for: [streamIsStillOpenExpectation], timeout: 5)
            
            testRunnerStream.closeStream()
            
            self.wait(for: [streamClosedExpectation], timeout: 5)
            
            handlerInvokedExpectation.fulfill()
        }
        
        _ = try runTestEntries([testEntry])
        
        wait(for: [handlerInvokedExpectation], timeout: 5)
    }
    
    private func expectationForDidRunEvent() -> XCTestExpectation {
        let eventExpectation = XCTestExpectation(description: "didRun event has been sent")
        
        noOpPluginEventBusProvider.eventBus.add(
            stream: BlockBasedEventStream { (busEvent: BusEvent) in
                switch busEvent {
                case let .runnerEvent(runnerEvent):
                    switch runnerEvent {
                    case .didRun:
                        eventExpectation.fulfill()
                    case .willRun, .testStarted, .testFinished:
                        break
                    }
                case .tearDown:
                    break
                }
            }
        )
        
        return eventExpectation
    }
    
    private func runTestEntries(_ testEntries: [TestEntry]) throws -> RunnerRunResult {
        let runner = Runner(
            configuration: createRunnerConfig(),
            dateProvider: dateProvider,
            developerDirLocator: FakeDeveloperDirLocator(result: tempFolder.absolutePath),
            fileSystem: fileSystem,
            logger: .noOp,
            persistentMetricsJobId: nil,
            pluginEventBusProvider: noOpPluginEventBusProvider,
            resourceLocationResolver: resolver,
            specificMetricRecorder: SpecificMetricRecorderWrapper(NoOpMetricRecorder()),
            tempFolder: tempFolder,
            testRunnerProvider: testRunnerProvider,
            testTimeoutCheckInterval: .milliseconds(100),
            version: Version(value: "version"),
            waiter: SynchronousWaiter()
        )
        return try runner.run(
            entries: testEntries,
            developerDir: .current,
            simulator: Simulator(
                testDestination: TestDestinationFixtures.testDestination,
                udid: UDID(value: UUID().uuidString),
                path: tempFolder.absolutePath
            )
        )
    }

    private func createRunnerConfig() -> RunnerConfiguration {
        return RunnerConfiguration(
            buildArtifacts: BuildArtifactsFixtures.fakeEmptyBuildArtifacts(),
            environment: [:],
            pluginLocations: [],
            simulatorSettings: SimulatorSettingsFixtures().simulatorSettings(),
            testRunnerTool: .xcodebuild,
            testTimeoutConfiguration: TestTimeoutConfiguration(
                singleTestMaximumDuration: testTimeout,
                testRunnerMaximumSilenceDuration: 0
            ),
            testType: .logicTest
        )
    }
}
