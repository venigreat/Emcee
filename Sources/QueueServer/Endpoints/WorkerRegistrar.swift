import Dispatch
import DistWorkerModels
import Foundation
import EmceeLogging
import QueueModels
import RESTInterfaces
import RESTMethods
import RESTServer
import WorkerAlivenessProvider
import WorkerCapabilities

public final class WorkerRegistrar: RESTEndpoint {
    private let logger: ContextualLogger
    private let workerAlivenessProvider: WorkerAlivenessProvider
    private let workerCapabilitiesStorage: WorkerCapabilitiesStorage
    private let workerConfigurations: WorkerConfigurations
    private let workerDetailsHolder: WorkerDetailsHolder
    public let path: RESTPath = RESTMethod.registerWorker
    public let requestIndicatesActivity = true
    
    public enum WorkerRegistrarError: Swift.Error, CustomStringConvertible {
        case missingWorkerConfiguration(workerId: WorkerId)
        case workerIsAlreadyRegistered(workerId: WorkerId)
        
        public var description: String {
            switch self {
            case .missingWorkerConfiguration(let workerId):
                return "Missing worker configuration for \(workerId)"
            case .workerIsAlreadyRegistered(let workerId):
                return "Can't register \(workerId) because it is already registered"
            }
        }
    }
    
    public init(
        logger: ContextualLogger,
        workerAlivenessProvider: WorkerAlivenessProvider,
        workerCapabilitiesStorage: WorkerCapabilitiesStorage,
        workerConfigurations: WorkerConfigurations,
        workerDetailsHolder: WorkerDetailsHolder
    ) {
        self.logger = logger
        self.workerAlivenessProvider = workerAlivenessProvider
        self.workerCapabilitiesStorage = workerCapabilitiesStorage
        self.workerConfigurations = workerConfigurations
        self.workerDetailsHolder = workerDetailsHolder
    }
    
    public func handle(payload: RegisterWorkerPayload) throws -> RegisterWorkerResponse {
        guard let workerConfiguration = workerConfigurations.workerConfiguration(workerId: payload.workerId) else {
            throw WorkerRegistrarError.missingWorkerConfiguration(workerId: payload.workerId)
        }
        logger.debug("Registration request from worker with id: \(payload.workerId)")
        
        workerCapabilitiesStorage.set(workerCapabilities: payload.workerCapabilities, forWorkerId: payload.workerId)
        
        let workerAliveness = workerAlivenessProvider.alivenessForWorker(workerId: payload.workerId)
        guard !workerAliveness.registered || workerAliveness.silent else {
            throw WorkerRegistrarError.workerIsAlreadyRegistered(workerId: payload.workerId)
        }
        workerAlivenessProvider.didRegisterWorker(workerId: payload.workerId)
        logger.debug("Worker \(payload.workerId) has acceptable status")
        workerDetailsHolder.update(
            workerId: payload.workerId,
            restAddress: payload.workerRestAddress
        )
        return .workerRegisterSuccess(workerConfiguration: workerConfiguration)
    }
}
