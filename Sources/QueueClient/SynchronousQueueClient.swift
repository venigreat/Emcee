import Dispatch
import Foundation
import Logging
import QueueModels
import RESTMethods
import RequestSender
import ScheduleStrategy
import SocketModels
import SynchronousWaiter
import Types

public final class SynchronousQueueClient: QueueClientDelegate {
    private let queueClient: QueueClient
    private var jobResultsResult: Either<JobResults, QueueClientError>?
    private var jobDeleteResult: Either<JobId, QueueClientError>?
    private let syncQueue = DispatchQueue(label: "ru.avito.SynchronousQueueClient")
    private let requestTimeout: TimeInterval
    private let networkRequestRetryCount: Int
    
    public init(
        queueServerAddress: SocketAddress,
        requestTimeout: TimeInterval = 10,
        networkRequestRetryCount: Int = 5
    ) {
        self.requestTimeout = requestTimeout
        self.networkRequestRetryCount = networkRequestRetryCount
        self.queueClient = QueueClient(
            queueServerAddress: queueServerAddress,
            requestSenderProvider: DefaultRequestSenderProvider()
        )
        self.queueClient.delegate = self
    }
    
    public func close() {
        queueClient.close()
    }
    
    // MARK: Public API
    
    public func jobResults(jobId: JobId) throws -> JobResults {
        return try synchronize {
            jobResultsResult = nil
            return try runRetrying {
                try queueClient.fetchJobResults(jobId: jobId)
                try SynchronousWaiter().waitWhile(timeout: requestTimeout, description: "Wait for \(jobId) job results") {
                    self.jobResultsResult == nil
                }
                return try jobResultsResult!.dematerialize()
            }
        }
    }
    
    public func delete(jobId: JobId) throws -> JobId {
        return try synchronize {
            jobDeleteResult = nil
            try queueClient.deleteJob(jobId: jobId)
            try SynchronousWaiter().waitWhile(timeout: requestTimeout, description: "Wait for job \(jobId) to be deleted") {
                self.jobDeleteResult == nil
            }
            return try jobDeleteResult!.dematerialize()
        }
    }
    
    // MARK: - Private
    
    private func synchronize<T>(_ work: () throws -> T) rethrows -> T {
        return try syncQueue.sync {
            return try work()
        }
    }
    
    private func runRetrying<T>(_ work: () throws -> T) rethrows -> T {
        for retryIndex in 0 ..< networkRequestRetryCount {
            if retryIndex > 0 {
                Logger.verboseDebug("Attempting to send request: #\(retryIndex + 1) of \(networkRequestRetryCount)")
            }
            do {
                return try work()
            } catch {
                Logger.error("Failed to send request with error: \(error)")
                SynchronousWaiter().wait(timeout: 1.0, description: "Pause between request retries")
            }
        }
        return try work()
    }
    
    // MARK: - Queue Delegate
    
    public func queueClient(_ sender: QueueClient, didFailWithError error: QueueClientError) {
        jobResultsResult = Either.error(error)
        jobDeleteResult = Either.error(error)
    }
    
    public func queueClient(_ sender: QueueClient, didFetchJobResults jobResults: JobResults) {
        jobResultsResult = Either.success(jobResults)
    }
    
    public func queueClient(_ sender: QueueClient, didDeleteJob jobId: JobId) {
        jobDeleteResult = Either.success(jobId)
    }
}
