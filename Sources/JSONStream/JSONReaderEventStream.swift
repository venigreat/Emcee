import Foundation

public protocol JSONReaderEventStream {
    /** Called when JSON reader consumes a root JSON array. */
    func newArray(_ array: NSArray, bytes: [UInt8])
    /** Called when JSON reader consumes a root JSON object. */
    func newObject(_ object: NSDictionary, bytes: [UInt8])
}
