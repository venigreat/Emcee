import BucketPayloads
import QueueModels

public protocol TestHistoryTracker {
    func bucketToDequeue(
        workerId: WorkerId,
        queue: [EnqueuedBucket],
        workerIdsInWorkingCondition: @autoclosure () -> [WorkerId]
    ) -> EnqueuedBucket?
    
    func accept(
        testingResult: TestingResult,
        bucketId: BucketId,
        payload: RunTestsBucketPayload,
        workerId: WorkerId
    ) throws -> TestHistoryTrackerAcceptResult
}
