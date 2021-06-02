import AtomicModels
import Dispatch
import Foundation
import EmceeLogging
import QueueClient
import QueueModels
import RequestSender
import SocketModels
import Types

public final class RemoteQueuePortScanner: RemotePortDeterminer {
    private let host: String
    private let logger: ContextualLogger
    private let portRange: ClosedRange<SocketModels.Port>
    private let requestSenderProvider: RequestSenderProvider
    private let workQueue = DispatchQueue(label: "RemoteQueuePortScanner.workQueue")
    
    public init(
        host: String,
        logger: ContextualLogger,
        portRange: ClosedRange<SocketModels.Port>,
        requestSenderProvider: RequestSenderProvider
    ) {
        self.host = host
        self.logger = logger
        self.portRange = portRange
        self.requestSenderProvider = requestSenderProvider
    }
    
    public func queryPortAndQueueServerVersion(timeout: TimeInterval) -> [SocketModels.Port: Version] {
        let group = DispatchGroup()
        
        let portToVersion = AtomicValue<[SocketModels.Port: Version]>([:])
        
        for port in portRange {
            group.enter()
            logger.debug("Checking availability of \(port)")
            
            let queueServerVersionFetcher = QueueServerVersionFetcherImpl(
                requestSender: requestSenderProvider.requestSender(
                    socketAddress: SocketAddress(host: host, port: port)
                )
            )
            
            queueServerVersionFetcher.fetchQueueServerVersion(
                callbackQueue: workQueue
            ) { (result: Either<Version, Error>) in
                if let version = try? result.dematerialize() {
                    self.logger.debug("Found queue server with \(version) version at \(port)")
                    portToVersion.withExclusiveAccess { $0[port] = version }
                }
                group.leave()
            }
        }
        
        _ = group.wait(timeout: .now() + timeout)
        return portToVersion.currentValue()
    }
}
