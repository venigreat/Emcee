import DI
import DateProvider
import DeveloperDirLocator
import EmceeLogging
import FileSystem
import Foundation
import Metrics
import ProcessController
import QueueModels
import ResourceLocationResolver
import SimulatorPool
import SimulatorPoolModels
import Tmp
import UniqueIdentifierGenerator

public final class OnDemandSimulatorPoolFactory {
    public static func create(
        di: DI,
        logger: ContextualLogger,
        simulatorBootQueue: DispatchQueue = DispatchQueue(label: "SimulatorBootQueue"),
        version: Version
    ) throws -> OnDemandSimulatorPool {
        DefaultOnDemandSimulatorPool(
            logger: logger,
            resourceLocationResolver: try di.get(),
            simulatorControllerProvider: DefaultSimulatorControllerProvider(
                additionalBootAttempts: 2,
                developerDirLocator: try di.get(),
                logger: logger,
                simulatorBootQueue: simulatorBootQueue,
                simulatorStateMachineActionExecutorProvider: SimulatorStateMachineActionExecutorProviderImpl(
                    dateProvider: try di.get(),
                    processControllerProvider: try di.get(),
                    resourceLocationResolver: try di.get(),
                    simulatorSetPathDeterminer: SimulatorSetPathDeterminerImpl(
                        fileSystem: try di.get(),
                        temporaryFolder: try di.get(),
                        uniqueIdentifierGenerator: try di.get()
                    ),
                    version: version,
                    globalMetricRecorder: try di.get()
                )
            ),
            tempFolder: try di.get()
        )
    }
}
