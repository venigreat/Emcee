import Foundation
import Extensions

final class TestingPluginExecutable {
    private static let swiftPackagePath = FileManager.default.walkUpTheHierarchy(
        path: #file,
        untilFileIsFound: "Package.swift")
    
    public static let testingPluginPath: String? = buildTestingPlugin()
    
    private static func buildTestingPlugin() -> String? {
        guard let swiftPackagePath = TestingPluginExecutable.swiftPackagePath else {
            return nil
        }
        
        let process = Process.launchedProcess(
            launchPath: "/usr/bin/swift",
            arguments: [
                "build",
                "--package-path", swiftPackagePath,
                "--product", "testing_plugin"
            ])
        process.waitUntilExit()
        let location = swiftPackagePath.appending(pathComponents: [".build", "debug", "testing_plugin"])
        if FileManager.default.fileExists(atPath: location) {
            return location
        } else {
            return nil
        }
    }
}
