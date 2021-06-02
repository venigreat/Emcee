import Foundation

public struct AnalyticsConfiguration: Codable, Hashable {
    public let graphiteConfiguration: MetricConfiguration?
    public let statsdConfiguration: MetricConfiguration?
    public let kibanaConfiguration: KibanaConfiguration?
    
    public let persistentMetricsJobId: String?
    public let metadata: [String: String]?

    public init(
        graphiteConfiguration: MetricConfiguration? = nil,
        statsdConfiguration: MetricConfiguration? = nil,
        kibanaConfiguration: KibanaConfiguration? = nil,
        persistentMetricsJobId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.graphiteConfiguration = graphiteConfiguration
        self.statsdConfiguration = statsdConfiguration
        self.kibanaConfiguration = kibanaConfiguration
        self.persistentMetricsJobId = persistentMetricsJobId
        self.metadata = metadata
    }
}
