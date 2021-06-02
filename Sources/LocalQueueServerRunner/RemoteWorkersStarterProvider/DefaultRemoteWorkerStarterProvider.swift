import Deployer
import DistDeployer
import EmceeLogging
import Foundation
import ProcessController
import QueueModels
import SocketModels
import Tmp
import UniqueIdentifierGenerator

public final class DefaultRemoteWorkerStarterProvider: RemoteWorkerStarterProvider {
    private let emceeVersion: Version
    private let logger: ContextualLogger
    private let processControllerProvider: ProcessControllerProvider
    private let tempFolder: TemporaryFolder
    private let uniqueIdentifierGenerator: UniqueIdentifierGenerator
    private let workerDeploymentDestinations: [DeploymentDestination]
    
    public init(
        emceeVersion: Version,
        logger: ContextualLogger,
        processControllerProvider: ProcessControllerProvider,
        tempFolder: TemporaryFolder,
        uniqueIdentifierGenerator: UniqueIdentifierGenerator,
        workerDeploymentDestinations: [DeploymentDestination]
    ) {
        self.emceeVersion = emceeVersion
        self.logger = logger
        self.processControllerProvider = processControllerProvider
        self.tempFolder = tempFolder
        self.uniqueIdentifierGenerator = uniqueIdentifierGenerator
        self.workerDeploymentDestinations = workerDeploymentDestinations
    }
    
    public enum DefaultRemoteWorkerStarterProviderError: Error, CustomStringConvertible {
        case noDeploymentDestinationForWorkerId(WorkerId)
        
        public var description: String {
            switch self {
            case .noDeploymentDestinationForWorkerId(let workerId):
                return "No known deployment destination is available for \(workerId)"
            }
        }
    }
    
    public func remoteWorkerStarter(
        workerId: WorkerId
    ) throws -> RemoteWorkerStarter {
        guard let deploymentDestination = workerDeploymentDestinations.first(where: { $0.workerId == workerId }) else {
            throw DefaultRemoteWorkerStarterProviderError.noDeploymentDestinationForWorkerId(workerId)
        }
        
        return DefaultRemoteWorkersStarter(
            deploymentDestination: deploymentDestination,
            emceeVersion: emceeVersion,
            logger: logger,
            processControllerProvider: processControllerProvider,
            tempFolder: tempFolder,
            uniqueIdentifierGenerator: uniqueIdentifierGenerator
        )
    }
}
