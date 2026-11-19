import FamilyControls
import Foundation
import ManagedSettings
import SwiftData
import SwiftUI
import UIKit

enum AppSelectionLimitOutcome: Equatable {
    case ok
    case selectAllNotAllowed
    case trimmed(removedCount: Int)
}

class ParentControlViewModel: ObservableObject {
    static let shared = ParentControlViewModel()

    /// false = in-memory only, for the parent viewing a CHILD's app list (HomeVC "Manage Apps").
    /// Such an instance never reads or writes the SwiftData record, which on the parent device
    /// holds the parent's OWN self-drive list that AppBlockerManager shields from.
    let persistsLocally: Bool

    init(persistsLocally: Bool = true) {
        self.persistsLocally = persistsLocally
    }

    /// Maximum apps a parent can block individually (keeps name resolution and API sync reliable).
    static let maxSelectableApps = 30

    @Published var selection = FamilyActivitySelection(includeEntireCategory: true)
    @Published var appStatuses: [AppBlockStatus] = []
    @Published var allServerApps: [AppBlockStatus] = []
    @Published var hasChanges: Bool = false
    /// True when the picker "Select All" mode is active (applicationTokens is empty).
    @Published var isBlockAllMode: Bool = false
    private let apiCallViewModel = ApiCallViewModel()

    /// Tokens removed during this session, to be explicitly unblocked on the next server sync.
    private var deletedTokens = Set<String>()
    private var deletedTokenNames: [String: String] = [:]

    /// Tokens recently deleted, to prevent them from being re-added by incoming server GET requests.
    private var recentlyDeletedTokens: [String: Date] = [:]
    private let recentDeletionProtectionWindow: TimeInterval = 60.0

    /// Timestamp of the last successful save/sync. Used to skip redundant server fetches
    /// when the view re-appears shortly after a save (prevents removed apps from coming back).
    private var lastSyncDate: Date? = nil
    /// How long (seconds) after a save to suppress the server re-fetch on re-appear.
    private let postSyncFetchSuppressWindow: TimeInterval = 30.0

    private func base64Str(for token: ApplicationToken) -> String {
        (try? JSONEncoder().encode(token))?.base64EncodedString() ?? ""
    }

    /// Captured app icons from Label rendering — base64(token) → UIImage
    var capturedIcons: [String: UIImage] = [:]

    /// Prevents concurrent server syncs that cause HTTP 500 optimistic locking errors
    private var isSyncInProgress = false
    private var syncCompletions: [(Bool) -> Void] = []
    private var needsSyncAgain = false
    private var pendingChildId: String? = nil

    private var modelContext: ModelContext?
    private var shouldRemoveRequestedApps = false

    /// The UserDefaults key where we persist GuardianDrive's own ApplicationToken (Base64 JSON).
    private static let ownTokenUDKey = "GaurdianDrive_OwnAppToken"

    /// Returns the set of own-app tokens to exclude: persisted token + any name-matched ones.
    /// Exposed so `ParentControlView` can filter the ForEach list without extra logic.
    /// Cached set of own-app tokens for O(1) lookups during filtering.
    private var _cachedOwnAppTokens: Set<ApplicationToken>? = nil

    var ownAppTokens: Set<ApplicationToken> {
        if let cached = _cachedOwnAppTokens { return cached }

        var tokens = Set<ApplicationToken>()
        // Name-matched (works once names are resolved)
        for status in appStatuses {
            let name = (status.appName ?? "").lowercased()
            if name.contains("gaurdian") || name.contains("guardiandrive") {
                tokens.insert(status.token)
            }
        }
        // Persisted token (works on every subsequent run, even before names resolve)
        if let data = UserDefaults.standard.data(forKey: Self.ownTokenUDKey),
            let token = try? JSONDecoder().decode(ApplicationToken.self, from: data)
        {
            tokens.insert(token)
        }
        _cachedOwnAppTokens = tokens
        return tokens
    }

