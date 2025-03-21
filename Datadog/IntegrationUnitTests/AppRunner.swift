/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

internal class AppRunner {
    struct ProcessLaunchType {
        let processLaunchDate: Date
        let activePrewarm: Bool
        let initialAppState: AppState

        /// The process was not in memory and user launches it by tapping the app icon.
        static func userLaunch(processLaunchDate: Date) -> ProcessLaunchType {
            return .init(
                processLaunchDate: processLaunchDate,
                activePrewarm: false,
                initialAppState: .inactive
            )
        }

        /// The process was prewarmed by OS. The user may launch the app later by tapping the app icon.
        static func osPrewarm(processLaunchDate: Date) -> ProcessLaunchType {
            return .init(
                processLaunchDate: processLaunchDate,
                activePrewarm: true,
                initialAppState: .background
            )
        }

        /// The process was launched in background, e.g. due to silent push notification or background fetch.
        /// The user may launch the app much later by tapping the app icon.
        static func backgroundLaunch(processLaunchDate: Date) -> ProcessLaunchType {
            return .init(
                processLaunchDate: processLaunchDate,
                activePrewarm: false,
                initialAppState: .background
            )
        }
    }

    func setUp() {
        CreateTemporaryDirectory()
    }

    func tearDown() {
        DeleteTemporaryDirectory()

        appDirectory = nil
        notificationCenter = nil
        dateProvider = nil
        appStateProvider = nil
        appLaunchHandler = nil
        core = nil
    }

    // swiftlint:disable implicitly_unwrapped_optional
    private var appDirectory: (() -> Directory)!
    private var notificationCenter: NotificationCenter!
    private var dateProvider: DateProviderMock!
    private var appStateProvider: AppStateProviderMock!
    private var appLaunchHandler: AppLaunchHandlerMock!
    private var core: DatadogCoreProxy!
    // swiftlint:enable implicitly_unwrapped_optional

    func launch(_ launchType: ProcessLaunchType) {
        appDirectory = { Directory(url: temporaryDirectory) }
        notificationCenter = NotificationCenter()
        dateProvider = DateProviderMock(now: launchType.processLaunchDate)
        appStateProvider = AppStateProviderMock(state: launchType.initialAppState)
        appLaunchHandler = AppLaunchHandlerMock(
            launchDate: launchType.processLaunchDate,
            timeToDidBecomeActive: nil, // will wait for SimulationStep.changeAppState(_:)
            isActivePrewarm: launchType.activePrewarm
        )
    }

    func receiveAppStateNotification(_ notificationName: Notification.Name) {
        notificationCenter.post(name: notificationName, object: nil)
        appStateProvider.current = {
            switch notificationName {
            case ApplicationNotifications.didBecomeActive: return .active
            case ApplicationNotifications.willResignActive: return .inactive
            case ApplicationNotifications.didEnterBackground: return .background
            case ApplicationNotifications.willEnterForeground: return .inactive
            default: fatalError("Unrecognized notification: \(notificationName)")
            }
        }()

        if notificationName == ApplicationNotifications.didBecomeActive {
            let launchTime = dateProvider.now.timeIntervalSince(appLaunchHandler.launchDate)
            appLaunchHandler.simulateDidBecomeActive(timeInterval: launchTime)
        }
    }

    var currentState: AppState { appStateProvider.current }

    func advanceTime(by interval: TimeInterval) {
        dateProvider.now.addTimeInterval(interval)
    }

    var currentTime: Date { dateProvider.now }

    func initializeSDK(_ setUp: (inout Datadog.Configuration) -> Void = { _ in }) {
        var config = Datadog.Configuration(clientToken: "mock-client-token", env: "env")
        config.systemDirectory = appDirectory
        config.dateProvider = dateProvider
        config.notificationCenter = notificationCenter
        config.appLaunchHandler = appLaunchHandler
        config.appStateProvider = appStateProvider
        setUp(&config)
        do {
            core = DatadogCoreProxy(
                core: try DatadogCore(configuration: config, trackingConsent: .granted, instanceName: .mockAny())
            )
        } catch {
            XCTFail("\(error)")
        }
    }

    func enableRUM(_ setUp: (inout RUM.Configuration) -> Void = { _ in }) {
        var config = RUM.Configuration(applicationID: "mock-application-id")
        config.dateProvider = dateProvider
        config.notificationCenter = notificationCenter
        setUp(&config)
        RUM.enable(with: config, in: core)
    }

    var rum: RUMMonitorProtocol { RUMMonitor.shared(in: core) }

    func recordedRUMSessions() throws -> [RUMSessionMatcher] {
        return try RUMSessionMatcher.groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
    }

    func viewDidAppear(vc: UIViewController) {
        vc.viewDidAppear(true)
    }

    func viewDidDisappear(vc: UIViewController) {
        vc.viewDidDisappear(true)
    }
}

internal struct AppRun {
    private var testBlocks: [(AppRunner) -> Void]

    private init(precondition: @escaping (AppRunner) -> Void) {
        testBlocks = [precondition]
    }

    static func given(_ precondition: @escaping (AppRunner) -> Void) -> Self {
        return AppRun(precondition: precondition)
    }

    func when(_ condition: @escaping (AppRunner) -> Void) -> Self {
        var new = self
        new.testBlocks.append(condition)
        return new
    }

    func then() throws -> [RUMSessionMatcher] {
        let app = AppRunner()
        app.setUp()
        defer { app.tearDown() }
        testBlocks.forEach { block in block(app) }
        return try app.recordedRUMSessions()
    }
}
