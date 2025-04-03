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

class RUMForegroundSessionTimeOutInBackgroundTests: XCTestCase {
    private let dt1: TimeInterval = 1.1
    private let dt2: TimeInterval = 1.2
    private let dt3: TimeInterval = 1.3
    private let dt4: TimeInterval = 1.4
    private let dt5: TimeInterval = 1.5
    private let accuracy: TimeInterval = 0.01

    private let processLaunchDate = Date()
    private let applicationLaunchViewName = RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
    private let backgroundViewName = RUMOffViewEventsHandlingRule.Constants.backgroundViewName
    private let customViewName = "CustomView"
    private let sessionTimeoutDuration = RUMSessionScope.Constants.sessionTimeoutDuration

    private func givenForegroundSessionWithAppLaunchView(
        configureSDK: @escaping (inout Datadog.Configuration) -> Void = { _ in },
        configureRUM: @escaping (inout RUM.Configuration) -> Void = { _ in }
    ) -> AppRun {
        return AppRun.given { app in
            app.launch(.userLaunch(processLaunchDate: self.processLaunchDate))
            app.advanceTime(by: self.dt1)

            // Enable RUM:
            app.initializeSDK(configureSDK)
            app.enableRUM { rumConfig in
                configureRUM(&rumConfig)
                rumConfig.sessionEndedSampleRate = 0 // TODO: RUM-9335 Enable "Session Ended" telemetry after fixing `application.id` value for session time-outs
                rumConfig.telemetrySampleRate = 0
            }

            // Activate app:
            app.advanceTime(by: self.dt2)
            app.receiveAppStateNotification(ApplicationNotifications.didBecomeActive)
        }
    }

    private func givenForegroundSessionWithManualView(
        configureSDK: @escaping (inout Datadog.Configuration) -> Void = { _ in },
        configureRUM: @escaping (inout RUM.Configuration) -> Void = { _ in }
    ) -> AppRun {
        return givenForegroundSessionWithAppLaunchView(configureSDK: configureSDK, configureRUM: configureRUM)
            .when { app in
                app.rum.startView(key: "view", name: self.customViewName)
            }
    }

    private func givenForegroundSessionWithAutomaticView(
        configureSDK: @escaping (inout Datadog.Configuration) -> Void = { _ in },
        configureRUM: @escaping (inout RUM.Configuration) -> Void = { _ in }
    ) -> AppRun {
        return givenForegroundSessionWithAppLaunchView(configureSDK: configureSDK, configureRUM: configureRUM)
            .when { app in
                let view = createMockView(viewControllerClassName: self.customViewName)
                app.viewDidAppear(vc: view)
            }
    }

    private func sesssionTimesOut(app: AppRunner) {
        app.advanceTime(by: sessionTimeoutDuration)
    }

    private func appEntersBackground(app: AppRunner) {
        app.advanceTime(by: dt3)
        app.receiveAppStateNotification(ApplicationNotifications.willResignActive)
        app.receiveAppStateNotification(ApplicationNotifications.didEnterBackground)
    }

    private func actionsAreTracked(app: AppRunner) {
        app.advanceTime(by: dt4)
        app.rum.addAction(type: .custom, name: "CustomAction1")
        app.advanceTime(by: dt5)
        app.rum.addAction(type: .custom, name: "CustomAction2")
    }

    private func resourceIsTracked(app: AppRunner) {
        app.advanceTime(by: dt4)
        app.rum.startResource(resourceKey: "resource", url: URL(string: "https://resource.url")!)
        app.advanceTime(by: dt5)
        app.rum.stopResource(resourceKey: "resource", response: .mockAny())
    }

    private func longTasksAreTracked(app: AppRunner) {
        app.advanceTime(by: dt4)
        app.rum._internal?.addLongTask(at: app.currentTime, duration: 0.1)
        app.advanceTime(by: dt5)
        app.rum._internal?.addLongTask(at: app.currentTime, duration: 0.1)
    }

    // MARK: - Session Time Out on Application Launch View

