import Foundation
import JSONStream

class FakeJSONStream: JSONStream {
    var data: [UInt8]
    var isClosed = false
    
    public init(string: String) {
        let stringData = string.data(using: .utf8) ?? Data()
        data = [UInt8](stringData).reversed()
    }
    
    func read() -> UInt8? {
        guard let last = data.last else { return nil }
        data.removeLast()
        return last
    }
    
    func touch() -> UInt8? {
        return data.last
    }
    
    func close() {
        isClosed = true
    }
}

class FakeEventStream: JSONReaderEventStream {
    var all = [NSObject]()
    var allObjects = [NSDictionary]()
    var allArrays = [NSArray]()
    var allBytes = [[UInt8]]()
    
    public init() {}
    
    func newArray(_ array: NSArray, bytes: [UInt8]) {
        all.append(array)
        allArrays.append(array)
        allBytes.append(bytes)
    }
    
    func newObject(_ object: NSDictionary, bytes: [UInt8]) {
        all.append(object)
        allObjects.append(object)
        allBytes.append(bytes)
    }
}
