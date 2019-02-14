import Foundation

public final class DSN: Equatable, CustomStringConvertible {
    public let storeUrl: URL
    public let publicKey: String
    public let secretKey: String
    public let projectId: String
    
    private static func projectId(from url: URL) -> String? {
        return url.pathComponents.dropFirst().first
    }
    
    public init(
        storeUrl: URL,
        publicKey: String,
        secretKey: String,
        projectId: String)
    {
        self.storeUrl = storeUrl
        self.publicKey = publicKey
        self.secretKey = secretKey
        self.projectId = projectId
    }
    
    public var description: String {
        return "<DSN: \(publicKey):\(secretKey) \(projectId)>"
    }
    
    public static func takeFromEnv(envName: String) throws -> DSN {
        guard let sentryDsnEnv = ProcessInfo.processInfo.environment[envName] else {
            throw DSNError.envIsNotSet(envName)
        }
        return try create(dsnString: sentryDsnEnv)
    }
    
    public static func create(dsnString: String) throws -> DSN {
        guard let url = URL(string: dsnString), let projectId = DSN.projectId(from: url) else {
            throw DSNError.incorrectValue(dsnString)
        }
        guard let publicKey = url.user else {
            throw DSNError.missingPublicKey
        }
        guard let privateKey = url.password else {
            throw DSNError.missingPrivateKey
        }
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/api/\(projectId)/store/"
        guard let storeUrl = components.url else {
            throw DSNError.unableToConstructStoreUrl(dsnString)
        }
        
        return DSN(
            storeUrl: storeUrl,
            publicKey: publicKey,
            secretKey: privateKey,
            projectId: projectId
        )
    }
    
    public static func == (left: DSN, right: DSN) -> Bool {
        return left.storeUrl == right.storeUrl
            && left.publicKey == right.publicKey
            && left.secretKey == right.secretKey
            && left.projectId == right.projectId
    }
}