    func testGivenTimedOutSessionWithApplicationLaunchView_whenAppEntersBackground() throws {
        // Given
        let given1 = givenForegroundSessionWithAppLaunchView()
        let given2 = givenForegroundSessionWithAppLaunchView(configureRUM: { $0.trackBackgroundEvents = true })

        for given in [given1, given2] {
            // Given
            let given = given.and(sesssionTimesOut)

            // When / Then
            let session = try given.when(appEntersBackground).then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
        }
    }

    func testGivenTimedOutSessionWithApplicationLaunchView_whenEventsAreTrackedAfterAppEntersBackground() throws {
        // Given
        // - BET disabled
        let given = givenForegroundSessionWithAppLaunchView()
            .and(sesssionTimesOut)

        // When
        let when1 = given.when(appEntersBackground).and(actionsAreTracked)
        let when2 = given.when(appEntersBackground).and(resourceIsTracked)
        let when3 = given.when(appEntersBackground).and(longTasksAreTracked)

        for when in [when1, when2, when3] {
            // Then
            // - Only timed-out session is tracked
            let session = try when.then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
        }
    }

    func testGivenTimedOutSessionWithApplicationLaunchView_andBETEnabled_whenEventsAreTrackedAfterAppEntersBackground() throws {
        // Given
        // - BET enabled
        let given = givenForegroundSessionWithAppLaunchView(configureRUM: { $0.trackBackgroundEvents = true })
            .and(sesssionTimesOut)

        // When
        let when1 = given.when(appEntersBackground).and(actionsAreTracked)
        let when2 = given.when(appEntersBackground).and(resourceIsTracked)

        for when in [when1, when2] {
            // Then
            // - It tracks timed-out session:
            let (session1, session2) = try when.then().takeTwo()
            XCTAssertNotNil(session1.applicationStartAction)
            XCTAssertEqual(session1.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session1.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session1.duration, dt1, accuracy: accuracy)
            XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session1.views.count, 1)
            XCTAssertEqual(session1.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session1.views[0].duration, dt1, accuracy: accuracy)

            // - It creates new session for tracking background events:
            XCTAssertNil(session2.applicationStartAction)
            XCTAssertNil(session2.applicationStartupTime)
            XCTAssertEqual(session2.sessionStartDate, processLaunchDate + dt1 + dt2 + sessionTimeoutDuration + dt3 + dt4, accuracy: accuracy)
            XCTAssertEqual(session2.duration, dt5, accuracy: accuracy)
            XCTAssertEqual(session2.sessionPrecondition, .inactivityTimeout)
            XCTAssertEqual(session2.views.count, 1)
            XCTAssertEqual(session2.views[0].name, backgroundViewName)
            XCTAssertEqual(session2.views[0].duration, dt5, accuracy: accuracy)
            XCTAssertEqual(session2.views[0].actionEvents.count, when == when1 ? 2 : 0)
            XCTAssertEqual(session2.views[0].resourceEvents.count, when == when2 ? 1 : 0)
        }
    }

    func testGivenTimedOutSessionWithApplicationLaunchView_andBETEnabled_whenLongTasksAreTrackedAfterAppEntersBackground() throws {
        // Given
        // - BET enabled
        let given = givenForegroundSessionWithAppLaunchView(configureRUM: { $0.trackBackgroundEvents = true })
            .and(sesssionTimesOut)

        // When
        let when = given.when(appEntersBackground).and(longTasksAreTracked)

        // Then
        // - It only tracks timed-out session:
        let session = try when.then().takeSingle()
        XCTAssertNotNil(session.applicationStartAction)
        XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
        XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
        XCTAssertEqual(session.duration, dt1, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
        XCTAssertEqual(session.views.count, 1)
        XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
        XCTAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
    }

    // MARK: - Session Time Out on Custom View

    func testGivenTimedOutSessionWithCustomView_whenAppEntersBackground() throws {
        // Given
        let given1 = givenForegroundSessionWithManualView()
        let given2 = givenForegroundSessionWithManualView(configureRUM: { $0.trackBackgroundEvents = true })
        let given3 = givenForegroundSessionWithAutomaticView(configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        })
        let given4 = givenForegroundSessionWithAutomaticView(configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2, given3, given4] {
            // Given
            let given = given.and(sesssionTimesOut)

            // When / Then
            let session = try given.when(appEntersBackground).then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 2)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, customViewName)
            XCTAssertEqual(session.views[1].duration, 0, accuracy: accuracy)
        }
    }

    func testGivenTimedOutSessionWithCustomView_whenEventsAreTrackedAfterAppEntersBackground() throws {
        // Given
        // - BET disabled
        let given1 = givenForegroundSessionWithManualView()
        let given2 = givenForegroundSessionWithAutomaticView(configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        })

        for given in [given1, given2] {
            // Given
            let given = given.and(sesssionTimesOut)

            // When
            let when1 = given.when(appEntersBackground).and(actionsAreTracked)
            let when2 = given.when(appEntersBackground).and(resourceIsTracked)
            let when3 = given.when(appEntersBackground).and(longTasksAreTracked)

            for when in [when1, when2, when3] {
                // Then
                // - Only timed-out session is tracked
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
                XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, customViewName)
                XCTAssertEqual(session.views[1].duration, 0, accuracy: accuracy)
            }
        }
    }

    func testGivenTimedOutSessionCustomView_andBETEnabled_whenEventsAreTrackedAfterAppEntersBackground() throws {
        // Given
        // - BET enabled
        let given1 = givenForegroundSessionWithManualView(configureRUM: { $0.trackBackgroundEvents = true })
        let given2 = givenForegroundSessionWithAutomaticView(configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // Given
            let given = given.and(sesssionTimesOut)

            // When
            let when1 = given.when(appEntersBackground).and(actionsAreTracked)
            let when2 = given.when(appEntersBackground).and(resourceIsTracked)

            for when in [when1, when2] {
                // Then
                // - It tracks timed-out session:
                let (session1, session2) = try when.then().takeTwo()
                XCTAssertNotNil(session1.applicationStartAction)
                XCTAssertEqual(session1.applicationStartupTime, dt1, accuracy: accuracy)
                XCTAssertEqual(session1.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session1.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session1.views.count, 2)
                XCTAssertEqual(session1.views[0].name, applicationLaunchViewName)
                XCTAssertEqual(session1.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session1.views[1].name, customViewName)
                XCTAssertEqual(session1.views[1].duration, 0, accuracy: accuracy)

                // - It creates new session for tracking background events:
                XCTAssertNil(session2.applicationStartAction)
                XCTAssertNil(session2.applicationStartupTime)
                XCTAssertEqual(session2.sessionStartDate, processLaunchDate + dt1 + dt2 + sessionTimeoutDuration + dt3 + dt4, accuracy: accuracy)
                XCTAssertEqual(session2.duration, dt5, accuracy: accuracy)
                XCTAssertEqual(session2.sessionPrecondition, .inactivityTimeout)
                XCTAssertEqual(session2.views.count, 1)
                XCTAssertEqual(session2.views[0].name, backgroundViewName)
                XCTAssertEqual(session2.views[0].duration, dt5, accuracy: accuracy)
                XCTAssertEqual(session2.views[0].actionEvents.count, when == when1 ? 2 : 0)
                XCTAssertEqual(session2.views[0].resourceEvents.count, when == when2 ? 1 : 0)
            }
        }
    }

    func testGivenTimedOutSessionWithCustomView_andBETEnabled_whenLongTasksAreTrackedAfterAppEntersBackground() throws {
        // Given
        // - BET enabled
        let given1 = givenForegroundSessionWithManualView(configureRUM: { $0.trackBackgroundEvents = true })
        let given2 = givenForegroundSessionWithAutomaticView(configureRUM: {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // Given
            let given = given.and(sesssionTimesOut)

            // When
            let when = given.when(appEntersBackground).and(longTasksAreTracked)

            // Then
            // - It only tracks timed-out session:
            let session = try when.then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            XCTAssertEqual(session.applicationStartupTime, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            XCTAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 2)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            XCTAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, customViewName)
            XCTAssertEqual(session.views[1].duration, 0, accuracy: accuracy)
        }
    }
}
