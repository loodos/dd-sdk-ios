/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The RUM context received from `Core`.
public struct RUMCoreContext {
    /// Current RUM application ID - standard UUID string, lowecased.
    public let applicationID: String
    /// Current RUM session ID - standard UUID string, lowecased.
    public let sessionID: String
    /// Current RUM view ID - standard UUID string, lowecased. It can be empty when view is being loaded.
    public let viewID: String?
    /// The ID of current RUM action (standard UUID `String`, lowercased).
    public let userActionID: String?
    /// Current view related server time offset
    public let viewServerTimeOffset: TimeInterval?

    /// Creates a RUM context.
    ///
    /// - Parameters:
    ///   - applicationID: Current RUM application ID - standard UUID string, lowecased.
    ///   - sessionID: Current RUM session ID - standard UUID string, lowecased.
    ///   - viewID: Current RUM view ID - standard UUID string, lowecased. It can be empty when view is being loaded.
    ///   - userActionID: The ID of current RUM action (standard UUID `String`, lowercased).
    ///   - viewServerTimeOffset: Current view related server time offset
    public init(
        applicationID: String,
        sessionID: String,
        viewID: String? = nil,
        userActionID: String? = nil,
        viewServerTimeOffset: TimeInterval? = nil
    ) {
        self.applicationID = applicationID
        self.sessionID = sessionID
        self.viewID = viewID
        self.userActionID = userActionID
        self.viewServerTimeOffset = viewServerTimeOffset
    }
}
