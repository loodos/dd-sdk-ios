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

class RUMSessionStartInBackgroundTests: XCTestCase {
    private let dt1: TimeInterval = 1.1
    private let dt2: TimeInterval = 1.2
    private let dt3: TimeInterval = 1.3
    private let accuracy: TimeInterval = 0.01

    private let processLaunchDate = Date()
    private let backgroundViewName = RUMOffViewEventsHandlingRule.Constants.backgroundViewName

    private func givenRUMEnabled(
        launchType: AppRunner.ProcessLaunchType,
        configureSDK: @escaping (inout Datadog.Configuration) -> Void = { _ in },
        configureRUM: @escaping (inout RUM.Configuration) -> Void = { _ in }
    ) -> AppRun {
        return AppRun.given { app in
            app.launch(launchType)
            app.advanceTime(by: self.dt1)

            // Enable RUM:
            app.initializeSDK(configureSDK)
            app.enableRUM(configureRUM)
        }
    }

    private func noEventIsTracked(app: AppRunner) {
        precondition(app.currentState == .background)
        app.advanceTime(by: dt2)
    }

    private func actionsAreTracked(app: AppRunner) {
        precondition(app.currentState == .background)
        app.advanceTime(by: dt2)
        app.rum.addAction(type: .custom, name: "CustomAction1")
        app.advanceTime(by: dt3)
        app.rum.addAction(type: .custom, name: "CustomAction2")
    }

    private func resourceIsTracked(app: AppRunner) {
        precondition(app.currentState == .background)
        app.advanceTime(by: dt2)
        app.rum.startResource(resourceKey: "resource", url: URL(string: "https://resource.url")!)
        app.advanceTime(by: dt3)
        app.rum.stopResource(resourceKey: "resource", response: .mockAny())
    }

    private func longTasksAreTracked(app: AppRunner) {
        precondition(app.currentState == .background)
        app.advanceTime(by: dt2)
        app.rum._internal?.addLongTask(at: app.currentTime, duration: 0.1)
        app.advanceTime(by: dt3)
        app.rum._internal?.addLongTask(at: app.currentTime, duration: 0.1)
    }

    // MARK: - OS Prewarm Launch

    private var osPrewarmLaunch: AppRunner.ProcessLaunchType { .osPrewarm(processLaunchDate: processLaunchDate) }

    func testGivenOSPrewarmLaunch_whenNoEventIsTracked() throws {
        // Given
        let given1 = givenRUMEnabled(launchType: osPrewarmLaunch)
        let given2 = givenRUMEnabled(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let sessions = try given.when(noEventIsTracked).then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }

    func testGivenOSPrewarmLaunch_whenActionsAreTracked() throws {
        // Given
        let given1 = givenRUMEnabled(launchType: osPrewarmLaunch)

        // When / Then
        let sessions = try given1.when(actionsAreTracked).then()
        XCTAssertTrue(sessions.isEmpty)

        // Given
        let given2 = givenRUMEnabled(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        // When / Then
        let session = try given2.when(actionsAreTracked).then().takeSingle()
        XCTAssertNil(session.applicationStartAction)
        XCTAssertNil(session.applicationStartupTime)
        XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
        XCTAssertEqual(session.duration, dt3, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .prewarm)
        XCTAssertEqual(session.views.count, 1)
        XCTAssertEqual(session.views[0].name, backgroundViewName)
        XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
    }

    func testGivenOSPrewarmLaunch_whenResourceIsTracked() throws {
        // Given
        let given1 = givenRUMEnabled(launchType: osPrewarmLaunch)

        // When / Then
        let sessions = try given1.when(resourceIsTracked).then()
        XCTAssertTrue(sessions.isEmpty)

        // Given
        let given2 = givenRUMEnabled(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        // When / Then
        let session = try given2.when(resourceIsTracked).then().takeSingle()
        XCTAssertNil(session.applicationStartAction)
        XCTAssertNil(session.applicationStartupTime)
        XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
        XCTAssertEqual(session.duration, dt3, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .prewarm)
        XCTAssertEqual(session.views.count, 1)
        XCTAssertEqual(session.views[0].name, backgroundViewName)
        XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
    }

    func testGivenOSPrewarmLaunch_whenLongTasksAreTracked() throws {
        // Given
        let given1 = givenRUMEnabled(launchType: osPrewarmLaunch)
        let given2 = givenRUMEnabled(launchType: osPrewarmLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let sessions = try given.when(longTasksAreTracked).then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }

    // MARK: - Background Launch

    private var backgroundLaunch: AppRunner.ProcessLaunchType { .backgroundLaunch(processLaunchDate: processLaunchDate) }

    func testGivenBackgroundLaunch_whenNoEventIsTracked() throws {
        // Given
        let given1 = givenRUMEnabled(launchType: backgroundLaunch)
        let given2 = givenRUMEnabled(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let sessions = try given.when(noEventIsTracked).then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }

    func testGivenBackgroundLaunch_whenActionsAreTracked() throws {
        // Given
        let given1 = givenRUMEnabled(launchType: backgroundLaunch)

        // When / Then
        let sessions = try given1.when(actionsAreTracked).then()
        XCTAssertTrue(sessions.isEmpty)

        // Given
        let given2 = givenRUMEnabled(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        // When / Then
        let session = try given2.when(actionsAreTracked).then().takeSingle()
        XCTAssertNil(session.applicationStartAction)
        XCTAssertNil(session.applicationStartupTime)
        XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
        XCTAssertEqual(session.duration, dt3, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
        XCTAssertEqual(session.views.count, 1)
        XCTAssertEqual(session.views[0].name, backgroundViewName)
        XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
    }

    func testGivenBackgroundLaunch_whenResourceIsTracked() throws {
        // Given
        let given1 = givenRUMEnabled(launchType: backgroundLaunch)

        // When / Then
        let sessions = try given1.when(resourceIsTracked).then()
        XCTAssertTrue(sessions.isEmpty)

        // Given
        let given2 = givenRUMEnabled(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        // When / Then
        let session = try given2.when(resourceIsTracked).then().takeSingle()
        XCTAssertNil(session.applicationStartAction)
        XCTAssertNil(session.applicationStartupTime)
        XCTAssertEqual(session.sessionStartDate, processLaunchDate + dt1 + dt2, accuracy: accuracy)
        XCTAssertEqual(session.duration, dt3, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
        XCTAssertEqual(session.views.count, 1)
        XCTAssertEqual(session.views[0].name, backgroundViewName)
        XCTAssertEqual(session.views[0].duration, dt3, accuracy: accuracy)
    }

    func testGivenBackgroundLaunch_whenLongTasksAreTracked() throws {
        // Given
        let given1 = givenRUMEnabled(launchType: backgroundLaunch)
        let given2 = givenRUMEnabled(launchType: backgroundLaunch, configureRUM: {
            $0.trackBackgroundEvents = true
        })

        for given in [given1, given2] {
            // When / Then
            let sessions = try given.when(longTasksAreTracked).then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }
}
