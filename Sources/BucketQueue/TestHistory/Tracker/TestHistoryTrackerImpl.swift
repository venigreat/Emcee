import BucketPayloads
import QueueModels
import RunnerModels
import UniqueIdentifierGenerator

public final class TestHistoryTrackerImpl: TestHistoryTracker {
    private let testHistoryStorage: TestHistoryStorage
    private let uniqueIdentifierGenerator: UniqueIdentifierGenerator
    
    public init(
        testHistoryStorage: TestHistoryStorage,
        uniqueIdentifierGenerator: UniqueIdentifierGenerator
    ) {
        self.testHistoryStorage = testHistoryStorage
        self.uniqueIdentifierGenerator = uniqueIdentifierGenerator
    }
    
    public func bucketToDequeue(
        workerId: WorkerId,
        queue: [EnqueuedBucket],
        workerIdsInWorkingCondition: @autoclosure () -> [WorkerId]
    ) -> EnqueuedBucket? {
        let enqueuedPayloads: [(bucketId: BucketId, payload: RunTestsBucketPayload)] = queue.compactMap {
            guard let payload = $0.bucket.bucketPayload as? RunTestsBucketPayload else { return nil }
            return ($0.bucket.bucketId, payload)
        }
        
        let bucketThatWasNotFailingOnWorkerOrNil = enqueuedPayloads.first { pair in
            !bucketWasFailingOnWorker(bucketId: pair.bucketId, payload: pair.payload, workerId: workerId)
        }
        
        if let bucketToDequeue = bucketThatWasNotFailingOnWorkerOrNil {
            return queue.first(where: { $0.bucket.bucketId == bucketToDequeue.bucketId })
        } else {
            let computedWorkerIdsInWorkingCondition = workerIdsInWorkingCondition()
            
            if let bucketThatWasFailingOnEveryWorker = enqueuedPayloads.first(
                where: { pair in
                    bucketWasFailingOnEveryWorker(
                        bucketId: pair.bucketId,
                        payload: pair.payload,
                        workerIdsInWorkingCondition: computedWorkerIdsInWorkingCondition
                    )
                }
            ) {
                return queue.first(where: { $0.bucket.bucketId == bucketThatWasFailingOnEveryWorker.bucketId })
            }
            
            return nil
        }
    }
    
    public func accept(
        testingResult: TestingResult,
        bucketId: BucketId,
        payload: RunTestsBucketPayload,
        workerId: WorkerId
    ) throws -> TestHistoryTrackerAcceptResult {
        var resultsOfSuccessfulTests = [TestEntryResult]()
        var resultsOfFailedTests = [TestEntryResult]()
        var resultsOfTestsToRetry = [TestEntryResult]()
        
        for testEntryResult in testingResult.unfilteredResults {
            let id = TestEntryHistoryId(
                bucketId: bucketId,
                testEntry: testEntryResult.testEntry
            )
            
            let testEntryHistory = testHistoryStorage.registerAttempt(
                id: id,
                testEntryResult: testEntryResult,
                workerId: workerId
            )
            
            if testEntryResult.succeeded {
                resultsOfSuccessfulTests.append(testEntryResult)
            } else {
                if testEntryHistory.numberOfAttempts < numberOfAttemptsToRunTests(payload: payload) {
                    resultsOfTestsToRetry.append(testEntryResult)
                } else {
                    resultsOfFailedTests.append(testEntryResult)
                }
            }
        }
        
        let testingResult = TestingResult(
            testDestination: payload.testDestination,
            unfilteredResults: resultsOfSuccessfulTests + resultsOfFailedTests
        )
        
        // Every failed test produces a single bucket with itself
        let payloadsToReenqueue = resultsOfTestsToRetry.map { testEntryResult in
            RunTestsBucketPayload(
                buildArtifacts: payload.buildArtifacts,
                developerDir: payload.developerDir,
                pluginLocations: payload.pluginLocations,
                simulatorControlTool: payload.simulatorControlTool,
                simulatorOperationTimeouts: payload.simulatorOperationTimeouts,
                simulatorSettings: payload.simulatorSettings,
                testDestination: payload.testDestination,
                testEntries: [testEntryResult.testEntry],
                testExecutionBehavior: payload.testExecutionBehavior,
                testRunnerTool: payload.testRunnerTool,
                testTimeoutConfiguration: payload.testTimeoutConfiguration,
                testType: payload.testType
            )
        }
        
//        payloadsToReenqueue.forEach { reenqueuingBucket in
//            reenqueuingBucket.testEntries.forEach { entry in
//                let id = TestEntryHistoryId(
//                    bucketId: bucket.bucketId,
//                    testEntry: entry
//                )
//
//                testHistoryStorage.registerReenqueuedBucketId(
//                    testEntryHistoryId: id,
//                    enqueuedBucketId: reenqueuingBucket.bucketId
//                )
//            }
//        }
        
        return TestHistoryTrackerAcceptResult(
            payloadsToReenqueue: payloadsToReenqueue,
            testingResult: testingResult
        )
    }
    
    private func bucketWasFailingOnWorker(
        bucketId: BucketId,
        payload: RunTestsBucketPayload,
        workerId: WorkerId
    ) -> Bool {
        let onWorker: (TestEntryHistory) -> Bool = { testEntryHistory in
            testEntryHistory.isFailingOnWorker(workerId: workerId)
        }
        return bucketWasFailing(
            bucketId: bucketId,
            payload: payload,
            whereItWasFailing: onWorker
        )
    }
    
    private func bucketWasFailingOnEveryWorker(
        bucketId: BucketId,
        payload: RunTestsBucketPayload,
        workerIdsInWorkingCondition: [WorkerId]
    ) -> Bool {
        let onEveryWorker: (TestEntryHistory) -> Bool = { testEntryHistory in
            let everyWorkerFailed = workerIdsInWorkingCondition.allSatisfy { workerId in
                testEntryHistory.isFailingOnWorker(workerId: workerId)
            }
            return everyWorkerFailed
        }
        return bucketWasFailing(
            bucketId: bucketId,
            payload: payload,
            whereItWasFailing: onEveryWorker
        )
    }
    
    private func bucketWasFailing(
        bucketId: BucketId,
        payload: RunTestsBucketPayload,
        whereItWasFailing: (TestEntryHistory) -> Bool
    ) -> Bool {
        return payload.testEntries.contains { testEntry in
            testEntryWasFailing(
                testEntry: testEntry,
                bucketId: bucketId,
                whereItWasFailing: whereItWasFailing
            )
        }
    }
    
    private func testEntryWasFailing(
        testEntry: TestEntry,
        bucketId: BucketId,
        whereItWasFailing: (TestEntryHistory) -> Bool
    ) -> Bool {
        let testEntryHistoryId = TestEntryHistoryId(
            bucketId: bucketId,
            testEntry: testEntry
        )
        let testEntryHistory = testHistoryStorage.history(id: testEntryHistoryId)
        
        return whereItWasFailing(testEntryHistory)
    }
    
    private func numberOfAttemptsToRunTests(payload: RunTestsBucketPayload) -> UInt {
        return 1 + payload.testExecutionBehavior.numberOfRetries
    }
}
