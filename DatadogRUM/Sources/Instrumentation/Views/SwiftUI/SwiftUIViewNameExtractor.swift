/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

// MARK: - SwiftUIViewNameExtractor
/// Protocol defining interface for extracting view names for SwiftUI views
internal protocol SwiftUIViewNameExtractor {
    func extractName(from: UIViewController) -> String?
}

// MARK: - SwiftUIReflectionBasedViewNameExtractor
/// Default implementation that extracts SwiftUI view names using reflection and string parsing
internal struct SwiftUIReflectionBasedViewNameExtractor: SwiftUIViewNameExtractor {
    private let createReflector: (Any) -> TopLevelReflector

    init(
        reflectorFactory: @escaping (Any) -> TopLevelReflector = { subject in
            ReflectionMirror(reflecting: subject)
        }
    ) {
        self.createReflector = reflectorFactory
    }

    /// Attempts to extract a meaningful SwiftUI view name from a `UIViewController`
    /// - Parameter viewController: The `UIViewController` potentially hosting a SwiftUI view
    /// - Returns: The extracted view name or `nil` if extraction failed
    func extractName(from viewController: UIViewController) -> String? {
        // Skip known container controllers that shouldn't be tracked
        if shouldSkipViewController(viewController: viewController) {
            return nil
        }

        // Reflector to inspect the view controller's internals
        let reflector = createReflector(viewController)

        return extractViewName(
            from: viewController,
            withReflector: reflector
        )
    }

    private func extractViewName(
        from viewController: UIViewController,
        withReflector reflector: TopLevelReflector
    ) -> String? {
        let className = NSStringFromClass(type(of: viewController))
        let controllerType = ControllerType(className: className)

        switch controllerType {
        case .tabItem:
            return extractTabViewName(from: viewController)

        case .hostingController:
            if let output = SwiftUIViewPath.hostingController.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

            if let output = SwiftUIViewPath.hostingControllerRoot.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

        case .navigationController:
            // Try detail view first
            if let output = SwiftUIViewPath.navigationStackDetail.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

            // Check if it's a container view that we should ignore
            if SwiftUIViewPath.navigationStackContainer.traverse(with: reflector) != nil {
                return nil
            }

            // Try standard navigation stack view
            if let output = SwiftUIViewPath.navigationStack.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

        case .modal:
            if let output = SwiftUIViewPath.sheetContent.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

        case .unknown:
            break
        }

        return nil
    }

    // MARK: - Helpers
    private static let genericTypePattern: NSRegularExpression? = {
        return try? NSRegularExpression(pattern: #"<(?:[^,>]*,\s+)?([^<>,]+?)>"#)
    }()

    /// Extracts a view name from a type description
    internal func extractViewName(from input: String) -> String? {
        // Extract the view name from generic types like ParameterizedLazyView<String, DetailView>
        if let match = Self.genericTypePattern?.firstMatch(
            in: input,
            options: [],
            range: NSRange(input.startIndex..<input.endIndex, in: input)
        ),
           let range = Range(match.range(at: 1), in: input) {
            return String(input[range])
        }

        // Extract the view name from metatypes like DetailView.Type
        if input.hasSuffix(".Type") {
            return String(input.dropLast(5))
        }

        return nil
    }

    private func extractTabViewName(from viewController: UIViewController) -> String? {
        // We fetch the parent, which corresponds to the TabBarController
        guard let parent = viewController.parent as? UITabBarController,
              let container = parent.parent else {
            return nil
        }

        let selectedIndex = parent.selectedIndex
        let containerReflector = ReflectionMirror(reflecting: container)

        if let output = SwiftUIViewPath.hostingController.traverse(with: containerReflector) {
            let typeName = typeDescription(of: output)
            if let containerViewName = extractViewName(from: typeName) {
                return "\(containerViewName)_index_\(selectedIndex)"
            }
        }

        return nil
    }

    internal func shouldSkipViewController(viewController: UIViewController) -> Bool {
        // Skip Tab Bar Controllers as they're containers
        if viewController is UITabBarController {
            return true
        }

        // Skip Navigation Controllers
        if viewController is UINavigationController {
            return true
        }

        return false
    }

    private func typeDescription(of object: Any) -> String {
        return String(describing: type(of: object))
    }
}
