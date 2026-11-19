import FamilyControls
import ManagedSettings
import SwiftUI

struct ParentControlView: View {
    @ObservedObject var viewModel = ParentControlViewModel.shared
    @State private var isPickerPresented = false
    @State private var isSaving = false
    @State private var isRequestingAuthorization = false
    @State private var selectionLimitMessage: String?
    @State private var showSelectionLimitAlert = false
    @State private var showRemoveAllConfirmation = false
    @State private var tokensBeforePicker: Set<ApplicationToken> = []

    /// True briefly after the picker closes while the native Label(token) names render.
    /// Drives the loader overlay and disables Save until the names have settled.
    @State private var isResolvingNames = false

    // MARK: - Stable display order
    // Built once on appear / picker-close. Names resolve in-place without reordering.
    @State private var tokenOrder: [ApplicationToken] = []

    /// Tracks the active name-resolution Task so we can cancel it when
    /// the view disappears or a new resolution cycle starts.
    @State private var resolutionTask: Task<Void, Never>? = nil

    var onBack: (() -> Void)?
    var childId: String?

    private func tokenKey(_ token: ApplicationToken) -> String {
        (try? JSONEncoder().encode(token))?.base64EncodedString() ?? ""
    }

    // Stable-ordered list — positions never change mid-session.
    private var orderedStatuses: [AppBlockStatus] {
        let filtered = viewModel.appStatuses.filter { !viewModel.ownAppTokens.contains($0.token) }
        if tokenOrder.isEmpty { return filtered }
        let statusMap = Dictionary(uniqueKeysWithValues: filtered.map { ($0.token, $0) })
        let ordered = tokenOrder.compactMap { statusMap[$0] }
        // Append tokens added after the order was built (e.g. mid-session server sync)
        let extra = filtered.filter { !tokenOrder.contains($0.token) }
        return ordered + extra
    }

    // MARK: - Cache hydration

    /// Fills `appName` from UserDefaults cache for every token that still has an
    /// unresolved name. Call this before rendering the list so cached apps show
    /// names immediately without waiting for FamilyControlsAgent.
    private func hydrateNamesFromCache() {
        for status in viewModel.appStatuses {
            guard AppNameResolution.isUnresolved(status.appName) else { continue }
            let key = tokenKey(status.token)
            if let cached = AppNameResolutionCache.cachedName(forTokenStr: key) {
                viewModel.updateAppName(cached, for: status.token)
            }
        }
    }

    // Call this whenever the list changes to build a fresh alphabetical order.
    private func rebuildTokenOrder() {
        let filtered = viewModel.appStatuses.filter { !viewModel.ownAppTokens.contains($0.token) }
        tokenOrder = filtered.sorted {
            let a = sortKey($0.appName)
            let b = sortKey($1.appName)
            if a.isEmpty && b.isEmpty { return false }
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }.map(\.token)
    }

    private func sortKey(_ name: String?) -> String {
        let raw = name ?? ""
        let stripped = raw.hasPrefix("com.") ? String(raw.dropFirst(4)) : raw
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    /// Full-list loader shown while the app names are being fetched from their tokens.
    private var loadingOverlay: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).opacity(0.92)
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading app names…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let onBack = onBack {
                BackHeaderView(action: onBack)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select Apps to Block")
                        .font(.title2)
                        .fontWeight(.bold)
                    HStack {
                        Text("Up to \(ParentControlViewModel.maxSelectableApps) apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !viewModel.appStatuses.isEmpty {
                            Text("• \(viewModel.appStatuses.count) selected")
                                .font(.caption)
                                .foregroundColor(
                                    viewModel.appStatuses.count >= ParentControlViewModel.maxSelectableApps
                                        ? .red : Color("AppDarkBlue"))
                        }
                    }
                }
                Spacer()

