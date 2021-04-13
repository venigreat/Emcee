import Deployer
import Foundation

public final class DeploymentDestinationFixtures {
    
    public var host: String = "localhost"
    public var port: Int32 = 42
    public var username: String = "username"
    public var key: String = "~/.ssh/key_name"
    public var remoteDeploymentPath: String = "/Users/username/path"
    
    public init() {}
    
    public func with(host: String) -> DeploymentDestinationFixtures {
        self.host = host
        return self
    }
    
    public func with(port: Int32) -> DeploymentDestinationFixtures {
        self.port = port
        return self
    }
    
    public func with(username: String) -> DeploymentDestinationFixtures {
        self.username = username
        return self
    }
    
    public func with(key: String) -> DeploymentDestinationFixtures {
        self.key = key
        return self
    }
    
    public func with(remoteDeploymentPath: String) -> DeploymentDestinationFixtures {
        self.remoteDeploymentPath = remoteDeploymentPath
        return self
    }
    
    public func build() -> DeploymentDestination {
        return DeploymentDestination(
            host: host,
            port: port,
            username: username,
            key: key,
            remoteDeploymentPath: remoteDeploymentPath
        )
    }
}
