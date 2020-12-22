import Foundation

public protocol AppendableJSONStream: JSONStream {
    func append(scalars: [UInt8])
}

public extension AppendableJSONStream {
    func append(data: Data) {
        let bytes = [UInt8](data)
        append(scalars: bytes)
    }
    
    func append(string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data: data)
    }
}
