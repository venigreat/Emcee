import BucketPayloads
import QueueModels

public final class TestHistoryTrackerAcceptResult {
    public let payloadsToReenqueue: [RunTestsBucketPayload]
    public let testingResult: TestingResult
    
    public init(
        payloadsToReenqueue: [RunTestsBucketPayload],
        testingResult: TestingResult
    ) {
        self.payloadsToReenqueue = payloadsToReenqueue
        self.testingResult = testingResult
    }
}
