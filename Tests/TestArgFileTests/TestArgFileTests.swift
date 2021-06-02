import BuildArtifacts
import Foundation
import LoggingSetup
import MetricsExtensions
import QueueModels
import ResourceLocation
import SimulatorPoolModels
import SocketModels
import TestArgFile
import XCTest

final class TestArgFileTests: XCTestCase {
    func test___decoding_full_json() throws {
        let json = Data(
            """
            {
                "entries": [],
                "jobGroupId": "jobGroupId",
                "jobGroupPriority": 100,
                "jobId": "jobId",
                "jobPriority": 500,
                "testDestinationConfigurations": [],
                "analyticsConfiguration": {
                    "graphiteConfiguration": {
                        "socketAddress": "graphite.host:123",
                        "metricPrefix": "graphite.prefix",
                    },
                    "statsdConfiguration": {
                        "socketAddress": "statsd.host:124",
                        "metricPrefix": "statsd.prefix",
                    },
                    "kibanaConfiguration": {
                        "endpoints": [
                            "http://kibana.example.com:9200"
                        ],
                        "indexPattern": "index-pattern"
                    },
                    "persistentMetricsJobId": "persistentMetricsJobId",
                    "metadata": {
                        "some": "value"
                    }
                }
            }
            """.utf8
        )
        
        let testArgFile = assertDoesNotThrow {
            try JSONDecoder().decode(TestArgFile.self, from: json)
        }

        XCTAssertEqual(
            testArgFile,
            TestArgFile(
                entries: [],
                prioritizedJob: PrioritizedJob(
                    analyticsConfiguration: AnalyticsConfiguration(
                        graphiteConfiguration: MetricConfiguration(
                            socketAddress: SocketAddress(host: "graphite.host", port: 123),
                            metricPrefix: "graphite.prefix"
                        ),
                        statsdConfiguration: MetricConfiguration(
                            socketAddress: SocketAddress(host: "statsd.host", port: 124),
                            metricPrefix: "statsd.prefix"
                        ),
                        kibanaConfiguration: KibanaConfiguration(
                            endpoints: [
                                URL(string: "http://kibana.example.com:9200")!
                            ],
                            indexPattern: "index-pattern"
                        ),
                        persistentMetricsJobId: "persistentMetricsJobId",
                        metadata: ["some": "value"]
                    ),
                    jobGroupId: "jobGroupId",
                    jobGroupPriority: 100,
                    jobId: "jobId",
                    jobPriority: 500
                ),
                testDestinationConfigurations: []
            )
        )
    }
    
    func test___decoding_short_json() throws {
        let json = Data(
            """
            {
                "entries": [],
                "jobId": "jobId",
            }
            """.utf8
        )
        
        let testArgFile = assertDoesNotThrow {
            try JSONDecoder().decode(TestArgFile.self, from: json)
        }

        XCTAssertEqual(
            testArgFile,
            TestArgFile(
                entries: [],
                prioritizedJob: PrioritizedJob(
                    analyticsConfiguration: TestArgFileDefaultValues.analyticsConfiguration,
                    jobGroupId: "jobId",
                    jobGroupPriority: TestArgFileDefaultValues.priority,
                    jobId: "jobId",
                    jobPriority: TestArgFileDefaultValues.priority
                ),
                testDestinationConfigurations: []
            )
        )
    }
    
    func test___complete_short_example() throws {
        let json = Data(
            """
            {
                "jobId": "jobId",
                "entries": [
                    {
                        "testsToRun": ["all"],
                        "testDestination": {"deviceType": "iPhone X", "runtime": "11.3"},
                        "testType": "uiTest",
                        "buildArtifacts": {
                            "appBundle": "http://example.com/App.zip#MyApp/MyApp.app",
                            "runner": "http://example.com/App.zip#Tests/UITests-Runner.app",
                            "xcTestBundle": "http://example.com/App.zip#Tests/UITests-Runner.app/PlugIns/UITests.xctest"
                        }
                    }
                ]
            }
            """.utf8
        )
        
        let testArgFile = assertDoesNotThrow {
            try JSONDecoder().decode(TestArgFile.self, from: json)
        }

        XCTAssertEqual(testArgFile.prioritizedJob.jobId, "jobId")
        XCTAssertEqual(testArgFile.entries.count, 1)
        XCTAssertEqual(testArgFile.entries[0].testsToRun, [.allDiscoveredTests])
        XCTAssertEqual(testArgFile.entries[0].testDestination, try TestDestination(deviceType: "iPhone X", runtime: "11.3"))
        XCTAssertEqual(testArgFile.entries[0].testType, .uiTest)
        XCTAssertEqual(
            testArgFile.entries[0].buildArtifacts,
            BuildArtifacts(
                appBundle: AppBundleLocation(try .from("http://example.com/App.zip#MyApp/MyApp.app")),
                runner: RunnerAppLocation(try .from("http://example.com/App.zip#Tests/UITests-Runner.app")),
                xcTestBundle: XcTestBundle(
                    location: TestBundleLocation(try .from("http://example.com/App.zip#Tests/UITests-Runner.app/PlugIns/UITests.xctest")),
                    testDiscoveryMode: .parseFunctionSymbols
                ),
                additionalApplicationBundles: []
            )
        )
    }
}