    @MainActor func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        // Only load if we don't already have data in memory
        if appStatuses.isEmpty {
            loadData()
        }
    }

    // MARK: - Data Loading & Saving

    /// Loads data only if not already loaded. Safe to call from UIKit before reading appStatuses.
    @MainActor func loadDataIfNeeded() async {
        if appStatuses.isEmpty {
            loadData()
        }
    }

    @MainActor func loadData(childId: String? = nil, completion: (() -> Void)? = nil) {
        guard persistsLocally else {
            fetchFromServer(childId: childId, completion: completion)
            return
        }
        // Auto-initialize context from the shared container if missing
        if modelContext == nil {
            AppBlockerManager.shared.ensureModelContainer()
            if let container = AppBlockerManager.shared.modelContainer {
                self.modelContext = container.mainContext
                print("[ViewModel] loadData: Context auto-initialized from AppBlockerManager.")
            }
        }

        guard let context = modelContext else {
            print("[ViewModel] loadData: No modelContext or container available. Aborting load.")
            return
        }

        do {
            let results = try context.fetch(FetchDescriptor<BlockingSelection>())
            if let saved = results.first {
                print(
                    "[ViewModel] Loaded saved state from SwiftData — \(saved.appStatuses.count) app statuses"
                )

                // appStatuses is the reliable ground truth (our own Codable struct).
                // Rebuild selection.applicationTokens FROM appStatuses instead of trusting
                // the opaque FamilyActivitySelection which may not round-trip correctly
                // through SwiftData after an app kill.
                self.appStatuses = saved.appStatuses
                self.selection = saved.selection
                // Parent: actually do what the comment above says. A saved selection holding
                // extra (old) tokens makes syncAppStatuses() — run on picker close, remove and
                // save — re-add those apps, so 3 picked apps turned into 6. Child unchanged.
                if UserDefaults.Main.bool(forKey: .isParent) {
                    let staleCount = selection.applicationTokens.count
                    selection.applicationTokens = Set(saved.appStatuses.map(\.token))
                    if staleCount != selection.applicationTokens.count {
                        print("[ViewModel] Parent: selection had \(staleCount) tokens, rebuilt to \(selection.applicationTokens.count) from appStatuses.")
                    }
                }
                self.isBlockAllMode = false
                UserDefaults.standard.set(false, forKey: "BlockAll_SelectAll")

                // Strip own app from persisted data
                removeOwnAppFromSelection()

                if appStatuses.count > Self.maxSelectableApps {
                    appStatuses = Array(appStatuses.prefix(Self.maxSelectableApps))
                    selection.applicationTokens = Set(appStatuses.map(\.token))
                    hasChanges = true
                    print(
                        "[ViewModel] Trimmed saved list to \(Self.maxSelectableApps) apps"
                    )
                }

                print(
                    "[ViewModel] Restored \(self.appStatuses.count) app statuses, \(self.selection.applicationTokens.count) tokens in selection."
                )
            } else {
                print("[ViewModel] No saved selection found in SwiftData")
            }

            // Fetch fresh state from server — but skip if we just saved (prevents removed apps
            // from being re-added by a stale server response within the suppression window).
            let suppressFetch: Bool
            if let lastSync = lastSyncDate,
                Date().timeIntervalSince(lastSync) < postSyncFetchSuppressWindow
            {
                suppressFetch = true
                print(
                    "[ViewModel] loadData: Skipping server fetch — within \(Int(postSyncFetchSuppressWindow))s post-sync window."
                )
            } else {
                suppressFetch = false
            }
            if !suppressFetch {
                fetchFromServer(childId: childId, completion: completion)
            } else {
                completion?()
            }

        } catch {
            print("[ViewModel] Failed to fetch data: \(error)")
            completion?()
        }
    }

    /// Fetches the current blocked app list from the server and merges it into local state.
    /// This ensures that if the parent switched devices or cleared data, they still see
    /// what is currently active on the server.
    @MainActor func fetchFromServer(childId: String? = nil, completion: (() -> Void)? = nil) {
        let resolvedId = childId ?? AppState.sharedInstance.user?.userId ?? ""
        guard !resolvedId.isEmpty else { completion?(); return }

        // Parent's OWN self-drive list: this device is the source of truth (tokens only work
        // on the device that picked them); the server copy is just a mirror. Merging it into a
        // non-empty local list can apply a stale copy — re-adding removed apps and deleting
        // newly picked ones. Only use it to restore an empty list (e.g. after reinstall).
        if childId == nil, persistsLocally, UserDefaults.Main.bool(forKey: .isParent),
           !appStatuses.isEmpty {
            print("[ViewModel] Parent own list — keeping local list, skipping server merge.")
            completion?()
            return
        }

        print("[ViewModel] Fetching apps from server for ID: \(resolvedId)")
        let url = WebURL.getChildApps(childId: resolvedId)
        apiCallViewModel.getApiCallWithDisctionaryResponse(aUrl: url, aParams: [:]) {
            [weak self] (success, dict) in
            guard let self = self, success, let appsArray = dict["apps"] as? [[String: Any]] else {
                print("[ViewModel] Server fetch failed or returned no apps.")
                DispatchQueue.main.async { completion?() }
                return
            }

            Task { @MainActor in
                var updated = false
                var newAllServerApps: [AppBlockStatus] = []
                var serverTokens = Set<ApplicationToken>()
                for item in appsArray {
                    let rawTokenStr = item["token"] as? String ?? item["_id"] as? String ?? ""
                    let tokenStr = rawTokenStr.components(separatedBy: "___").first ?? rawTokenStr
                    guard let tokenData = Data(base64Encoded: tokenStr),
                        let token = try? JSONDecoder().decode(
                            ApplicationToken.self, from: tokenData)
                    else { continue }
                    serverTokens.insert(token)

                    let name =
                        item["name"] as? String ?? item["appName"] as? String ?? "Unknown App"

                    var resolvedName = name
                    if !AppNameResolution.isResolved(resolvedName),
                        let cached = AppNameResolutionCache.cachedName(forTokenStr: tokenStr)
                    {
                        resolvedName = cached
                    }
                    if resolvedName.contains(".") {
                        resolvedName = AppNameResolution.cleanBundleId(resolvedName)
                    }

                    let blockFlag = "\(item["a"] ?? "0")"
                    let isBlocked = (blockFlag == "1" || blockFlag == "true")

                    if !self.ownAppTokens.contains(token) {
                        newAllServerApps.append(
                            AppBlockStatus(
                                token: token, isBlocked: isBlocked, appName: resolvedName))
                    }

                    // Check protection window for recently deleted tokens
                    if let deletionDate = self.recentlyDeletedTokens[tokenStr] {
                        if Date().timeIntervalSince(deletionDate)
                            < self.recentDeletionProtectionWindow
                        {
                            print(
                                "[ViewModel] Ignoring server app within recent deletion protection window: \(resolvedName)"
                            )
                            continue
                        } else {
                            // Expired, clean up
                            self.recentlyDeletedTokens.removeValue(forKey: tokenStr)
                        }
                    }

                    if self.deletedTokens.contains(tokenStr) {
                        print(
                            "[ViewModel] Ignoring server app pending local removal: \(resolvedName)"
                        )
                        continue
                    }

                    // Don't process the own app
                    if self.ownAppTokens.contains(token) { continue }

                    // ✅ Skip entries with garbage names from old broken syncs
                    let isGarbageName =
                        AppNameResolution.isUnresolved(resolvedName)
                        || resolvedName.hasPrefix("com.") || resolvedName.hasPrefix("org.")

                    if let index = self.appStatuses.firstIndex(where: { $0.token == token }) {
                        // Exists locally: Sync status and name
                        if !isBlocked {
                            // Server says unblocked -> remove from local list
                            print(
                                "[ViewModel] Removing server-unblocked app: \(self.appStatuses[index].appName ?? resolvedName)"
                            )
                            self.appStatuses.remove(at: index)
                            self.selection.applicationTokens.remove(token)
                            updated = true
                        } else {
                            // Server says blocked: Update name only if server has a REAL name
                            let localName = self.appStatuses[index].appName ?? ""
                            let localIsUnresolved = AppNameResolution.isUnresolved(localName)
                            if localIsUnresolved && !isGarbageName {
                                self.appStatuses[index].appName = resolvedName
                                updated = true
                            }
                            // Ensure it's marked as blocked locally if not already
                            if !self.appStatuses[index].isBlocked {
                                self.appStatuses[index].isBlocked = true
                                self.selection.applicationTokens.insert(token)
                                updated = true
                            }
                        }
                    } else if isBlocked {
                        // New app from server — add it locally even if name is unresolved
                        print("[ViewModel] Adding missing server-blocked app: \(resolvedName)")
                        self.appStatuses.append(
                            AppBlockStatus(token: token, isBlocked: true, appName: resolvedName))
                        self.selection.applicationTokens.insert(token)
                        updated = true
                    }
                }

                self.allServerApps = newAllServerApps.sorted {
                    ($0.appName ?? "").localizedCaseInsensitiveCompare($1.appName ?? "")
                        == .orderedAscending
                }

                // Clean up local apps that were completely deleted from the server
                let isParent = UserDefaults.Main.bool(forKey: .isParent)
                if !isParent || !self.hasChanges {
                    for i in (0..<self.appStatuses.count).reversed() {
                        let localToken = self.appStatuses[i].token
                        if !serverTokens.contains(localToken) && !self.ownAppTokens.contains(localToken) {
                            print(
                                "[ViewModel] Removing locally an app that was completely deleted from server: \(self.appStatuses[i].appName ?? "Unknown")"
                            )
                            self.appStatuses.remove(at: i)
                            self.selection.applicationTokens.remove(localToken)
                            updated = true
                        }
                    }
                }

                if updated {
                    self.writeToSwiftData()
                    self._cachedOwnAppTokens = nil
                    // NOTE: name resolution is now done ON-SCREEN, per row, by
                    // ParentControlView's NameExtractorView. We must NOT trigger the
                    // off-screen `resolveAllNamesInParallel` here — its key window
                    // (makeKeyAndVisible) suspends the visible Label(token) titles and
                    // leaves rows blank. Names render natively and are captured per row.
                }
                completion?()
            }
        }
    }

    @MainActor func saveData() {
        // Always scrub own app before writing to disk
        removeOwnAppFromSelection()
        writeToSwiftData()
    }

    /// Syncs selection → appStatuses, then persists to SwiftData.
    /// Call this after the FamilyActivityPicker closes on the parent path
    /// (where the picker updates selection.applicationTokens directly with no
    /// name-resolution step, so appStatuses must be rebuilt before saving).
    @MainActor func refreshAndSave() {
        removeOwnAppFromSelection()
        syncAppStatuses()
        writeToSwiftData()
    }

    /// Removes a specific app from the blocking list
    @MainActor func removeApp(token: ApplicationToken) {
        print(
            "🗑️ [ParentControl] Removing app with token: \(String(describing: token).prefix(12))...")

        // Store token for deletion tracking (for server sync)
        let tokenStr = base64Str(for: token)
        if !tokenStr.isEmpty {
            deletedTokens.insert(tokenStr)
            recentlyDeletedTokens[tokenStr] = Date()
            if let status = appStatuses.first(where: { $0.token == token }),
                let name = status.appName
            {
                deletedTokenNames[tokenStr] = name
                print("🗑️ [ParentControl] Removing app: '\(name)'")
            }
        }

        // Remove from selection and app statuses
        selection.applicationTokens.remove(token)
        appStatuses.removeAll { $0.token == token }
        hasChanges = true

        // Save changes
        refreshAndSave()

        print("✅ [ParentControl] App removed from blocking list")
    }

    /// Removes all selected apps from the blocking list
    @MainActor func removeAllApps() {
        print("🗑️ [ParentControl] Removing all \(appStatuses.count) selected apps")

        // Store tokens for deletion tracking (for server sync)
        let now = Date()
        for status in appStatuses {
            let tokenStr = base64Str(for: status.token)
            if !tokenStr.isEmpty {
                deletedTokens.insert(tokenStr)
                recentlyDeletedTokens[tokenStr] = now
                if let name = status.appName {
                    deletedTokenNames[tokenStr] = name
                }
            }
        }

        // Clear all selections
        selection = FamilyActivitySelection(includeEntireCategory: true)
        appStatuses.removeAll()
        isBlockAllMode = false
        UserDefaults.standard.set(false, forKey: "BlockAll_SelectAll")
        hasChanges = true
        shouldRemoveRequestedApps = true

        // Clear cached own app tokens to force refresh
        _cachedOwnAppTokens = nil

        // Save changes
        refreshAndSave()

        print("✅ [ParentControl] All apps removed from blocking list")
    }

    /// Enforces the 30-app cap. Call after the Family Activity Picker closes or before Save.
    @MainActor func enforceMaxAppSelectionLimit() -> AppSelectionLimitOutcome {
        removeOwnAppFromSelection()

        if selection.applicationTokens.isEmpty {
            isBlockAllMode = false
            UserDefaults.standard.set(false, forKey: "BlockAll_SelectAll")
            return .selectAllNotAllowed
        }

        let max = Self.maxSelectableApps
        let currentCount = selection.applicationTokens.count

        if currentCount > max {
            // Create a more predictable ordering: alphabetical by app name
            var orderedApps: [(token: ApplicationToken, name: String)] = []

            // First, get apps that have resolved names
            for status in appStatuses where selection.applicationTokens.contains(status.token) {
                let name = status.appName ?? "Unknown App"
                orderedApps.append((token: status.token, name: name))
            }

            // Then add any remaining tokens that don't have status entries
            for token in selection.applicationTokens {
                if !orderedApps.contains(where: { $0.token == token }) {
                    orderedApps.append((token: token, name: "Unknown App"))
                }
            }

            // Sort alphabetically by name for consistent, predictable ordering
            orderedApps.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            let removed = currentCount - max
            let keptApps = Array(orderedApps.prefix(max))
            selection.applicationTokens = Set(keptApps.map { $0.token })

            isBlockAllMode = false
            UserDefaults.standard.set(false, forKey: "BlockAll_SelectAll")
            hasChanges = true

            print("🔢 [Limit] Trimmed \(removed) apps, kept first \(max) alphabetically")
            return .trimmed(removedCount: removed)
        }

        // No trimming needed, but ensure consistent state
        isBlockAllMode = false
        UserDefaults.standard.set(false, forKey: "BlockAll_SelectAll")
        return .ok
    }

    /// Raw SwiftData write — does NOT call syncAppStatuses or saveData.
    /// Use this as the single, non-recursive persistence point.
    /// Must run on @MainActor because modelContext is container.mainContext.
    @MainActor func writeToSwiftData() {
        guard persistsLocally else { return }
        guard let context = modelContext else {
            print("[ViewModel] ⚠️ writeToSwiftData skipped — no modelContext (changes NOT saved).")
            return
        }
        do {
            let results = try context.fetch(FetchDescriptor<BlockingSelection>())
            if let existing = results.first {
                existing.selection = self.selection
                existing.appStatuses = self.appStatuses
                existing.categoryStatuses = []  // Empty since we're hiding categories
            } else {
                context.insert(
                    BlockingSelection(
                        selection: self.selection,
                        appStatuses: self.appStatuses,
                        categoryStatuses: []
                    ))
            }

            try context.save()
            print("[ViewModel] Successfully saved state.")
        } catch {
            print(
                "[ViewModel] Failed to save state: \(error) (Non-critical: will retry on next UI update)"
            )
        }
    }

    // MARK: - App Selection Management

    @MainActor func selectApp(token: ApplicationToken, name: String?) {
        selection.applicationTokens.insert(token)

        // Update name map if provided
        var map: [ApplicationToken: String] = [:]
        if let name = name {
            map[token] = name
        }

        _cachedOwnAppTokens = nil  // Invalidate cache
        syncAppStatuses(updatedNames: map)
    }

    @MainActor func deselectApp(token: ApplicationToken) {
        selection.applicationTokens.remove(token)
        hasChanges = true  // local change — needs server sync
        _cachedOwnAppTokens = nil  // Invalidate cache
        syncAppStatuses()
        if !UserDefaults.Main.bool(forKey: .isParent) {
            // Child: sync immediately; hasChanges is cleared on completion.
            syncAppsWithServer()
        }
    }

    @MainActor func deleteApps(at offsets: IndexSet) {
        let tokens = Array(selection.applicationTokens)
        for index in offsets {
            let tokenToRemove = tokens[index]
            selection.applicationTokens.remove(tokenToRemove)
        }
        hasChanges = true  // local change — needs server sync
        _cachedOwnAppTokens = nil  // Invalidate cache
        syncAppStatuses()
        if !UserDefaults.Main.bool(forKey: .isParent) {
            // Child: sync immediately; hasChanges is cleared on completion.
            syncAppsWithServer()
        }
    }

    // MARK: - Status Management

    func isBlocked(_ token: ApplicationToken) -> Bool {
        return appStatuses.first(where: { $0.token == token })?.isBlocked ?? true
    }

    func getAppName(for token: ApplicationToken) -> String? {
        return appStatuses.first(where: { $0.token == token })?.appName
    }

    /// Called when a Label(token) resolves the real app name — persists it for future sorting.
    @MainActor func updateAppName(_ name: String, for token: ApplicationToken) {
        guard let index = appStatuses.firstIndex(where: { $0.token == token }) else { return }
        guard appStatuses[index].appName != name else { return }

        appStatuses[index].appName = name
        hasChanges = true
        _cachedOwnAppTokens = nil  // Invalidate cache
        writeToSwiftData()

        if let tokenData = try? JSONEncoder().encode(token) {
            let tokenStr = tokenData.base64EncodedString()
            AppNameResolutionCache.store(name: name, forTokenStr: tokenStr)
        }

        // Note: Caller should batch sync to server to avoid excessive API calls
        print("✅ [ViewModel] Name resolved: \(name)")
    }

    /// Stores a captured icon image keyed by base64(token) for use during server sync.
    func storeIcon(_ image: UIImage, forKey key: String) {
        capturedIcons[key] = image
    }

    /// Returns a cached icon image for the given key, or nil if not yet resolved.
    func cachedIcon(forKey key: String) -> UIImage? {
        return capturedIcons[key]
    }

    /// Resolves app names one token at a time. FamilyControlsAgent cannot reliably
    /// resolve hundreds of Label(token) views created in parallel.
    @MainActor func resolveAllNamesInParallel() async {
        let unresolved = appStatuses.filter { AppNameResolution.isUnresolved($0.appName) }
        guard !unresolved.isEmpty else {
            print("✅ [ViewModel] No names need resolution")
            return
        }

        // 1. Fast path: check persistent cache token-wise first
        for status in unresolved {
            if let tokenData = try? JSONEncoder().encode(status.token) {
                let tokenStr = tokenData.base64EncodedString()
                if let cached = AppNameResolutionCache.cachedName(forTokenStr: tokenStr) {
                    updateAppName(cached, for: status.token)
                }
            }
        }

        // 2. Filter again to see if anything is still unresolved
        let remainingUnresolved = appStatuses.filter { AppNameResolution.isUnresolved($0.appName) }
        guard !remainingUnresolved.isEmpty else {
            print("✅ [ViewModel] All names resolved from cache")
            return
        }

        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            print("⚠️ [ViewModel] FamilyControls not authorized — skipping name resolution")
            return
        }

        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
        else {
            print("⚠️ [ViewModel] No window scene for name resolution")
            return
        }

        print("🔍 [ViewModel] Resolving \(remainingUnresolved.count) app names sequentially...")

        // Save the current key window so we can restore it after resolution.
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }

        // Position the window off the RIGHT edge so it's never visible,
        // but use alpha = 1.0 and makeKeyAndVisible() so FamilyControlsAgent
        // treats it as a fully active window and populates Label text.
        // (With alpha = 0.01 or windowLevel < .normal, FamilyControlsAgent
        //  skips the window and labels stay blank.)
        let screenWidth = windowScene.screen.bounds.width
        let resolutionWindow = UIWindow(windowScene: windowScene)
        resolutionWindow.frame = CGRect(x: screenWidth + 10, y: 0, width: 300, height: 44)
        resolutionWindow.backgroundColor = .white
        resolutionWindow.windowLevel = .normal
        resolutionWindow.makeKeyAndVisible()  // Key window = full FamilyControlsAgent priority

        var resolvedCount = 0
        for status in remainingUnresolved {
            if Task.isCancelled { break }
            let token = status.token

            let hc = UIHostingController(
                rootView: AnyView(
                    Label(token)
                        .labelStyle(.automatic)
                        .frame(width: 300, height: 44)
                        .background(Color.white)
                )
            )
            hc.view.frame = resolutionWindow.bounds
            hc.view.backgroundColor = .white
            resolutionWindow.rootViewController = hc
            resolutionWindow.layoutIfNeeded()

            // Give FamilyControlsAgent time to populate the label (key window → fast response)
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Poll up to 6 × 0.5s = 3s max per token
            let maxAttempts = 6
            for _ in 0..<maxAttempts {
                if Task.isCancelled { break }
                guard hc.view.window != nil else { break }
                if let name = findLabelText(in: hc.view), AppNameResolution.isResolved(name) {
                    updateAppName(name, for: token)
                    resolvedCount += 1
                    print("✅ [ViewModel] Resolved: \(name)")
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            resolutionWindow.rootViewController = nil
        }

        // Restore the original key window
        resolutionWindow.isHidden = true
        previousKeyWindow?.makeKeyAndVisible()

        print(
            "✅ [ViewModel] Name resolution finished — \(resolvedCount)/\(remainingUnresolved.count) resolved"
        )
        
        if resolvedCount > 0 && !UserDefaults.Main.bool(forKey: .isParent) {
            if hasChanges {
                syncAppsWithServer()
            }
        }
    }

    /// Resolves app names for all tokens that have nil/Unknown names.
    @MainActor func resolveAppNamesIfNeeded() {
        Task { @MainActor in
            await resolveAllNamesInParallel()
        }
    }

    // Delegates to the shared findAnyLabelText (AppNameResolutionViews.swift)
    // which handles both iOS 15 (UILabel) and iOS 16+ (_UITextLayoutView / accessibility).
    private func findLabelText(in view: UIView) -> String? {
        return findAnyLabelText(in: view)
    }

    @MainActor func toggleBlockStatus(for token: ApplicationToken) {
        if let index = appStatuses.firstIndex(where: { $0.token == token }) {
            // In the current UI, unchecking a blocked app should remove it from the list.
            if appStatuses[index].isBlocked {
                appStatuses[index].isBlocked = false
                selection.applicationTokens.remove(token)
                let tokenStr = base64Str(for: token)
                if !tokenStr.isEmpty {
                    if let name = appStatuses[index].appName {
                        deletedTokenNames[tokenStr] = name
                    }
                    deletedTokens.insert(tokenStr)
                    recentlyDeletedTokens[tokenStr] = Date()
                }
                appStatuses.remove(at: index)
                hasChanges = true
                _cachedOwnAppTokens = nil  // Invalidate cache
            }
        }
        writeToSwiftData()
    }

    @MainActor func updateMonitoring() {
        let isParent = UserDefaults.Main.bool(forKey: .isParent)

        var blockedSelection = FamilyActivitySelection(includeEntireCategory: true)
        let blockedTokens = appStatuses.filter { $0.isBlocked }.map { $0.token }
        blockedSelection.applicationTokens = Set(blockedTokens)
        blockedSelection.categoryTokens = selection.categoryTokens
        blockedSelection.webDomainTokens = selection.webDomainTokens

        if isParent {
            saveData()
            AppBlockerManager.shared.reEvaluateSpeed()
        } else {
            AppBlockerManager.shared.startMonitoring(selection: blockedSelection)
        }
    }

    /// Called ONLY when the user explicitly taps "Block Selected".
    /// This is the only path that immediately applies shields regardless of speed.
    @MainActor func applyManualBlockNow() {
        var blockedSelection = FamilyActivitySelection(includeEntireCategory: true)
        let blockedTokens = appStatuses.filter { $0.isBlocked }.map { $0.token }
        blockedSelection.applicationTokens = Set(blockedTokens)
        blockedSelection.categoryTokens = selection.categoryTokens
        blockedSelection.webDomainTokens = selection.webDomainTokens

        if UserDefaults.Main.bool(forKey: .isParent) {
            // Parent: directly block specific selected apps on their own device.
            AppBlockerManager.shared.applyParentManualBlock(selection: blockedSelection)
        } else {
            // Child: persist to SwiftData and trigger the .all(except: approvedTokens) shield.
            // This respects the no-token-limit approach and approved app exceptions.
            AppBlockerManager.shared.startMonitoring(selection: blockedSelection)
        }
    }

    @MainActor func unblockAll() {
        for index in appStatuses.indices {
            appStatuses[index].isBlocked = false
        }
        hasChanges = true
        saveData()

        if UserDefaults.Main.bool(forKey: .isParent) {
            // Parent: wipe local shields directly.
            AppBlockerManager.shared.clearParentBlock()
        } else {
            // Child: stop monitoring and clear shields.
            AppBlockerManager.shared.stopMonitoring()
        }
    }

    // MARK: - Logic Helpers

    /// Removes the GuardianDrive app itself from the selection so it can never be blocked.
    /// Internal so `ParentControlView` can call it immediately after the system picker closes.
    func removeOwnAppFromSelection() {
        let toRemove = ownAppTokens
        guard !toRemove.isEmpty else { return }

        // Persist any newly name-resolved own tokens so future calls work without a name
        for token in toRemove {
            if let data = try? JSONEncoder().encode(token) {
                UserDefaults.standard.set(data, forKey: Self.ownTokenUDKey)
            }
        }

        for token in toRemove {
            selection.applicationTokens.remove(token)
            appStatuses.removeAll { $0.token == token }
        }
        print("[ParentControl] Removed \(toRemove.count) GuardianDrive token(s) from selection.")
    }

    @MainActor func syncAppStatuses(updatedNames: [ApplicationToken: String]? = nil) {
        isBlockAllMode = false
        UserDefaults.standard.set(false, forKey: "BlockAll_SelectAll")

        let now = Date()
        for i in (0..<appStatuses.count).reversed() {
            let token = appStatuses[i].token
            if !selection.applicationTokens.contains(token) {
                let tokenStr = base64Str(for: token)
                if !tokenStr.isEmpty {
                    if let name = appStatuses[i].appName {
                        deletedTokenNames[tokenStr] = name
                    }
                    deletedTokens.insert(tokenStr)
                    recentlyDeletedTokens[tokenStr] = now
                }
                appStatuses.remove(at: i)
                hasChanges = true
            } else if let newName = updatedNames?[token] {
                appStatuses[i].appName = newName
            }
        }

        for token in selection.applicationTokens {
            guard
                appStatuses.count < Self.maxSelectableApps
                    || appStatuses.contains(where: { $0.token == token })
            else { break }
            if !appStatuses.contains(where: { $0.token == token }) {
                var name = updatedNames?[token]
                let tokenStr = base64Str(for: token)
                if name == nil || AppNameResolution.isUnresolved(name) {
                    if !tokenStr.isEmpty {
                        if let cached = AppNameResolutionCache.cachedName(forTokenStr: tokenStr) {
                            name = cached
                        }
                    }
                }
                let finalName = name ?? "Unknown App"
                appStatuses.append(
                    AppBlockStatus(token: token, isBlocked: true, appName: finalName))
                if !tokenStr.isEmpty {
                    deletedTokens.remove(tokenStr)
                }
                hasChanges = true
            }
        }
        print(
            "[ViewModel] \(selection.applicationTokens.count) picker token(s) — list shows \(appStatuses.count)/\(Self.maxSelectableApps) app(s)"
        )
    }

    // MARK: - API Integration

    func syncAppsWithServer(childId: String? = nil, completion: @escaping (Bool) -> Void = { _ in })
    {
        let resolvedId = childId ?? AppState.sharedInstance.user?.userId ?? ""
        if resolvedId.isEmpty {
            print("[ViewModel] Error: No childId or userId found for sync")
            completion(false)
            return
        }

        // Add this completion to our list
        syncCompletions.append(completion)

        // Prevent concurrent syncs — HTTP 500 optimistic locking errors
        guard !isSyncInProgress else {
            print("[ViewModel] ⏭ Sync already in progress — queueing request and completion")
            needsSyncAgain = true
            pendingChildId = resolvedId
            return
        }
        isSyncInProgress = true

        print("[ViewModel] Syncing apps with server...")
        executeFinalSync(childId: resolvedId)
    }

    /// Performs the actual server sync once names are ready.
    private func executeFinalSync(childId: String) {
        let ownTokens = ownAppTokens

        // Snapshot deleted tokens — used in the merge step below
        let tokensToUnblock = deletedTokens
        let tokenNamesToUnblock = deletedTokenNames

        // Build payload for currently blocked apps.
        // Unresolved names are sent as "Unknown App" so the child device receives the token
        // and can resolve the real name via FamilyControls Label(token) locally.
        var pendingNameCount = 0
        var appsPayload: [[String: Any]] = appStatuses.compactMap { status -> [String: Any]? in
            guard !ownTokens.contains(status.token) else { return nil }
            guard let data = try? JSONEncoder().encode(status.token) else { return nil }
            let tokenStr = data.base64EncodedString()

            let rawName = status.appName ?? ""
            var syncName: String
            if AppNameResolution.isResolved(rawName) {
                syncName = rawName
            } else if let cached = AppNameResolutionCache.cachedName(forTokenStr: tokenStr) {
                syncName = cached
            } else {
                pendingNameCount += 1
                syncName = "Unknown App"
            }

            print("[ViewModel] Syncing app: \(syncName)")

            return [
                "name": syncName,
                "token": tokenStr,
                "deviceType": "IOS",
                "icon": "",
                "a": status.isBlocked ? "1" : "0",
            ]
        }

        if pendingNameCount > 0 {
            print(
                "ℹ️ [ViewModel] \(pendingNameCount) app(s) synced with placeholder name — child will resolve"
            )
        }

        // We no longer append deleted tokens with a: "0" because the backend treats
        // any app in the sync payload as blocked. Omitting them will remove them.

        // Build a set of all token strings that are explicitly handled in our payload
        // (both blocked a=1 and unblocked a=0) — used to filter the server merge below
        let handledTokenStrings = Set(appsPayload.compactMap { $0["token"] as? String })

        appDelegate.showHud()

        func executeSyncCall(
            payload: [[String: Any]], childId: String, onDone: @escaping (Bool) -> Void
        ) {
            let url = WebURL.childAppsSync(childId: childId)
            let params: [String: Any] = ["apps": payload]
            apiCallViewModel.putMethodApiCallWithDisctionaryResponse(aUrl: url, param: params) {
                (isSuccess, _) in
                onDone(isSuccess)
            }
        }

        let fetchUrl = WebURL.getChildApps(childId: childId)
        apiCallViewModel.getApiCallWithDisctionaryResponse(aUrl: fetchUrl, aParams: [:]) {
            [weak self] (success, dict) in
            guard let self = self else {
                appDelegate.hideHud()
                return
            }
            var finalPayload = appsPayload
            let isBlockAll = UserDefaults.standard.bool(forKey: "BlockAll_SelectAll")

            if isBlockAll, success, let appsArray = dict["apps"] as? [[String: Any]] {
                var blockAllPayload: [[String: Any]] = []
                var seenTokens = Set<String>()

                for item in appsArray {
                    let serverToken = item["token"] as? String ?? item["_id"] as? String ?? ""
                    guard !serverToken.isEmpty, !seenTokens.contains(serverToken) else { continue }
                    seenTokens.insert(serverToken)

                    let serverName = item["name"] as? String ?? "Unknown App"
                    let syncName =
                        AppNameResolution.isResolved(serverName) ? serverName : "Unknown App"
                    blockAllPayload.append([
                        "name": syncName,
                        "token": serverToken,
                        "deviceType": "IOS",
                        "icon": "",
                        "a": "1",
                    ])
                }

                for status in self.appStatuses where !ownTokens.contains(status.token) {
                    guard let data = try? JSONEncoder().encode(status.token) else { continue }
                    let tokenStr = data.base64EncodedString()
                    guard !seenTokens.contains(tokenStr) else { continue }
                    seenTokens.insert(tokenStr)
                    let rawName = status.appName ?? ""
                    let syncName = AppNameResolution.isResolved(rawName) ? rawName : "Unknown App"
                    blockAllPayload.append([
                        "name": syncName,
                        "token": tokenStr,
                        "deviceType": "IOS",
                        "icon": "",
                        "a": "1",
                    ])
                }

                finalPayload = blockAllPayload
                print(
                    "[ViewModel] Block-all sync — marking \(finalPayload.count) app(s) blocked on server"
                )
            } else if success, let appsArray = dict["apps"] as? [[String: Any]] {
                for item in appsArray {
                    let serverToken = item["token"] as? String ?? item["_id"] as? String ?? ""
                    guard !serverToken.isEmpty else { continue }

                    guard let tokenData = Data(base64Encoded: serverToken),
                        let decodedToken = try? JSONDecoder().decode(
                            ApplicationToken.self, from: tokenData)
                    else { continue }

                    // Skip tokens already handled in our payload (both blocked and unblocked explicitly)
                    guard !handledTokenStrings.contains(serverToken) else { continue }

                    let serverStatus =
                        (item["status"] as? String ?? item["currentStatus"] as? String ?? "")
                        .uppercased()
                    let serverName = item["name"] as? String ?? ""
                    let isGarbage =
                        serverName.isEmpty
                        || serverName == "Unknown App" || serverName == "Unknown"
                        || serverName == "Removed App" || serverName == "Sync Failed"
                        || serverName == "Name" || serverName == "Pending Resolution..."
                        || serverName.hasPrefix("com.") || serverName.hasPrefix("org.")

                    // Check if server considers this app blocked (a == "1" or a == 1 or a == "true")
                    let serverAFlag = "\(item["a"] ?? "0")"

                    if serverStatus == "REQUESTED" && !isGarbage && !self.shouldRemoveRequestedApps
                    {
                        // Preserve child-requested apps not in our local list.
                        // Since the backend sets a=1 for anything we send, this keeps it blocked
                        // but visible as requested, which is the correct state for pending requests.
                        finalPayload.append([
                            "name": serverName,
                            "token": serverToken,
                            "deviceType": "IOS",
                            "icon": "",
                            "a": "1",
                        ])
                    }
                    // We no longer force unblock via else branch because the backend ignores a: "0".
                    // Simply omitting the app from the payload causes the backend to remove it.
                    // Already-unblocked server entries are dropped — no action needed
                }
            }

            executeSyncCall(payload: finalPayload, childId: childId) { success in
                appDelegate.hideHud()
                if success {
                    self.hasChanges = false
                    self.shouldRemoveRequestedApps = false

                    // Clear the snapshot/successfully synced deleted tokens here!
                    for token in tokensToUnblock {
                        self.deletedTokens.remove(token)
                        self.deletedTokenNames.removeValue(forKey: token)
                    }

                    print("[ViewModel] ✅ App sync fully completed.")
                    self.lastSyncDate = Date()  // Record sync time to suppress redundant re-fetch

                    if self.needsSyncAgain, let nextChildId = self.pendingChildId {
                        self.needsSyncAgain = false
                        self.pendingChildId = nil
                        self.executeFinalSync(childId: nextChildId)
                    } else {
                        self.isSyncInProgress = false
                        let completions = self.syncCompletions
                        self.syncCompletions.removeAll()
                        completions.forEach { $0(true) }
                    }
                } else {
                    self.isSyncInProgress = false
                    print("[ViewModel] ❌ Sync failed")
                    DispatchQueue.main.async {
                        appDelegate.window?.rootViewController?.popupAlert(
                            title: "Sync Failed",
                            message: "Failed to save some app settings. Please try again.",
                            actionTitles: ["OK"],
                            actions: [{ _ in }, nil]
                        )
                    }
                    let completions = self.syncCompletions
                    self.syncCompletions.removeAll()
                    completions.forEach { $0(false) }
                }
            }
        }
    }

    // MARK: - Clear all data on logout
    /// Resets all in-memory selection state so the picker shows no apps after the next login.
    /// Also disconnects the modelContext so `loadData()` won't reload stale SwiftData rows
    /// before a fresh context is set by the next user session.
    func clearData() {
        selection = FamilyActivitySelection(includeEntireCategory: true)
        appStatuses.removeAll()
        hasChanges = false
        isBlockAllMode = false
        UserDefaults.standard.set(false, forKey: "BlockAll_SelectAll")
        deletedTokens.removeAll()
        deletedTokenNames.removeAll()
        recentlyDeletedTokens.removeAll()
        syncCompletions.removeAll()
        needsSyncAgain = false
        pendingChildId = nil
        isSyncInProgress = false
        shouldRemoveRequestedApps = false
        modelContext = nil
        lastSyncDate = nil
        print("[ParentControlViewModel] Cleared all data for logout.")
    }
}

