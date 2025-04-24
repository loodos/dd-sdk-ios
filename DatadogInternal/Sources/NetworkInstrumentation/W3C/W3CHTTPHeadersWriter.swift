/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `W3CHTTPHeadersWriter` class facilitates the injection of trace propagation headers into network requests
/// targeted at a backend expecting [W3C propagation format](https://github.com/openzipkin/b3-propagation).
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = W3CHTTPHeadersWriter()
///     let span = Tracer.shared().startRootSpan(operationName: "network request")
///     Tracer.shared().inject(spanContext: span.context, writer: writer)
///
///     writer.traceHeaderFields.forEach { (field, value) in
///         request.setValue(value, forHTTPHeaderField: field)
///     }
///
///     // call span.finish() when the request completes
///
public class W3CHTTPHeadersWriter: TracePropagationHeadersWriter {
    /// A dictionary containing the required HTTP Headers for propagating trace information.
    ///
    /// Usage:
    ///
    ///     writer.traceHeaderFields.forEach { (field, value) in
    ///         request.setValue(value, forHTTPHeaderField: field)
    ///     }
    ///
    public private(set) var traceHeaderFields: [String: String] = [:]

    /// A dictionary containing the tracestate to be injected.
    /// This value will be merged with the tracestate from the trace context.
    private let tracestate: [String: String]

    private let samplingStrategy: TraceSamplingStrategy
    private let traceContextInjection: TraceContextInjection

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingRate: The sampling rate applied for headers injection.
    /// - Parameter tracestate: The tracestate to be injected.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(samplingRate: Float) {
        self.init(sampleRate: samplingRate, tracestate: [:])
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampleRate: The sampling rate applied for headers injection, with 20% as the default.
    /// - Parameter tracestate: The tracestate to be injected.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(sampleRate: Float = 20, tracestate: [String: String] = [:]) {
        self.init(samplingStrategy: .custom(sampleRate: sampleRate), tracestate: tracestate, traceContextInjection: .sampled)
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingStrategy: The strategy for sampling trace propagation headers.
    /// - Parameter tracestate: The tracestate to be injected.
    /// - Parameter traceContextInjection: The strategy for injecting trace context into requests.
    public init(
        samplingStrategy: TraceSamplingStrategy,
        tracestate: [String: String] = [:],
        traceContextInjection: TraceContextInjection = .sampled
    ) {
        self.samplingStrategy = samplingStrategy
        self.tracestate = tracestate
        self.traceContextInjection = traceContextInjection
    }

    /// Writes the trace ID, span ID, and optional parent span ID into the trace propagation headers.
    ///
    /// - Parameter traceID: The trace ID.
    /// - Parameter spanID: The span ID.
    /// - Parameter parentSpanID: The parent span ID, if applicable.
    public func write(traceContext: TraceContext) {
        typealias Constants = W3CHTTPHeaders.Constants

        let sampler = samplingStrategy.sampler(for: traceContext)
        let sampled = sampler.sample()

        switch (traceContextInjection, sampled) {
        case (.all, _), (.sampled, true):
            traceHeaderFields[W3CHTTPHeaders.traceparent] = [
                Constants.version,
                String(traceContext.traceID, representation: .hexadecimal32Chars),
                String(traceContext.spanID, representation: .hexadecimal16Chars),
                sampled ? Constants.sampledValue : Constants.unsampledValue
            ]
            .joined(separator: Constants.separator)

            // while merging, the tracestate values from the tracestate property take precedence
            // over the ones from the trace context
            let tracestate: [String: String] = [
                Constants.sampling: "\(sampled ? 1 : 0)",
                Constants.parentId: String(traceContext.spanID, representation: .hexadecimal16Chars)
            ].merging(tracestate) { old, new in
                return new
            }

            let ddtracestate = tracestate
                .map { "\($0.key)\(Constants.tracestateKeyValueSeparator)\($0.value)" }
                .sorted()
                .joined(separator: Constants.tracestatePairSeparator)

            traceHeaderFields[W3CHTTPHeaders.tracestate] = "\(Constants.dd)=\(ddtracestate)"

            if let sessionId = traceContext.rumSessionId {
                traceHeaderFields[W3CHTTPHeaders.baggage] = "\(Constants.rumSessionBaggageKey)=\(sessionId)"
            }
        case (.sampled, false):
            break
        }
    }
}
