@testable import Deployer
@testable import SSHDeployer
import Foundation
import PathLib
import ProcessControllerTestHelpers
import Tmp
import TestHelpers
import UniqueIdentifierGeneratorTestHelpers
import XCTest

class SSHDeployerTests: XCTestCase {
    private let uniqueIdentifierGenerator = FixedValueUniqueIdentifierGenerator(value: "fixed")
    private lazy var tempFolder = assertDoesNotThrow { try TemporaryFolder() }
    
    func testForInputCorrectness() throws {
        let deploymentId = UUID().uuidString
        let deployableWithSingleFile = DeployableItem(
            name: "deployable_name",
            files: [
                DeployableFile(source: AbsolutePath(#file), destination: RelativePath(components: ["remote", "file.swift"]))
            ])
        let destination = DeploymentDestination(
            host: "host",
            port: 1034,
            username: "user",
            key: "key",
            remoteDeploymentPath: "/some/remote/container")
        
        let deployer = try SSHDeployer(
            sshClientType: FakeSSHClient.self,
            deploymentId: deploymentId,
            deployables: [deployableWithSingleFile],
            deployableCommands: [
                [
                    "string_arg",
                    .item(deployableWithSingleFile, relativePath: "remote/file.swift")
                ]
            ],
            destination: destination,
            logger: .noOp,
            processControllerProvider: FakeProcessControllerProvider(),
            temporaryFolder: tempFolder,
            uniqueIdentifierGenerator: uniqueIdentifierGenerator
        )
        try deployer.deploy()
        
        guard let client = FakeSSHClient.lastCreatedInstance else {
            XCTFail("Expected FakeSSHClient.lastCreatedInstance to be non nil as instance should be created")
            return
        }
        
        XCTAssertEqual(client.host, destination.host)
        XCTAssertEqual(client.port, destination.port)
        XCTAssertEqual(client.username, destination.username)
        XCTAssertEqual(client.key, destination.key)
        XCTAssertTrue(client.calledConnectAndAuthenticate)
        
        XCTAssertEqual(client.executeCommands.count, 4)
        XCTAssertEqual(
            client.executeCommands[0],
            ["rm", "-rf", "\(destination.remoteDeploymentPath)/\(deploymentId)/deployable_name"])
        XCTAssertEqual(
            client.executeCommands[1],
            ["mkdir", "-p", "\(destination.remoteDeploymentPath)/\(deploymentId)/deployable_name"])
        
        XCTAssertEqual(client.uploadCommands.count, 1)
        let uploadCommand = client.uploadCommands[0]
        
        XCTAssertEqual(
            Array(uploadCommand.keys),
            [tempFolder.pathWith(components: ["fixed", "deployable_name.zip"]).fileUrl]
        )
        XCTAssertEqual(
            Array(uploadCommand.values),
            ["/some/remote/container/\(deploymentId)/deployable_name/_package.zip"])
        
        XCTAssertEqual(
            client.executeCommands[2],
            ["unzip", "\(destination.remoteDeploymentPath)/\(deploymentId)/deployable_name/_package.zip",
                "-d", "\(destination.remoteDeploymentPath)/\(deploymentId)/deployable_name"])
        XCTAssertEqual(
            client.executeCommands[3],
            ["string_arg", "/some/remote/container/\(deploymentId)/deployable_name/remote/file.swift"])
    }
}
