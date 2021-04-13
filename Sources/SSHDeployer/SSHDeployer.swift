import Deployer
import Foundation
import Logging
import PathLib
import ProcessController
import TemporaryStuff
import UniqueIdentifierGenerator

public final class SSHDeployer: Deployer {
    
    private let sshClientType: SSHClient.Type
    
    public init(
        sshClientType: SSHClient.Type,
        deploymentId: String,
        deployables: [DeployableItem],
        deployableCommands: [DeployableCommand],
        destination: DeploymentDestination,
        processControllerProvider: ProcessControllerProvider,
        temporaryFolder: TemporaryFolder,
        uniqueIdentifierGenerator: UniqueIdentifierGenerator
    ) throws {
        self.sshClientType = sshClientType
        try super.init(
            deploymentId: deploymentId,
            deployables: deployables,
            deployableCommands: deployableCommands,
            destination: destination,
            processControllerProvider: processControllerProvider,
            temporaryFolder: temporaryFolder,
            uniqueIdentifierGenerator: uniqueIdentifierGenerator
        )
    }
    
    override public func deployToDestination(
        pathToDeployable: [AbsolutePath: DeployableItem]
    ) throws {
        do {
            try deploy(pathToDeployable: pathToDeployable)
        } catch let error {
            SSHDeployer.log(destination, "Failed to deploy to this destination with error: \(error)")
        }
    }
    
    /**
     * Returns a remote path at remote destination which will contain all deployed contents for the given deployable.
     */
    public static func remoteContainerPath(
        forDeployable deployable: DeployableItem,
        destination: DeploymentDestination,
        deploymentId: String
    ) -> AbsolutePath {
        return AbsolutePath(destination.remoteDeploymentPath)
            .appending(components: [deploymentId, deployable.name])
    }
    
    public static func remotePath(
        deployable: DeployableItem,
        file: DeployableFile,
        destination: DeploymentDestination,
        deploymentId: String
    ) -> AbsolutePath {
        let container = remoteContainerPath(
            forDeployable: deployable,
            destination: destination,
            deploymentId: deploymentId
        )
        return container.appending(relativePath: file.destination)
    }
    
    // MARK: - Private - Deploy
    
    private func deploy(
        pathToDeployable: [AbsolutePath: DeployableItem]
    ) throws {
        SSHDeployer.log(destination, "Connecting")
        let sshClient = try self.sshClientType.init(
            host: destination.host,
            port: destination.port,
            username: destination.username,
            key: destination.key
        )
        try sshClient.connectAndAuthenticate()
        SSHDeployer.log(destination, "Connected and authenticated")
        
        try pathToDeployable.forEach { (absolutePath: AbsolutePath, deployable: DeployableItem) in
            let remoteDeploymentPath = SSHDeployer.remoteContainerPath(
                forDeployable: deployable,
                destination: destination,
                deploymentId: deploymentId
            )
            try sshClient.execute(["rm", "-rf", remoteDeploymentPath.pathString])
            try sshClient.execute(["mkdir", "-p", remoteDeploymentPath.pathString])
            let remotePackagePath = remoteDeploymentPath.appending(component: "_package.zip")
            
            try uploadFile(
                sshClient: sshClient,
                destination: destination,
                localAbsolutePath: absolutePath,
                remoteAbsolutePath: remotePackagePath
            )
            
            try deployPackageRemotely(
                sshClient: sshClient,
                destination: destination,
                deployable: deployable,
                remotePackagePath: remotePackagePath,
                remoteDeploymentPath: remoteDeploymentPath
            )
        }
        
        try invokeCommands(
            sshClient: sshClient,
            destination: destination
        )
        
        SSHDeployer.log(destination, "Finished deploying")
    }
    
    private func uploadFile(
        sshClient: SSHClient,
        destination: DeploymentDestination,
        localAbsolutePath: AbsolutePath,
        remoteAbsolutePath: AbsolutePath
    ) throws {
        SSHDeployer.log(destination, "Uploading \(localAbsolutePath) -> \(remoteAbsolutePath)")
        try sshClient.upload(localUrl: localAbsolutePath.fileUrl, remotePath: remoteAbsolutePath.pathString)
        SSHDeployer.log(destination, "Uploaded \(localAbsolutePath) -> \(remoteAbsolutePath)")
    }
    
    private func deployPackageRemotely(
        sshClient: SSHClient,
        destination: DeploymentDestination,
        deployable: DeployableItem,
        remotePackagePath: AbsolutePath,
        remoteDeploymentPath: AbsolutePath
    ) throws {
        SSHDeployer.log(destination, "Deploying '\(deployable.name)'")
        try sshClient.execute(["unzip", remotePackagePath.pathString, "-d", remoteDeploymentPath.pathString])
        SSHDeployer.log(destination, "Deployed '\(deployable.name)'")
    }
    
    // MARK: - Private - Command Invocatoin
    
    private func invokeCommands(sshClient: SSHClient, destination: DeploymentDestination) throws {
        for command in deployableCommands {
            let commandArgs: [String] = command.commandArgs.map { (arg: DeployableCommandArg) in
                switch arg {
                case let .string(value):
                    return value
                case .item(let deployableItem, let relativePath):
                    var remotePath = SSHDeployer.remoteContainerPath(
                        forDeployable: deployableItem,
                        destination: destination,
                        deploymentId: deploymentId)
                    if let additionalPath = relativePath {
                        remotePath = remotePath.appending(component: additionalPath)
                    }
                    return remotePath.pathString
                }
            }
            SSHDeployer.log(destination, "Executing command: \(command)")
            try sshClient.execute(commandArgs)
            SSHDeployer.log(destination, "Executed command")
        }
    }
    
    // MARK: - Private - Logging

    private static func log(
        _ destination: DeploymentDestination,
        _ text: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        Logger.debug("\(destination.host): \(text)", file: file, line: line)
    }
}
