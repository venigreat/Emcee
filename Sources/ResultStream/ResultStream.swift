import DateProvider
import Foundation
import JSONStream
import EmceeLogging
import PathLib
import Runner

public protocol ResultStream {
    func streamContents(
        completion: @escaping (Error?) -> ()
    )
}

public final class ResultStreamImpl: ResultStream {
    private let dateProvider: DateProvider
    private let logger: ContextualLogger
    private let queue = DispatchQueue(label: "queue")
    private let testRunnerStream: TestRunnerStream
    private let jsonStream = BlockingArrayBasedJSONStream()
    
    public init(
        dateProvider: DateProvider,
        logger: ContextualLogger,
        testRunnerStream: TestRunnerStream
    ) {
        self.dateProvider = dateProvider
        self.logger = logger
        self.testRunnerStream = testRunnerStream
    }
    
    public func write(data: Data) {
        jsonStream.append(data: data)
    }
    
    public func close() {
        jsonStream.close()
    }
    
    public func streamContents(
        completion: @escaping (Error?) -> ()
    ) {
        let eventStream = JsonToResultStreamEventStream(
            dateProvider: dateProvider,
            logger: logger,
            testRunnerStream: testRunnerStream
        )
        let jsonReader = JSONReader(
            inputStream: jsonStream,
            eventStream: eventStream
        )
        queue.async {
            do {
                try jsonReader.start()
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }
}
