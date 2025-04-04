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

class RUMSessionStartInForegroundTests: XCTestCase {
    private let dt1: TimeInterval = 1.1
    private let dt2: TimeInterval = 1.2
    private let dt3: TimeInterval = 1.3
    private let dt4: TimeInterval = 1.4
    private let dt5: TimeInterval = 1.5
    private let accuracy: TimeInterval = 0.01

    private let processLaunchDate = Date()
    private let applicationLaunchViewName = RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName

    private func givenRUMEnabledBeforeAppDidBecomeActive(
        launchType: AppRunner.ProcessLaunchType,
        configureSDK: @escaping (inout Datadog.Configuration) -> Void = { _ in },
        configureRUM: @escaping (inout RUM.Configuration) -> Void = { _ in }
    ) -> AppRun {
        return AppRun.given { app in
            app.launch(launchType)
            app.advanceTime(by: self.dt1)

            // First, enable RUM:
            app.initializeSDK(configureSDK)
            app.enableRUM(configureRUM)

            // Then, activate app:
            app.advanceTime(by: self.dt2)
            app.receiveAppStateNotification(ApplicationNotifications.didBecomeActive)
        }
    }

    private func givenRUMEnabledAfterAppDidBecomeActive(
        launchType: AppRunner.ProcessLaunchType,
        configureSDK: @escaping (inout Datadog.Configuration) -> Void = { _ in },
        configureRUM: @escaping (inout RUM.Configuration) -> Void = { _ in }
    ) -> AppRun {
        return AppRun.given { app in
            app.launch(launchType)
            app.advanceTime(by: self.dt1)

            // First, activate app:
            app.receiveAppStateNotification(ApplicationNotifications.didBecomeActive)

            // Then, enable RUM:
            app.advanceTime(by: self.dt2)
            app.initializeSDK(configureSDK)
            app.enableRUM(configureRUM)
        }
    }

    private func appEntersBackground(app: AppRunner) {
        precondition(app.currentState == .active)
        app.advanceTime(by: dt3)
        app.receiveAppStateNotification(ApplicationNotifications.willResignActive)
        app.receiveAppStateNotification(ApplicationNotifications.didEnterBackground)
    }

    private func manualViewIsStartedAndCompletesInForeground(app: AppRunner) {
        precondition(app.currentState == .active)
        app.advanceTime(by: dt3)
        app.rum.startView(key: "view", name: "ManualView")
        app.advanceTime(by: dt4)
        app.rum.stopView(key: "view")
    }

    private func manualViewIsStartedAndCompletesInBackground(app: AppRunner) {
        precondition(app.currentState == .active)
        app.advanceTime(by: dt3)
        app.rum.startView(key: "view", name: "ManualView")
        app.advanceTime(by: dt4)
        app.receiveAppStateNotification(ApplicationNotifications.willResignActive)
        app.receiveAppStateNotification(ApplicationNotifications.didEnterBackground)
        app.rum.stopView(key: "view")
    }

    private func automaticViewIsStartedAndAppEntersBackground(app: AppRunner) {
        precondition(app.currentState == .active)
        app.advanceTime(by: dt3)
        let view = createMockView(viewControllerClassName: "AutomaticView")
        app.viewDidAppear(vc: view)
        app.advanceTime(by: dt4)
        app.receiveAppStateNotification(ApplicationNotifications.willResignActive)
        app.receiveAppStateNotification(ApplicationNotifications.didEnterBackground)
    }

    private func actionIsTrackedAndAppEntersBackground(app: AppRunner) {
        precondition(app.currentState == .active)
        app.advanceTime(by: dt3)
        app.rum.addAction(type: .custom, name: "CustomAction")
        app.advanceTime(by: dt4)
        app.receiveAppStateNotification(ApplicationNotifications.willResignActive)
        app.receiveAppStateNotification(ApplicationNotifications.didEnterBackground)
    }

    private func resourceIsStartedAndCompletesInForeground(app: AppRunner) {
        precondition(app.currentState == .active)
        app.advanceTime(by: dt3)
        app.rum.startResource(resourceKey: "resource", url: URL(string: "https://resource.url")!)
        app.advanceTime(by: dt4)
        app.rum.stopResource(resourceKey: "resource", response: .mockAny())
    }

    private func resourceIsStartedAndCompletesInBackground(app: AppRunner) {
        precondition(app.currentState == .active)
        app.advanceTime(by: dt3)
        app.rum.startResource(resourceKey: "resource", url: URL(string: "https://resource.url")!)
        app.receiveAppStateNotification(ApplicationNotifications.willResignActive)
        app.receiveAppStateNotification(ApplicationNotifications.didEnterBackground)
        app.advanceTime(by: dt4)
        app.rum.stopResource(resourceKey: "resource", response: .mockAny())
    }

    private func longTaskIsTrackedAndAppEntersBackground(app: AppRunner) {
        precondition(app.currentState == .active)
        app.advanceTime(by: dt3)
        app.rum._internal?.addLongTask(at: app.currentTime, duration: 0.1)
        app.advanceTime(by: dt4)
        app.receiveAppStateNotification(ApplicationNotifications.willResignActive)
        app.receiveAppStateNotification(ApplicationNotifications.didEnterBackground)
    }

    // MARK: - User Launch

    private var userLaunch: AppRunner.ProcessLaunchType { .userLaunch(processLaunchDate: processLaunchDate) }