                HStack(spacing: 12) {
                    if !viewModel.appStatuses.isEmpty {
                        Button(action: { showRemoveAllConfirmation = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.circle.fill")
                                Text("Remove All").font(.caption)
                            }
                            .foregroundColor(.red)
                        }
                    }

                    Button(action: {
                        tokensBeforePicker = viewModel.selection.applicationTokens
                        let status = AuthorizationCenter.shared.authorizationStatus
                        if status == .approved {
                            isPickerPresented = true
                        } else if status == .notDetermined {
                            Task {
                                do {
                                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                                    await MainActor.run {
                                        if AuthorizationCenter.shared.authorizationStatus == .approved {
                                            isPickerPresented = true
                                        }
                                    }
                                } catch {
                                    print("❌ Authorization failed: \(error)")
                                }
                            }
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(Color("AppDarkBlue"))
                    }
                }
                .familyActivityPicker(isPresented: $isPickerPresented, selection: $viewModel.selection)
            }
            .padding()

            if viewModel.appStatuses.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No apps selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap + to choose up to \(ParentControlViewModel.maxSelectableApps) apps. Select each app individually (do not use Select All).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    if viewModel.hasChanges && viewModel.appStatuses.isEmpty {
                        Text("All apps have been removed from the blocking list")
                            .font(.caption)
                            .foregroundColor(Color("AppDarkBlue"))
                            .padding(.top, 8)
                    }
                }
                .padding()
                Spacer()
            } else {
                let statuses = orderedStatuses

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Selected Apps (\(statuses.count)/\(ParentControlViewModel.maxSelectableApps))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 36)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(statuses, id: \.token) { status in
                                VStack(spacing: 0) {
                                    HStack {
                                        Button(action: {
                                            viewModel.toggleBlockStatus(for: status.token)
                                        }) {
                                            Image(systemName: status.isBlocked ? "checkmark.square.fill" : "square")
                                                .foregroundColor(status.isBlocked ? Color("AppDarkBlue") : .secondary)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())

                                        ParentAppLabel(status: status) { resolvedName in
                                            guard AppNameResolution.isResolved(resolvedName) else { return }
                                            Task { @MainActor in
                                                viewModel.updateAppName(resolvedName, for: status.token)
                                            }
                                        }

                                        Spacer()

                                        Button(action: {
                                            viewModel.removeApp(token: status.token)
                                            tokenOrder.removeAll { $0 == status.token }
                                            viewModel.syncAppsWithServer(childId: childId) { _ in }
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.system(size: 20))
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    Divider().padding(.leading, 52)
                                }
                            }
                            .onDelete(perform: { indexSet in
                                for index in indexSet {
                                    let status = statuses[index]
                                    viewModel.removeApp(token: status.token)
                                    tokenOrder.removeAll { $0 == status.token }
                                }
                                viewModel.syncAppsWithServer(childId: childId) { _ in }
                            })
                        }
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemGroupedBackground)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                    }
                }
                .background(Color(UIColor.systemGroupedBackground))
                .overlay {
                    if isResolvingNames {
                        loadingOverlay
                    }
                }
            }

            Button(action: {
                if viewModel.appStatuses.isEmpty {
                    isSaving = true
                    viewModel.removeOwnAppFromSelection()
                    viewModel.refreshAndSave()
                    if !UserDefaults.Main.bool(forKey: .isParent) {
                        viewModel.updateMonitoring()
                    }
                    Task {
                        viewModel.syncAppsWithServer(childId: childId) { success in
                            isSaving = false
                            if success, let onBack = onBack { onBack() }
                        }
                    }
                    return
                }

                let limitOutcome = viewModel.enforceMaxAppSelectionLimit()
                if case .selectAllNotAllowed = limitOutcome {
                    selectionLimitMessage = "Please select up to \(ParentControlViewModel.maxSelectableApps) apps individually. \"Select All\" is not supported."
                    showSelectionLimitAlert = true
                    return
                }
                if case .trimmed(let removed) = limitOutcome {
                    selectionLimitMessage = "Selection limited to \(ParentControlViewModel.maxSelectableApps) apps. \(removed) app(s) were removed."
                    showSelectionLimitAlert = true
                }

                isSaving = true
                viewModel.removeOwnAppFromSelection()
                viewModel.refreshAndSave()

                if !UserDefaults.Main.bool(forKey: .isParent) {
                    viewModel.updateMonitoring()
                }

                Task {
                    viewModel.syncAppsWithServer(childId: childId) { success in
                        isSaving = false
                        if success, let onBack = onBack { onBack() }
                    }
                }
            }) {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("AppDarkBlue"))
                    .cornerRadius(10)
            }
            .padding()
            .disabled(isSaving || isResolvingNames)
            .opacity((isSaving || isResolvingNames) ? 0.6 : 1.0)
        }
        .navigationTitle("Parental Control")
        .alert("App selection limit", isPresented: $showSelectionLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(selectionLimitMessage ?? "")
        }
        .alert("Remove All Apps", isPresented: $showRemoveAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                isSaving = true
                viewModel.removeAllApps()
                tokenOrder.removeAll()
                viewModel.syncAppsWithServer(childId: childId) { success in
                    isSaving = false
                    if success, let onBack = onBack { onBack() }
                }
            }
        } message: {
            Text("Are you sure you want to remove all \(viewModel.appStatuses.count) selected apps from the blocking list?")
        }
        .onChange(of: viewModel.appStatuses.count) { _, _ in
            ParentAppNameResolver.shared.resolve(viewModel.appStatuses.map(\.token))
        }
        .onChange(of: isPickerPresented) { _, presented in
            guard !presented, !isSaving else { return }

            viewModel.removeOwnAppFromSelection()
            let outcome = viewModel.enforceMaxAppSelectionLimit()

            switch outcome {
            case .selectAllNotAllowed:
                viewModel.selection.applicationTokens = tokensBeforePicker
                selectionLimitMessage = "Please select up to \(ParentControlViewModel.maxSelectableApps) apps individually. \"Select All\" is not supported."
                showSelectionLimitAlert = true
                return
            case .trimmed(let removed):
                selectionLimitMessage = "Selection limited to \(ParentControlViewModel.maxSelectableApps) apps. \(removed) app(s) were removed."
                showSelectionLimitAlert = true
            case .ok:
                break
            }

            // On picker "Done": run the Save flow immediately, show the loader, and pop
            // back to the previous screen — do NOT stay on ParentControlView.
            isSaving = true
            isResolvingNames = true
            viewModel.refreshAndSave()
            if !UserDefaults.Main.bool(forKey: .isParent) {
                viewModel.updateMonitoring()
            }
            Task {
                viewModel.syncAppsWithServer(childId: childId) { success in
                    isSaving = false
                    isResolvingNames = false
                    if success, let onBack = onBack { onBack() }
                }
            }
        }
        .onAppear {
            if AuthorizationCenter.shared.authorizationStatus == .notDetermined {
                Task {
                    do {
                        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    } catch {
                        print("❌ Authorization failed on appear: \(error)")
                    }
                }
            }
            viewModel.loadData(childId: childId)
            viewModel.removeOwnAppFromSelection()
            hydrateNamesFromCache()   // fills cached names instantly
            rebuildTokenOrder()
            // Parent only: look up names the on-screen Label(token) doesn't draw.
            ParentAppNameResolver.shared.resolve(viewModel.appStatuses.map(\.token))

            // Kill any leftover background resolver from a previous Save. Its off-screen
            // key window would suspend the on-screen Label(token) titles from rendering.
            resolutionTask?.cancel()
            resolutionTask = nil
            isResolvingNames = false
        }
    }
}

