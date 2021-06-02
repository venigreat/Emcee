import AutomaticTermination
import Deployer
import Foundation
import LocalQueueServerRunner
import MetricsExtensions
import LoggingSetup
import QueueModels
import SocketModels
import XCTest

final class QueueServerConfigurationTests: XCTestCase {
    func test___parsing() throws {
        let data = Data(
            """
                {
                  "globalAnalyticsConfiguration": {
                    "graphiteConfiguration": {
                      "socketAddress": "host:123",
                      "metricPrefix": "graphite.prefix"
                    },
                    "statsdConfiguration": {
                      "socketAddress": "host:123",
                      "metricPrefix": "statsd.prefix"
                    }
                  },
                  "workerSpecificConfigurations": {
                    "worker_1": {
                      "numberOfSimulators": 1
                    },
                    "worker_2": {
                      "numberOfSimulators": 2
                    },
                    "worker_3": {
                      "numberOfSimulators": 3
                    }
                  },
                  "queueServerDeploymentDestination": {
                    "host": "queue",
                    "port": 22,
                    "username": "q_user",
                    "key": "q_key",
                    "remoteDeploymentPath": "/remote/queue/depl/path"
                  },
                  "queueServerTerminationPolicy": {
                    "caseId": "stayAlive"
                  },
                  "checkAgainTimeInterval": 22,
                  "workerDeploymentDestinations": [
                    {
                      "host": "host",
                      "port": 1,
                      "username": "username",
                      "key": "key",
                      "remoteDeploymentPath": "/remote/deployment/path"
                    }
                  ]
                }
            """.utf8
        )
        
        let config = try JSONDecoder().decode(QueueServerConfiguration.self, from: data)
        XCTAssertEqual(
            config.globalAnalyticsConfiguration,
            AnalyticsConfiguration(
                graphiteConfiguration: MetricConfiguration(socketAddress: SocketAddress(host: "host", port: 123), metricPrefix: "graphite.prefix"),
                statsdConfiguration: MetricConfiguration(socketAddress: SocketAddress(host: "host", port: 123), metricPrefix: "statsd.prefix")
            )
        )
        XCTAssertEqual(
            config.workerSpecificConfigurations,
            [
                WorkerId("worker_1"): WorkerSpecificConfiguration(numberOfSimulators: 1),
                WorkerId("worker_2"): WorkerSpecificConfiguration(numberOfSimulators: 2),
                WorkerId("worker_3"): WorkerSpecificConfiguration(numberOfSimulators: 3),
            ]
        )
        XCTAssertEqual(
            config.queueServerDeploymentDestination,
            DeploymentDestination(host: "queue", port: 22, username: "q_user", key: "q_key", remoteDeploymentPath: "/remote/queue/depl/path")
        )
        XCTAssertEqual(
            config.queueServerTerminationPolicy,
            AutomaticTerminationPolicy.stayAlive
        )
        XCTAssertEqual(
            config.checkAgainTimeInterval,
            22
        )
        XCTAssertEqual(
            config.workerDeploymentDestinations,
            [
                DeploymentDestination(host: "host", port: 1, username: "username", key: "key", remoteDeploymentPath: "/remote/deployment/path")
            ]
        )
    }
}
