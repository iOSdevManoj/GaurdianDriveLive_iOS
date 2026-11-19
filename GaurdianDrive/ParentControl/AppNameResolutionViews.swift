// AppNameResolutionViews.swift
// Shared SwiftUI helpers used by CellForDurationList, CellForAppsList,
// ViewForReqAppSelection, etc. to resolve and display app names from ApplicationToken.

import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit

// MARK: - LabelWithNameCapture

/// Renders `Label(token).labelStyle(.titleOnly)` and fires `onNameResolved` once
/// FamilyControlsAgent provides the real app name.
struct LabelWithNameCapture: View {
    let token: ApplicationToken
    let onNameResolved: (String) -> Void

    var body: some View {
        Label(token)
            .labelStyle(.titleOnly)
            .background(
                NameExtractorView(token: token, onNameResolved: onNameResolved)
            )
    }
}

// MARK: - NameExtractorView

/// UIViewRepresentable that polls the UIKit hierarchy for text rendered by the
/// sibling `Label(token)` view. Handles iOS 15 (UILabel) and iOS 16+
/// (_UITextLayoutView exposed via accessibility). Scoped to the immediate
/// container to avoid cross-row contamination.
struct NameExtractorView: UIViewRepresentable {
    let token: ApplicationToken
    let onNameResolved: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Reset if token changed (view recycled for a different app)
        if context.coordinator.currentToken != token {
            context.coordinator.currentToken = token
            context.coordinator.hasResolved = false
            context.coordinator.isPolling = false
        }
        guard !context.coordinator.hasResolved else { return }
        // Guard: only start one poll loop per coordinator — SwiftUI calls updateUIView
        // on every parent re-render; without this guard we'd spawn dozens of overlapping
        // poll loops that swamp FamilyControlsAgent.
        guard !context.coordinator.isPolling else { return }
        context.coordinator.startPolling(from: uiView, onNameResolved: onNameResolved)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var hasResolved = false
        var isPolling = false
        var currentToken: ApplicationToken? = nil
        private var attempts = 0
        private let maxAttempts = 20  // 20 × 0.5s = 10s total

        func startPolling(from uiView: UIView, onNameResolved: @escaping (String) -> Void) {
            isPolling = true
            attempts = 0
            poll(from: uiView, onNameResolved: onNameResolved)
        }

        private func poll(from uiView: UIView, onNameResolved: @escaping (String) -> Void) {
            guard !hasResolved else { isPolling = false; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak uiView] in
                guard let self, !self.hasResolved, let uiView else {
                    self?.isPolling = false
                    return
                }

                // Walk up to 4 superview levels starting from our UIView's parent.
                // Stops at UIHostingController boundary to prevent cross-row contamination.
                var searchRoot: UIView? = uiView.superview
                for _ in 0..<4 {
                    guard let root = searchRoot else { break }
                    if let text = findAnyLabelText(in: root), AppNameResolution.isResolved(text) {
                        self.hasResolved = true
                        self.isPolling = false
                        onNameResolved(text)
                        return
                    }
                    if root.next is UIViewController { break }
                    searchRoot = root.superview
                }

                self.attempts += 1
                if self.attempts < self.maxAttempts {
                    self.poll(from: uiView, onNameResolved: onNameResolved)
                } else {
                    self.isPolling = false
                }
            }
        }
    }
}

// MARK: - Text finding helpers