enum AppNameResolution {
    static func isResolved(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !isUnresolved(trimmed)
    }

    static func isUnresolved(_ name: String?) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else { return true }
        // Only flag names that are clearly placeholder / sentinel values.
        // NOTE: "Sync Failed", "Name", "com.*", "org.*" have been removed from
        // this list — they are real app names / bundle IDs returned by
        // FamilyControlsAgent and must NOT block request submission.
        return name == "Unknown"
            || name == "Unknown App"
            || name == "Removed App"
            || name == "Pending Resolution..."
            || name == "..."  // CellForAppsList's own loading placeholder
            || name == "Label is already or no longer part of the view hierarchy"
    }

    static func cleanBundleId(_ bundleId: String) -> String {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(".") else { return trimmed }

        let knownMappings: [String: String] = [
            "com.apple.mobilesafari": "Safari",
            "com.apple.Preferences": "Settings",
            "com.apple.AppStore": "App Store",
            "com.apple.Maps": "Maps",
            "com.apple.Music": "Music",
            "com.apple.Camera": "Camera",
            "com.apple.MobileAddressBook": "Contacts",
            "com.apple.mobilecal": "Calendar",
            "com.apple.mobilephone": "Phone",
            "com.apple.MobileSMS": "Messages",
            "com.apple.mail": "Mail",
            "com.apple.Photos": "Photos",
            "com.apple.calculator": "Calculator",
            "com.apple.facetime": "FaceTime",
            "com.apple.weather": "Weather",
            "com.apple.news": "News",
            "com.apple.iBooks": "Books",
            "com.apple.Home": "Home",
            "com.apple.Fitness": "Fitness",
            "com.apple.Translate": "Translate",
            "com.apple.shortcuts": "Shortcuts",
            "com.apple.Health": "Health",
            "com.apple.Keynote": "Keynote",
            "com.apple.Numbers": "Numbers",
            "com.apple.Pages": "Pages",
            "com.apple.GarageBand": "GarageBand",
            "com.apple.iMovie": "iMovie",
            "com.google.chrome.ios": "Chrome",
            "com.google.Chrome": "Chrome",
            "com.google.Maps": "Google Maps",
            "com.google.Gmail": "Gmail",
            "com.google.youtube": "YouTube",
            "com.zhiliaoapp.musically": "TikTok",
            "com.toyopagroup.picolo": "Picolo",
            "com.facebook.Facebook": "Facebook",
            "com.instagram.android": "Instagram",
            "com.burbn.instagram": "Instagram",
            "com.facebook.Messenger": "Messenger",
            "com.linkedin.LinkedIn": "LinkedIn",
            "com.pinterest.Pinterest": "Pinterest",
            "com.reddit.Reddit": "Reddit",
            "com.snapchat.android": "Snapchat",
            "com.spotify.client": "Spotify",
        ]

        if let mapped = knownMappings[trimmed] {
            return mapped
        }

        let lowercaseBundle = trimmed.lowercased()
        for (key, val) in knownMappings {
            if key.lowercased() == lowercaseBundle {
                return val
            }
        }

        let components = trimmed.components(separatedBy: ".")
        if let lastComponent = components.last, !lastComponent.isEmpty {
            let spaceSeparated =
                lastComponent
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            let words = spaceSeparated.components(separatedBy: " ")
            let capitalizedWords = words.map { word -> String in
                guard let firstChar = word.first else { return word }
                return firstChar.uppercased() + word.dropFirst().lowercased()
            }
            return capitalizedWords.joined(separator: " ")
        }

        return trimmed
    }
}