// MARK: - AppRowLabelStyle

/// Custom label style that places icon (32×32, rounded) + title side by side,
/// matching the existing row layout.
struct AppRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            configuration.title
                .font(.body)
                .foregroundColor(Color("AppDarkBlue"))
                .lineLimit(1)
        }
    }
}

// MARK: - ParentAppLabel

/// One row in the blocked-apps list.
///
/// `ApplicationToken` is opaque — there is NO public API to read its app name as a
/// `String`. The system renders the name only through `Label(token)`.
///
/// This row uses the SAME on-screen mechanism the rest of the app already uses
/// (`NameExtractorView`, see AppNameResolutionViews.swift) — NOT the off-screen
/// `resolveAllNamesInParallel` key-window hack that was blanking this screen:
///   • `Label(token).labelStyle(.iconOnly)` → the 32×32 rounded app icon
///   • `Label(token).labelStyle(.titleOnly)` → the real localized app name, shown by
///     the system directly so it is never blank (no dependence on a stored string)
///   • `NameExtractorView` (background) → captures the resolved name on-screen and
///     reports it via `onNameResolved` so the ViewModel can cache + sync it.
struct ParentAppLabel: View {
    let status: AppBlockStatus
    /// Called once the on-screen Label resolves the real app name (for cache + server sync).
    var onNameResolved: ((String) -> Void)? = nil

    private var resolvedName: String? {
        if AppNameResolution.isResolved(status.appName ?? "") { return status.appName }
        return ParentAppNameResolver.knownName(for: status.token)
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(status.token)
                .labelStyle(.iconOnly)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            // Parent: once ParentAppNameResolver has the name, show it as plain text —
            // `.titleOnly` alone can render blank. Child keeps the original behavior.
            if UserDefaults.Main.bool(forKey: .isParent),
               let name = resolvedName {
                Text(name)
                    .font(.body)
                    .foregroundColor(Color("AppDarkBlue"))
                    .lineLimit(1)
            } else {
                Label(status.token)
                    .labelStyle(.titleOnly)
                    .font(.body)
                    .foregroundColor(Color("AppDarkBlue"))
                    .lineLimit(1)
                    .background(
                        NameExtractorView(token: status.token) { name in
                            onNameResolved?(name)
                        }
                    )
            }
        }
    }
}

// MARK: - Helpers (file-scope)

// findLabelText and findAnyLabelText are defined in AppNameResolutionViews.swift

func findLabelImage(in view: UIView) -> UIImage? {
    if let imageView = view as? UIImageView, let img = imageView.image {
        return img
    }
    for sub in view.subviews {
        if let found = findLabelImage(in: sub) { return found }
    }
    return nil
}
