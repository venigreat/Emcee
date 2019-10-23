import DeveloperDirLocator
import Dispatch
import Foundation
import Logging
import Models
import PathLib
import ProcessController
import ResourceLocationResolver
import SimulatorPool

public final class SimctlBasedSimulatorStateMachineActionExecutor: SimulatorStateMachineActionExecutor, CustomStringConvertible {

    public init() {}
    
    public var description: String {
        return "simctl"
    }
    
    public func performCreateSimulatorAction(
        environment: [String: String],
        simulatorSetPath: AbsolutePath,
        testDestination: TestDestination
    ) throws {
        let controller = try ProcessController(
            subprocess: Subprocess(
                arguments: [
                    "/usr/bin/xcrun", "simctl",
                    "--set", simulatorSetPath,
                    "create",
                    "Emcee Sim \(testDestination.deviceType) \(testDestination.runtime)",
                    "com.apple.CoreSimulator.SimDeviceType." + testDestination.deviceType.replacingOccurrences(of: " ", with: "."),
                    "com.apple.CoreSimulator.SimRuntime.iOS-" + testDestination.runtime.replacingOccurrences(of: ".", with: "-")
                ],
                environment: environment,
                silenceBehavior: SilenceBehavior(
                    automaticAction: .interruptAndForceKill,
                    allowedSilenceDuration: 30
                )
            )
        )
        controller.startAndListenUntilProcessDies()
    }
    
    public func performBootSimulatorAction(
        environment: [String: String],
        simulatorSetPath: AbsolutePath,
        simulatorUuid: String
    ) throws {
        let processController = try ProcessController(
            subprocess: Subprocess(
                arguments: [
                    "/usr/bin/xcrun", "simctl",
                    "--set", simulatorSetPath,
                    "bootstatus", simulatorUuid,
                    "-bd"
                ],
                environment: environment
            )
        )
        processController.startAndListenUntilProcessDies()
    }
    
    public func performShutdownSimulatorAction(
        environment: [String: String],
        simulatorSetPath: AbsolutePath,
        simulatorUuid: String
    ) throws {
        let shutdownController = try ProcessController(
            subprocess: Subprocess(
                arguments: [
                    "/usr/bin/xcrun", "simctl",
                    "--set", simulatorSetPath,
                    "shutdown", simulatorUuid
                ],
                environment: environment,
                silenceBehavior: SilenceBehavior(
                    automaticAction: .interruptAndForceKill,
                    allowedSilenceDuration: 20
                )
            )
        )
        shutdownController.startAndListenUntilProcessDies()
    }
    
    public func performDeleteSimulatorAction(
        environment: [String: String],
        simulatorSetPath: AbsolutePath,
        simulatorUuid: String
    ) throws {
        let deleteController = try ProcessController(
            subprocess: Subprocess(
                arguments: [
                    "/usr/bin/xcrun", "simctl",
                    "--set", simulatorSetPath,
                    "delete", simulatorUuid
                ],
                environment: environment,
                silenceBehavior: SilenceBehavior(
                    automaticAction: .interruptAndForceKill,
                    allowedSilenceDuration: 15
                )
            )
        )
        deleteController.startAndListenUntilProcessDies()
    }
}