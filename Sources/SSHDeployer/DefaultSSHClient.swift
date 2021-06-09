import Foundation
import Shout
import PathLib

public final class DefaultSSHClient: SSHClient {
    private let ssh: SSH
    private let host: String
    private let port: Int32
    private let username: String
    private let password: String?
    private let key: String?
    
    public init(host: String, port: Int32, username: String, password: String?, key: String?) throws {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.key = key
        self.ssh = try SSH(host: host, port: port)
    }

    public func connectAndAuthenticate() throws {
        if let password = password {
            try ssh.authenticate(username: username, password: password)
        } else if let key = key {
            try ssh.authenticate(username: username, privateKey: key)
        } else {
            fatalError("Connection to \(host) has no password or privateKey")
        }
        
    }
    
    @discardableResult
    public func execute(_ command: [String]) throws -> Int32 {
        let shellCommand = command.map { $0.shellEscaped() }.joined(separator: " ")
        return try ssh.execute(shellCommand) { _ in }
    }
    
    public func upload(localUrl: URL, remotePath: String) throws {
        try ssh.openSftp().upload(localURL: localUrl, remotePath: remotePath)
    }
}