/// Finds text from a UIKit view tree.
/// iOS 15: SwiftUI Text → UILabel
/// iOS 16+: SwiftUI Text → private _UITextLayoutView.
///   The view has `isAccessibilityElement = true` and its `accessibilityLabel`
///   contains the text. We intentionally do NOT require `subviews.isEmpty`
///   because _UITextLayoutView can have subviews (e.g. selection handles).
func findAnyLabelText(in view: UIView) -> String? {
    // Skip interactive inputs/buttons to avoid extracting placeholder or action text
    if view is UITextField || view is UIButton {
        return nil
    }
    // iOS 15: plain UILabel
    if let label = view as? UILabel, let text = label.text, !text.isEmpty {
        return text
    }
    // UITextView (some embedding contexts)
    if let tv = view as? UITextView, let text = tv.text, !text.isEmpty {
        return text
    }
    // iOS 16+: _UITextLayoutView — exposes text via accessibilityLabel.
    // NOTE: Do NOT add `view.subviews.isEmpty` here — _UITextLayoutView has
    // internal subviews and would always fail that check.
    if view.isAccessibilityElement,
       let acc = view.accessibilityLabel,
       !acc.isEmpty
    {
        return acc
    }
    for sub in view.subviews {
        if let found = findAnyLabelText(in: sub) { return found }
    }
    return nil
}

// MARK: - ParentAppNameResolver

/// Parent-side name lookup for the parent's OWN apps (Self Drive Control + Select Apps to
/// Block). Same technique as the child's `ChildHomeVC.resolveAllNamesSequentially`, kept
/// separate so the two flows can't affect each other: render `Label(token)` (automatic style —
/// `.titleOnly` draws no text on some iOS versions) one token at a time in a hidden
/// off-screen window, read the text, and cache it. Results go through
/// `ParentControlViewModel.updateAppName`, whose published `appStatuses` refreshes both screens.
@MainActor
final class ParentAppNameResolver {
    static let shared = ParentAppNameResolver()

    private var queue: [ApplicationToken] = []
    private var isRunning = false
    private var offscreen: UIWindow?

    /// Best known real name: name cache first, then the stored status name.
    static func knownName(for token: ApplicationToken) -> String? {
        if let data = try? JSONEncoder().encode(token),
           let cached = AppNameResolutionCache.cachedName(forTokenStr: data.base64EncodedString()) {
            return cached
        }
        let stored = ParentControlViewModel.shared.getAppName(for: token) ?? ""
        return AppNameResolution.isResolved(stored) ? stored : nil
    }

    /// Queues tokens with no known name. Safe to call repeatedly.
    func resolve(_ tokens: [ApplicationToken]) {
        guard UserDefaults.Main.bool(forKey: .isParent) else { return }
        for token in tokens where Self.knownName(for: token) == nil && !queue.contains(token) {
            queue.append(token)
        }
        guard !isRunning, !queue.isEmpty,
              let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
        else { return }

        isRunning = true
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -2000, y: 0, width: 300, height: 44)
        window.isHidden = false
        window.alpha = 0.01
        window.windowLevel = .normal - 1
        offscreen = window
        resolveNext()
    }

    private func resolveNext() {
        guard let window = offscreen, !queue.isEmpty else {
            offscreen?.isHidden = true
            offscreen?.rootViewController = nil
            offscreen = nil
            isRunning = false
            return
        }
        let token = queue.removeFirst()
        if Self.knownName(for: token) != nil { resolveNext(); return }

        let hc = UIHostingController(rootView: AnyView(
            Label(token)
                .labelStyle(.automatic)
                .frame(width: 300, height: 44)
        ))
        hc.view.frame = window.bounds
        hc.view.backgroundColor = .clear
        window.rootViewController = hc
        window.layoutIfNeeded()

        var attempts = 0
        func check() {
            if let name = findAnyLabelText(in: hc.view), AppNameResolution.isResolved(name) {
                if let data = try? JSONEncoder().encode(token) {
                    AppNameResolutionCache.store(name: name, forTokenStr: data.base64EncodedString())
                }
                ParentControlViewModel.shared.updateAppName(name, for: token)
                window.rootViewController = nil
                resolveNext()
            } else if attempts >= 12 {  // 12 × 0.4s ≈ 5s per token
                window.rootViewController = nil
                resolveNext()
            } else {
                attempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { check() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { check() }
    }
}
