import BuildArtifacts
import Foundation
import EmceeLogging
import PathLib
import ProcessController
import ResourceLocation
import ResourceLocationResolver
import Runner
import RunnerModels

public final class XcTestRunFileArgument: SubprocessArgument, CustomStringConvertible {
    private let buildArtifacts: BuildArtifacts
    private let entriesToRun: [TestEntry]
    private let containerPath: AbsolutePath
    private let resourceLocationResolver: ResourceLocationResolver
    private let testContext: TestContext
    private let testType: TestType
    private let testingEnvironment: XcTestRunTestingEnvironment
    
    public enum XcTestRunFileArgumentError: CustomStringConvertible, Error {
        case cannotObtainBundleIdentifier(path: AbsolutePath)
        
        public var description: String {
            switch self {
            case .cannotObtainBundleIdentifier(let path):
                return "Cannot obtain bundle id for bundle at path: '\(path)'"
            }
        }
    }

    public init(
        buildArtifacts: BuildArtifacts,
        entriesToRun: [TestEntry],
        containerPath: AbsolutePath,
        resourceLocationResolver: ResourceLocationResolver,
        testContext: TestContext,
        testType: TestType,
        testingEnvironment: XcTestRunTestingEnvironment
    ) {
        self.buildArtifacts = buildArtifacts
        self.entriesToRun = entriesToRun
        self.containerPath = containerPath
        self.resourceLocationResolver = resourceLocationResolver
        self.testContext = testContext
        self.testType = testType
        self.testingEnvironment = testingEnvironment
    }
    
    public var description: String {
        "<\(type(of: self)) tests: \(entriesToRun.map { $0.testName }), testType \(testType), environment \(testContext.environment)>"
    }

    public func stringValue() throws -> String {
        let xcTestRun = try createXcTestRun()
        let xcTestRunPlist = XcTestRunPlist(xcTestRun: xcTestRun)
        let plistPath = containerPath.appending(component: "testrun.xctestrun")
        try xcTestRunPlist.createPlistData().write(
            to: plistPath.fileUrl,
            options: .atomic
        )
        return plistPath.pathString
    }

    private func createXcTestRun() throws -> XcTestRun {
        let resolvableXcTestBundle = resourceLocationResolver.resolvable(withRepresentable: buildArtifacts.xcTestBundle.location)
        
        switch testType {
        case .uiTest:
            return try xcTestRunForUiTesting(
                resolvableXcTestBundle: resolvableXcTestBundle
            )
        case .logicTest:
            return try xcTestRunForLogicTesting(
                resolvableXcTestBundle: resolvableXcTestBundle
            )
        case .appTest:
            return try xcTestRunForApplicationTesting(
                resolvableXcTestBundle: resolvableXcTestBundle
            )
        }
    }

    private func xcTestRunForLogicTesting(
        resolvableXcTestBundle: ResolvableResourceLocation
    ) throws -> XcTestRun {
        let testBundlePath = try resolvableXcTestBundle.resolve().directlyAccessibleResourcePath()
        let testHostPath = "__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"
        
        let insertedLibraries = [
            "__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib/libXCTestBundleInject.dylib"
        ] + testingEnvironment.insertedLibraries
        
        let xctestSpecificEnvironment = [
            "DYLD_INSERT_LIBRARIES": insertedLibraries.joined(separator: ":"),
            "XCInjectBundleInto": testHostPath,
        ]
        let testTargetProductModuleName = try self.testTargetProductModuleName(
            xcTestBundlePath: testBundlePath
        )
        
        return XcTestRun(
            testTargetName: testTargetProductModuleName,
            bundleIdentifiersForCrashReportEmphasis: [],
            dependentProductPaths: [
                testBundlePath.pathString,
            ],
            testBundlePath: testBundlePath.pathString,
            testHostPath: testHostPath,
            testHostBundleIdentifier: "com.apple.dt.xctest.tool",
            uiTargetAppPath: nil,
            environmentVariables: testContext.environment,
            commandLineArguments: [],
            uiTargetAppEnvironmentVariables: testContext.environment,
            uiTargetAppCommandLineArguments: [],
            uiTargetAppMainThreadCheckerEnabled: false,
            skipTestIdentifiers: [],
            onlyTestIdentifiers: entriesToRun.map { $0.testName.stringValue },
            testingEnvironmentVariables: xctestSpecificEnvironment.byMergingWith(testContext.environment),
            isUITestBundle: false,
            isAppHostedTestBundle: false,
            isXCTRunnerHostedTestBundle: false,
            testTargetProductModuleName: testTargetProductModuleName
        )
    }

