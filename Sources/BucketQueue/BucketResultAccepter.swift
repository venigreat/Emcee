import Foundation
import QueueModels

public protocol BucketResultAccepter {
    func accept(
        bucketId: BucketId,
        bucketResult: BucketResult,
        workerId: WorkerId
    ) throws -> BucketQueueAcceptResult
}
