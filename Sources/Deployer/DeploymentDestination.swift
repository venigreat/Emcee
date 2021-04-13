import Foundation
import QueueModels

public struct DeploymentDestination: Codable, CustomStringConvertible, Hashable {
    public let workerId: WorkerId
    public let host: String
    public let port: Int32
    public let username: String
    public let key: String
    public let remoteDeploymentPath: String
    
    enum CodingKeys: String, CodingKey {
        case host
        case port
        case username
        case key
        case remoteDeploymentPath
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let host = try container.decode(String.self, forKey: .host)
        let port = try container.decode(Int32.self, forKey: .port)
        let username = try container.decode(String.self, forKey: .username)
        let key = try container.decode(String.self, forKey: .key)
        let remoteDeploymentPath = try container.decode(String.self, forKey: .remoteDeploymentPath)
        
        self.init(
            host: host,
            port: port,
            username: username,
            key: key,
            remoteDeploymentPath: remoteDeploymentPath)
    }

    public init(
        host: String,
        port: Int32,
        username: String,
        key: String,
        remoteDeploymentPath: String)
    {
        self.workerId = WorkerId(value: host)
        self.host = host
        self.port = port
        self.username = username
        self.key = key
        self.remoteDeploymentPath = remoteDeploymentPath
    }
    
    public var description: String {
        return "<\(type(of: self)) host: \(host)>"
    }
}
