import BucketQueueModels
import DateProvider
import Dispatch
import Foundation
import EmceeLogging
import QueueModels
import RunnerModels
import TestHistoryTracker
import Types
import UniqueIdentifierGenerator
import WorkerAlivenessProvider
import WorkerCapabilities
import WorkerCapabilitiesModels

final class BucketQueueImpl: BucketQueue {
    private let dateProvider: DateProvider
    private let logger: ContextualLogger
    private let testHistoryTracker: TestHistoryTracker
    private let workerAlivenessProvider: WorkerAlivenessProvider
    private let uniqueIdentifierGenerator: UniqueIdentifierGenerator
    private let workerCapabilityConstraintResolver = WorkerCapabilityConstraintResolver()
    private let workerCapabilitiesStorage: WorkerCapabilitiesStorage
    
    private let bucketQueueHolder: BucketQueueHolder = BucketQueueHolder()
    
    public init(
        dateProvider: DateProvider,
        logger: ContextualLogger,
        testHistoryTracker: TestHistoryTracker,
        uniqueIdentifierGenerator: UniqueIdentifierGenerator,
        workerAlivenessProvider: WorkerAlivenessProvider,
        workerCapabilitiesStorage: WorkerCapabilitiesStorage
    ) {
        self.dateProvider = dateProvider
        self.logger = logger
        self.testHistoryTracker = testHistoryTracker
        self.uniqueIdentifierGenerator = uniqueIdentifierGenerator
        self.workerAlivenessProvider = workerAlivenessProvider
        self.workerCapabilitiesStorage = workerCapabilitiesStorage
    }
    
    public func enqueue(buckets: [Bucket]) throws {
        try SingleBucketQueueEnqueuer(
            bucketQueueHolder: bucketQueueHolder,
            dateProvider: dateProvider,
            uniqueIdentifierGenerator: uniqueIdentifierGenerator,
            workerAlivenessProvider: workerAlivenessProvider,
            workerCapabilitiesStorage: workerCapabilitiesStorage
        ).enqueue(buckets: buckets)
    }
    
    public var runningQueueState: RunningQueueState {
        SingleBucketQueueRunningQueueStateProvider(
            bucketQueueHolder: bucketQueueHolder
        ).runningQueueState
    }

    public func dequeueBucket(workerCapabilities: Set<WorkerCapability>, workerId: WorkerId) -> DequeuedBucket? {
        SingleBucketQueueDequeueableBucketSource(
            bucketQueueHolder: bucketQueueHolder,
            logger: logger,
            testHistoryTracker: testHistoryTracker,
            workerAlivenessProvider: workerAlivenessProvider,
            workerCapabilitiesStorage: workerCapabilitiesStorage
        ).dequeueBucket(workerCapabilities: workerCapabilities, workerId: workerId)
    }
    
    func removeAllEnqueuedBuckets() {
        SingleEmptyableBucketQueue(
            bucketQueueHolder: bucketQueueHolder
        ).removeAllEnqueuedBuckets()
    }
    
    func reenqueueStuckBuckets() -> [StuckBucket] {
        SingleBucketQueueStuckBucketsReenqueuer(
            bucketEnqueuer: SingleBucketQueueEnqueuer(
                bucketQueueHolder: bucketQueueHolder,
                dateProvider: dateProvider,
                uniqueIdentifierGenerator: uniqueIdentifierGenerator,
                workerAlivenessProvider: workerAlivenessProvider,
                workerCapabilitiesStorage: workerCapabilitiesStorage
            ),
            bucketQueueHolder: bucketQueueHolder,
            logger: logger,
            workerAlivenessProvider: workerAlivenessProvider,
            uniqueIdentifierGenerator: uniqueIdentifierGenerator
        ).reenqueueStuckBuckets()
    }
    
    func accept(
        bucketId: BucketId,
        testingResult: TestingResult,
        workerId: WorkerId
    ) throws -> BucketQueueAcceptResult {
        try SingleBucketResultAccepter(
            bucketEnqueuer: SingleBucketQueueEnqueuer(
                bucketQueueHolder: bucketQueueHolder,
                dateProvider: dateProvider,
                uniqueIdentifierGenerator: uniqueIdentifierGenerator,
                workerAlivenessProvider: workerAlivenessProvider,
                workerCapabilitiesStorage: workerCapabilitiesStorage
            ),
            bucketQueueHolder: bucketQueueHolder,
            logger: logger,
            testHistoryTracker: testHistoryTracker
        ).accept(
            bucketId: bucketId,
            testingResult: testingResult,
            workerId: workerId
        )
    }
    
}
