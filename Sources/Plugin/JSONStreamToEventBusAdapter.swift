import EventBus
import Foundation
import JSONStream
import Logging

final class JSONStreamToEventBusAdapter: JSONReaderEventStream {
    private let eventBus: EventBus
    private let decoder = JSONDecoder()
    
    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }
    
    func newArray(_ array: NSArray, bytes: [UInt8]) {
        let context = String(data: Data(bytes), encoding: .utf8)
        Logger.error("JSON stream reader received an unexpected event: '\(String(describing: context))'")
    }
    
    func newObject(_ object: NSDictionary, bytes: [UInt8]) {
        let eventData = Data(bytes)
        
        do {
            let busEvent = try decoder.decode(BusEvent.self, from: eventData)
            eventBus.post(event: busEvent)
        } catch {
            let context = String(data: Data(bytes), encoding: .utf8)
            Logger.error("Failed to decode plugin event: \(error)")
            Logger.debug("JSON String: \(String(describing: context))")
        }
    }
}