// MARK: - Persistent name cache (survives app restarts)
/// Stores resolved ApplicationToken → app name mappings in UserDefaults so that
/// FamilyControlsAgent does not need to be queried again on subsequent launches.
/// Keys are the first 24 characters of the base64-encoded token string, prefixed
/// by "anc_" to avoid collisions with other UserDefaults keys.
enum AppNameResolutionCache {
    private static let prefix = "anc2_"
    private static let defaults = UserDefaults.standard

    /// Returns a previously resolved name for the given token string, or nil if not cached.
    static func cachedName(forTokenStr tokenStr: String) -> String? {
        let key = cacheKey(for: tokenStr)
        guard let name = defaults.string(forKey: key),
            AppNameResolution.isResolved(name)
        else { return nil }
        return name
    }

    /// Persists a resolved name for the given token string.
    /// Only stores if the name passes `AppNameResolution.isResolved()`.
    static func store(name: String, forTokenStr tokenStr: String) {
        guard AppNameResolution.isResolved(name) else { return }
        defaults.set(name, forKey: cacheKey(for: tokenStr))
    }

    /// Clears all cached names — useful on logout or full reset.
    static func clearAll() {
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        allKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    private static func cacheKey(for tokenStr: String) -> String {
        return prefix + tokenStr
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
