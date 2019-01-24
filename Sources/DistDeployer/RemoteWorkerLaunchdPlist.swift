import Deployer
import Foundation
import LaunchdUtils
import Models
import SSHDeployer

public final class RemoteWorkerLaunchdPlist {
    
    private let deploymentId: String
    private let deploymentDestination: DeploymentDestination
    private let executableDeployableItem: DeployableItem
    private let queueAddress: SocketAddress

    public init(
        deploymentId: String,
        deploymentDestination: DeploymentDestination,
        executableDeployableItem: DeployableItem,
        queueAddress: SocketAddress)
    {
        self.deploymentId = deploymentId
        self.deploymentDestination = deploymentDestination
        self.executableDeployableItem = executableDeployableItem
        self.queueAddress = queueAddress
    }
    
    public func plistData() throws -> Data {
        let containerPath = SSHDeployer.remoteContainerPath(
            forDeployable: executableDeployableItem,
            destination: deploymentDestination,
            deploymentId: deploymentId
        )
        let emceeDeployableBinaryFile = try DeployableItemSingleFileExtractor(deployableItem: executableDeployableItem).singleDeployableFile()
        let workerBinaryRemotePath = SSHDeployer.remotePath(
            deployable: executableDeployableItem,
            file: emceeDeployableBinaryFile,
            destination: deploymentDestination,
            deploymentId: deploymentId
        )
        let jobLabel = "ru.avito.emcee.worker.\(deploymentId.removingWhitespaces())"
        let launchdPlist = LaunchdPlist(
            job: LaunchdJob(
                label: jobLabel,
                programArguments: [
                    workerBinaryRemotePath, "distWork",
                    "--queue-server", queueAddress.asString,
                    "--worker-id", deploymentDestination.identifier
                ],
                environmentVariables: [:],
                workingDirectory: containerPath,
                runAtLoad: true,
                disabled: true,
                standardOutPath: containerPath.appending(pathComponent: "stdout.log"),
                standardErrorPath: containerPath.appending(pathComponent: "stderr.log"),
                sockets: [:],
                inetdCompatibility: .disabled,
                sessionType: .background
            )
        )
        return try launchdPlist.createPlistData()
    }
    
}