    private func xcTestRunForApplicationTesting(
        resolvableXcTestBundle: ResolvableResourceLocation
    ) throws -> XcTestRun {
        guard let representableAppBundle = buildArtifacts.appBundle else {
            throw RunnerError.noAppBundleDefinedForUiOrApplicationTesting
        }
        let hostAppPath = try resourceLocationResolver.resolvable(resourceLocation: representableAppBundle.resourceLocation).resolve().directlyAccessibleResourcePath()
        let testBundlePath = try resolvableXcTestBundle.resolve().directlyAccessibleResourcePath()
        let testTargetProductModuleName = try self.testTargetProductModuleName(
            xcTestBundlePath: testBundlePath
        )

        guard let hostAppBundle = Bundle(path: hostAppPath.pathString), let hostAppBundleIdentifier = hostAppBundle.bundleIdentifier else {
            throw XcTestRunFileArgumentError.cannotObtainBundleIdentifier(path: hostAppPath)
        }
        
        let insertedLibraries = [
            "__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib/libXCTestBundleInject.dylib"
        ] + testingEnvironment.insertedLibraries
            
        let xctestSpecificEnvironment = [
            "DYLD_INSERT_LIBRARIES": insertedLibraries.joined(separator: ":"),
            "XCInjectBundleInto": hostAppPath.pathString,
        ]

        return XcTestRun(
            testTargetName: testTargetProductModuleName,
            bundleIdentifiersForCrashReportEmphasis: [],
            dependentProductPaths: [
                hostAppPath.pathString,
                testBundlePath.pathString,
            ],
            testBundlePath: testBundlePath.pathString,
            testHostPath: hostAppPath.pathString,
            testHostBundleIdentifier: hostAppBundleIdentifier,
            uiTargetAppPath: nil,
            environmentVariables: testContext.environment,
            commandLineArguments: [],
            uiTargetAppEnvironmentVariables: testContext.environment,
            uiTargetAppCommandLineArguments: [],
            uiTargetAppMainThreadCheckerEnabled: false,
            skipTestIdentifiers: [],
            onlyTestIdentifiers: entriesToRun.map { $0.testName.stringValue },
            testingEnvironmentVariables: xctestSpecificEnvironment.byMergingWith(testContext.environment),
            isUITestBundle: false,
            isAppHostedTestBundle: true,
            isXCTRunnerHostedTestBundle: false,
            testTargetProductModuleName: testTargetProductModuleName
        )
    }

    private func xcTestRunForUiTesting(
        resolvableXcTestBundle: ResolvableResourceLocation
    ) throws -> XcTestRun {
        guard let representableAppBundle = buildArtifacts.appBundle else {
            throw RunnerError.noAppBundleDefinedForUiOrApplicationTesting
        }
        guard let representableRunnerBundle = buildArtifacts.runner else {
            throw RunnerError.noRunnerAppDefinedForUiTesting
        }
        
        let uiTargetAppPath = try resourceLocationResolver.resolvable(resourceLocation: representableAppBundle.resourceLocation).resolve().directlyAccessibleResourcePath()
        let hostAppPath = try resourceLocationResolver.resolvable(resourceLocation: representableRunnerBundle.resourceLocation).resolve().directlyAccessibleResourcePath()
        let testBundlePath = try resolvableXcTestBundle.resolve().directlyAccessibleResourcePath()
        let additionalApplicationBundlePaths: [AbsolutePath] = try buildArtifacts.additionalApplicationBundles.map {
            try resourceLocationResolver.resolvable(resourceLocation: $0.resourceLocation).resolve().directlyAccessibleResourcePath()
        }
        let testTargetProductModuleName = try self.testTargetProductModuleName(
            xcTestBundlePath: testBundlePath
        )
        
        var testingEnvironmentVariables = [
            "DYLD_FRAMEWORK_PATH": "__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
            "DYLD_LIBRARY_PATH": "__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks"
        ]
        if !testingEnvironment.insertedLibraries.isEmpty {
            testingEnvironmentVariables["DYLD_INSERT_LIBRARIES"] = testingEnvironment.insertedLibraries.joined(separator: ":")
        }

        return XcTestRun(
            testTargetName: testTargetProductModuleName,
            bundleIdentifiersForCrashReportEmphasis: [],
            dependentProductPaths: ([uiTargetAppPath, testBundlePath, hostAppPath] + additionalApplicationBundlePaths).map { $0.pathString },
            testBundlePath: testBundlePath.pathString,
            testHostPath: hostAppPath.pathString,
            testHostBundleIdentifier: "StubBundleId",
            uiTargetAppPath: uiTargetAppPath.pathString,
            environmentVariables: testContext.environment,
            commandLineArguments: [],
            uiTargetAppEnvironmentVariables: testContext.environment,
            uiTargetAppCommandLineArguments: [],
            uiTargetAppMainThreadCheckerEnabled: false,
            skipTestIdentifiers: [],
            onlyTestIdentifiers: entriesToRun.map { $0.testName.stringValue },
            testingEnvironmentVariables: testingEnvironmentVariables,
            isUITestBundle: true,
            isAppHostedTestBundle: false,
            isXCTRunnerHostedTestBundle: true,
            testTargetProductModuleName: testTargetProductModuleName
        )
    }
    
    private func testTargetProductModuleName(
        xcTestBundlePath: AbsolutePath
    ) throws -> String {
        let plistPath = xcTestBundlePath.appending(component: "Info.plist")
        let plistContents = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistPath.fileUrl, options: .mappedIfSafe),
            options: [],
            format: nil
        )
        guard let plistDict = plistContents as? NSDictionary else {
            throw InfoPlistError.failedToReadPlistContents(path: plistPath, contents: plistContents)
        }
        guard let bundleName = plistDict["CFBundleName"] as? String else {
            throw InfoPlistError.noValueCFBundleName(path: plistPath)
        }
        return suitableModuleName(name: bundleName)
    }
    
    private func suitableModuleName(name: String) -> String {
        return name
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
