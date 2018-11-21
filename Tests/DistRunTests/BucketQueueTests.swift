import DistRun
import Foundation
import Models
import ModelsTestHelpers
import WorkerAlivenessTracker
import XCTest

final class BucketQueueTests: XCTestCase {
    let workerConfigurations = WorkerConfigurations()
    
    let workerId = "worker_id"
    let requestId = "request_id"
    let alivenessTrackerWithImmediateTimeout = FakeWorkerAlivenessTracker.alivenessTrackerWithImmediateTimeout()
    let alivenessTrackerWithAlwaysAliveResults = FakeWorkerAlivenessTracker.alivenessTrackerWithAlwaysAliveResults()
    let mutableAlivenessProvider = FakeWorkerAlivenessProvider()
    
    override func setUp() {
        continueAfterFailure = false
        
        alivenessTrackerWithImmediateTimeout.didRegisterWorker(workerId: workerId)
        alivenessTrackerWithAlwaysAliveResults.didRegisterWorker(workerId: workerId)
        mutableAlivenessProvider.aliveness[workerId] = .alive
    }
    
    func test__whenQueueIsCreated__it_is_depleted() {
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithImmediateTimeout)
        XCTAssertTrue(bucketQueue.state.isDepleted)
    }
    
    func test__if_buckets_enqueued__queue_is_not_depleted() {
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithImmediateTimeout)
        bucketQueue.enqueue(buckets: [BucketFixtures.createBucket(testEntries: [])])
        XCTAssertFalse(bucketQueue.state.isDepleted)
    }
    
    func test__if_buckets_dequeued__queue_is_not_depleted() {
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithImmediateTimeout)
        bucketQueue.enqueue(buckets: [BucketFixtures.createBucket(testEntries: [])])
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        XCTAssertFalse(bucketQueue.state.isDepleted)
    }
    
    func test__when_all_results_accepted__queue_is_depleted() {
        let bucket = BucketFixtures.createBucket(testEntries: [])
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        bucketQueue.enqueue(buckets: [bucket])
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        let testingResult = TestingResult(
            bucketId: bucket.bucketId,
            testDestination: bucket.testDestination,
            unfilteredResults: [])
        XCTAssertNoThrow(try bucketQueue.accept(testingResult: testingResult, requestId: requestId, workerId: workerId))
        
        XCTAssertTrue(bucketQueue.state.isDepleted)
    }
    
    func test__reponse_dequeuedBucket__when_dequeueing_buckets() {
        let bucket = BucketFixtures.createBucket(testEntries: [])
        
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        bucketQueue.enqueue(buckets: [bucket])
        let dequeueResult = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        XCTAssertEqual(dequeueResult, .dequeuedBucket(DequeuedBucket(bucket: bucket, workerId: workerId, requestId: requestId)))
    }
    
    func test__reponse_queueIsEmpty__when_dequeueing_bucket_from_empty_queue() {
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        let dequeueResult = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        XCTAssertEqual(dequeueResult, .queueIsEmpty)
    }
    
    func test__reponse_queueIsEmptyButNotAllResultsAreAvailable__when_queue_has_dequeued_buckets() {
        let bucket = BucketFixtures.createBucket(testEntries: [])
        
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        bucketQueue.enqueue(buckets: [bucket])
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        let dequeueResult = bucketQueue.dequeueBucket(requestId: "some other request", workerId: workerId)
        XCTAssertEqual(dequeueResult, .queueIsEmptyButNotAllResultsAreAvailable)
    }
    
    func test__reponse_workerBlocked__when_worker_is_blocked() {
        alivenessTrackerWithAlwaysAliveResults.didBlockWorker(workerId: workerId)
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        
        let bucket = BucketFixtures.createBucket(testEntries: [])
        bucketQueue.enqueue(buckets: [bucket])
        
        let dequeueResult = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        XCTAssertEqual(dequeueResult, .workerBlocked)
    }
    
    func test__dequeueing_previously_dequeued_buckets() {
        let bucket = BucketFixtures.createBucket(testEntries: [])
        
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        bucketQueue.enqueue(buckets: [bucket])
        
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        let dequeueResult = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        XCTAssertEqual(dequeueResult, .dequeuedBucket(DequeuedBucket(bucket: bucket, workerId: workerId, requestId: requestId)))
    }
    
    func test__accepting_correct_results() {
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        
        let testEntry = TestEntry(className: "class", methodName: "test", caseId: nil)
        let bucket = BucketFixtures.createBucket(testEntries: [testEntry])
        bucketQueue.enqueue(buckets: [bucket])
        
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        let testingResult = TestingResult(
            bucketId: bucket.bucketId,
            testDestination: bucket.testDestination,
            unfilteredResults: [TestEntryResult.lost(testEntry: testEntry)])
        XCTAssertNoThrow(try bucketQueue.accept(testingResult: testingResult, requestId: requestId, workerId: workerId))
    }
    
    func test__accepting_result_for_nonexisting_request_id_throws() {
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        
        let testEntry = TestEntry(className: "class", methodName: "test", caseId: nil)
        let bucket = BucketFixtures.createBucket(testEntries: [testEntry])
        bucketQueue.enqueue(buckets: [bucket])
        
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        let testingResult = TestingResult(
            bucketId: bucket.bucketId,
            testDestination: bucket.testDestination,
            unfilteredResults: [ /* empty - misses testEntry */ ])
        XCTAssertThrowsError(try bucketQueue.accept(testingResult: testingResult, requestId: "wrong id", workerId: workerId))
    }
    
    func test__accepting_result_for_nonexisting_worker_id_throws() {
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithImmediateTimeout)
        
        let testEntry = TestEntry(className: "class", methodName: "test", caseId: nil)
        let bucket = BucketFixtures.createBucket(testEntries: [testEntry])
        bucketQueue.enqueue(buckets: [bucket])
        
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        let testingResult = TestingResult(
            bucketId: bucket.bucketId,
            testDestination: bucket.testDestination,
            unfilteredResults: [ /* empty - misses testEntry */ ])
        XCTAssertThrowsError(try bucketQueue.accept(testingResult: testingResult, requestId: requestId, workerId: "wrong id"))
    }
    
    func test__when_worker_is_silent__its_dequeued_buckets_removed() {
        let bucket = BucketFixtures.createBucket(testEntries: [])
        
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: mutableAlivenessProvider)
        bucketQueue.enqueue(buckets: [bucket])
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        mutableAlivenessProvider.aliveness[workerId] = .silent
        
        let stuckBuckets = bucketQueue.removeStuckBuckets()
        XCTAssertEqual(stuckBuckets, [StuckBucket(reason: .workerIsSilent, bucket: bucket, workerId: workerId)])
    }
    
    func test__when_worker_is_blocked__its_dequeued_buckets_removed() {
        let bucket = BucketFixtures.createBucket(testEntries: [])
        
        let bucketQueue = BucketQueueFactory.create(workerAlivenessProvider: alivenessTrackerWithAlwaysAliveResults)
        bucketQueue.enqueue(buckets: [bucket])
        _ = bucketQueue.dequeueBucket(requestId: requestId, workerId: workerId)
        
        alivenessTrackerWithAlwaysAliveResults.didBlockWorker(workerId: workerId)
        let stuckBuckets = bucketQueue.removeStuckBuckets()
        XCTAssertEqual(stuckBuckets, [StuckBucket(reason: .workerIsBlocked, bucket: bucket, workerId: workerId)])
    }
}