    func testGivenUserLaunch_whenNoEventIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(appEntersBackground).then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt1 + dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt1 + dt2 + dt3, accuracy: accuracy)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(appEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
        }
    }

    func testGivenUserLaunch_whenManualViewIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When
            for when in [
                given.when(manualViewIsStartedAndCompletesInForeground),
                given.when(manualViewIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt1 + dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, "ManualView")
                XCTAssertEqual(session.views[1].duration, dt4, accuracy: accuracy)
            }
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When
            for when in [
                given.when(manualViewIsStartedAndCompletesInForeground),
                given.when(manualViewIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, "ManualView")
                XCTAssertEqual(session.views[1].duration, dt4, accuracy: accuracy)
            }
        }
    }

    func testGivenUserLaunch_whenAutomaticViewIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        })
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(automaticViewIsStartedAndAppEntersBackground).then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 2)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt1 + dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, "AutomaticView")
            XCTAssertEqual(session.views[1].duration, dt4, accuracy: accuracy)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        })
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(automaticViewIsStartedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 2)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, "AutomaticView")
            XCTAssertEqual(session.views[1].duration, dt4, accuracy: accuracy)
        }
    }

    func testGivenUserLaunch_whenActionIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(actionIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
            XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction" }))
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(actionIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction" }))
        }
    }

    func testGivenUserLaunch_whenResourceIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When
            for when in [
                given.when(resourceIsStartedAndCompletesInForeground),
                given.when(resourceIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When
            for when in [
                given.when(resourceIsStartedAndCompletesInForeground),
                given.when(resourceIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }
    }

    func testGivenUserLaunch_whenLongTaskIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(longTaskIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.views[0].viewEvents.last?.view.longTask?.count, 1)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: userLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(longTaskIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.views[0].viewEvents.last?.view.longTask?.count, 1)
        }
    }

    // MARK: - OS Prewarm Launch

    private var osPrewarmLaunch: AppRunner.ProcessLaunchType { .osPrewarm(processLaunchDate: processLaunchDate) }

    func testGivenOSPrewarmLaunch_whenNoEventIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let sessions = try given.when(appEntersBackground).then()
            XCTAssertTrue(sessions.isEmpty)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(appEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
        }
    }

    func testGivenOSPrewarmLaunch_whenManualViewIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When
            for when in [
                given.when(manualViewIsStartedAndCompletesInForeground),
                given.when(manualViewIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, "ManualView")
                XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
            }
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When
            for when in [
                given.when(manualViewIsStartedAndCompletesInForeground),
                given.when(manualViewIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, "ManualView")
                XCTAssertEqual(session.views[1].duration, dt4, accuracy: accuracy)
            }
        }
    }

    func testGivenOSPrewarmLaunch_whenAutomaticViewIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        })
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(automaticViewIsStartedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertNil(session.applicationStartAction)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .prewarm)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, "AutomaticView")
            XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        })
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(automaticViewIsStartedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 2)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, "AutomaticView")
            XCTAssertEqual(session.views[1].duration, dt4, accuracy: accuracy)
        }
    }

    func testGivenOSPrewarmLaunch_whenActionIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(actionIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertNil(session.applicationStartAction)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .prewarm)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(actionIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
        }
    }

    func testGivenOSPrewarmLaunch_whenResourceIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When
            for when in [
                given.when(resourceIsStartedAndCompletesInForeground),
                given.when(resourceIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When
            for when in [
                given.when(resourceIsStartedAndCompletesInForeground),
                given.when(resourceIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }
    }

    func testGivenOSPrewarmLaunch_whenLongTaskIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(longTaskIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertNil(session.applicationStartAction)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .prewarm)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
            XCTAssertEqual(session.views[0].viewEvents.last?.view.longTask?.count, 1)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(longTaskIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
        }
    }

    // MARK: - Background Launch

    private var backgroundLaunch: AppRunner.ProcessLaunchType { .backgroundLaunch(processLaunchDate: processLaunchDate) }

    func testGivenBackgroundLaunch_whenNoEventIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let sessions = try given.when(appEntersBackground).then()
            XCTAssertTrue(sessions.isEmpty)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(appEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
        }
    }

    func testGivenBackgroundLaunch_whenManualViewIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When
            for when in [
                given.when(manualViewIsStartedAndCompletesInForeground),
                given.when(manualViewIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, "ManualView")
                XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
            }
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When
            for when in [
                given.when(manualViewIsStartedAndCompletesInForeground),
                given.when(manualViewIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, "ManualView")
                XCTAssertEqual(session.views[1].duration, dt4, accuracy: accuracy)
            }
        }
    }

    func testGivenBackgroundLaunch_whenAutomaticViewIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        })
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(automaticViewIsStartedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertNil(session.applicationStartAction)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, "AutomaticView")
            XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        })
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(automaticViewIsStartedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 2)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, "AutomaticView")
            XCTAssertEqual(session.views[1].duration, dt4, accuracy: accuracy)
        }
    }

    func testGivenBackgroundLaunch_whenActionIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(actionIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertNil(session.applicationStartAction)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(actionIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
        }
    }

    func testGivenBackgroundLaunch_whenResourceIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When
            for when in [
                given.when(resourceIsStartedAndCompletesInForeground),
                given.when(resourceIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When
            for when in [
                given.when(resourceIsStartedAndCompletesInForeground),
                given.when(resourceIsStartedAndCompletesInBackground)
            ] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }
    }

    func testGivenBackgroundLaunch_whenLongTaskIsTrackedBeforeAppEntersBackground() throws {
        // Given
        let given1 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch)
        let given2 = givenRUMEnabledBeforeAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let session = try given.when(longTaskIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertNil(session.applicationStartAction)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt4, accuracy: accuracy)
            XCTAssertEqual(session.views[0].viewEvents.last?.view.longTask?.count, 1)
        }

        // Given
        let given3 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch)
        let given4 = givenRUMEnabledAfterAppDidBecomeActive(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given3, given4] {
            // When / Then
            let session = try given.when(longTaskIsTrackedAndAppEntersBackground).then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt3 + dt4, accuracy: accuracy)
        }
    }
}
