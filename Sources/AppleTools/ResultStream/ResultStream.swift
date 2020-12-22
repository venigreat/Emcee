import DateProvider
import Foundation
import JSONStream
import Logging
import PathLib
import Runner
import RunnerModels

public protocol ResultStream {
    func streamContents(
        completion: @escaping (Error?) -> ()
    )
}

public final class ResultStreamImpl: ResultStream {
    private let dateProvider: DateProvider
    private let queue = DispatchQueue(label: "queue")
    private let testRunnerStream: TestRunnerStream
    private let jsonStream = BlockingArrayBasedJSONStream()
    
    public init(
        dateProvider: DateProvider,
        testRunnerStream: TestRunnerStream
    ) {
        self.dateProvider = dateProvider
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

class JsonToResultStreamEventStream: JSONReaderEventStream {
    private let jsonDecoder = JSONDecoder()
    private let testRunnerStream: TestRunnerStream
    private let dateProvider: DateProvider
    
    init(
        dateProvider: DateProvider,
        testRunnerStream: TestRunnerStream
    ) {
        self.dateProvider = dateProvider
        self.testRunnerStream = testRunnerStream
    }
    
    func newArray(_ array: NSArray, bytes: [UInt8]) {
        Logger.debug("Skipped xcresultstream event: array is an unexpected kind of root object")
    }
    
    func newObject(_ object: NSDictionary, bytes: [UInt8]) {
        guard let name = object["name"] as? NSDictionary, let eventName = name["_value"] as? String else {
            return
        }
        
        do {
            switch eventName {
            case RSTestStarted.name.stringValue:
                let testStarted = try jsonDecoder.decode(RSTestStarted.self, from: Data(bytes))
                let testName = try testStarted.structuredPayload.testIdentifier.testName()
                testRunnerStream.testStarted(testName: testName)
            case RSTestFinished.name.stringValue:
                let testFinished = try jsonDecoder.decode(RSTestFinished.self, from: Data(bytes))
                let testStoppedEvent = try testFinished.testStoppedEvent(dateProvider: dateProvider)
                testRunnerStream.testStopped(testStoppedEvent: testStoppedEvent)
            case RSIssueEmitted.name.stringValue:
                let issue = try jsonDecoder.decode(RSIssueEmitted.self, from: Data(bytes))
                let testException = issue.structuredPayload.issue.testException()
                testRunnerStream.caughtException(testException: testException)
            default:
                break
            }
        } catch {
            Logger.error("Failed to parse result stream error for \(eventName) event: \(error)")
        }
    }
}

extension Array where Element == Unicode.Scalar {
    func data() -> Data {
        let bytes: [UInt8] = flatMap { element -> [UInt8] in
            let fourBytes: UInt32 = element.value.bigEndian
            let bytes = Swift.withUnsafeBytes(of: fourBytes, [UInt8].init)
            return bytes
        }
        return Data(bytes)
    }
}

extension RSActionTestSummaryIdentifiableObject {
    func testName() throws -> TestName {
        let result = identifier
            .stringValue
            .replacingOccurrences(of: "()", with: "")
            .replacingOccurrences(of: "/", with: " ")
        return try TestName.parseObjCTestName(string: "-[" + result + "]")
    }
}

extension RSTestFinished {
    func testStoppedEvent(
        dateProvider: DateProvider
    ) throws -> TestStoppedEvent {
        let testDuration = structuredPayload.test.duration?.doubleValue ?? 0.0
        return TestStoppedEvent(
            testName: try structuredPayload.test.testName(),
            result: structuredPayload.test.testStatus == "Success" ? .success : .failure,
            testDuration: testDuration,
            testExceptions: [],
            testStartTimestamp: dateProvider.currentDate().addingTimeInterval(-testDuration).timeIntervalSince1970
        )
    }
}

extension RSTestFailureIssueSummary {
    func testException() -> TestException {
        let fileLine = documentLocationInCreatingWorkspace.fileLine()
        return TestException(
            reason: message.stringValue,
            filePathInProject: fileLine.file,
            lineNumber: Int32(fileLine.line)
        )
    }
}

extension RSDocumentLocation {
    func fileLine() -> (file: String, line: Int) {
        let unknownResult = (file: "unknown", line: 0)
        
        // file:///path/to/file.swift#CharacterRangeLen=0&EndingLineNumber=118&StartingLineNumber=118
        guard
            let url = URL(string: url.stringValue),
            let fragment = url.fragment
        else { return unknownResult }
        
        let pairs: [(String, String)] = fragment
            .split(separator: "&")
            .map { $0.split(separator: "=") }
            .compactMap {
                guard $0.count == 2 else { return nil }
                return (String($0[0]), String($0[1]))
            }
        let dict = [String: String](uniqueKeysWithValues: pairs)
        
        guard let startingLineNumber = dict["StartingLineNumber"], let line = Int(startingLineNumber) else {
            return unknownResult
        }
        
        return (file: url.path, line: line)
    }
}
