//
//  NoLocationTrackingRequestStore.swift
//  GaurdianDrive
//
//  Backing store for the "No Location Tracking" (NLT) flow:
//    Child  Home → "Request No Location Tracking" → popup → POST .../request
//                → pending card with an ✕ that calls POST .../cancel
//    Parent Home → request card with Approve / Reject → POST .../approve | /reject
//
//  Backend contract (see WebURL.*NoLocationTracking):
//      POST child/{childId}/no-location-tracking-mode/request
//      POST child/{childId}/no-location-tracking-mode/approve
//      POST child/{childId}/no-location-tracking-mode/reject
//      POST child/{childId}/no-location-tracking-mode/cancel
//  All four take an empty body and carry no requestId — the state is a single
//  value per child, which is why this store is keyed by childId rather than by
//  request, unlike the No-Drive Mode flow.
//
//  READING the state: there is no dedicated GET yet, so `applyServerPayload`
//  scavenges it out of the `/child/{id}/apps/all` response that both Home
//  screens already poll (see ParentHomeViewModel.parseChildData and
//  ChildHomeViewModel.fetchApprovedNoDriveModeRequests). The parser accepts any
//  key that normalises to something containing "nolocationtracking", and any of
//  the shapes the backend is likely to use (string / bool / object / array, or
//  the three-list `…Requested` / `…Approved` / `…Rejected` shape used by
//  none-drive-mode). On the first payload it also logs every key containing
//  "location" so the real key can be confirmed from a device log and this list
//  narrowed down. Until then, the POST responses plus the persisted optimistic
//  state keep both screens correct.
//
//  While a request is APPROVED the child keeps tracking location locally — the
//  speed→shield pipeline and geofence wake-ups are untouched — but nothing is
//  uploaded: see the guards in LocationPermissionManager.sendLocationToServer()
//  and ChildHomeVC.sendLocation().
//

import Foundation

extension Notification.Name {
    /// Posted whenever the No-Location-Tracking status changes, on either side.
    static let noLocationTrackingRequestDidChange = Notification.Name(
        "noLocationTrackingRequestDidChange")
}

final class NoLocationTrackingRequestStore {

    static let shared = NoLocationTrackingRequestStore()
    private init() {}

    private let apiCallViewModel = ApiCallViewModel()

    // MARK: - Status

    enum Status: String {
        case none
        case pending
        case approved
        case rejected

        /// Maps whatever the backend calls it onto our four UI states.
        init(serverValue raw: String) {
            switch raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            case "REQUESTED", "REQUEST", "PENDING", "WAITING":
                self = .pending
            case "APPROVED", "APPROVE", "ACCEPTED", "ACTIVE", "ENABLED", "ON":
                self = .approved
            case "REJECTED", "REJECT", "DECLINED", "DENIED":
                self = .rejected
            default:
                self = .none
            }
        }
    }

    // MARK: - Storage
    //
    // Persisted so the pending/approved card survives an app kill, and so
    // LocationPermissionManager can honour an approved request on a background
    // relaunch that happens before login state is restored.

    private static func udKey(_ childId: String) -> String { "NLT_Status_\(childId)" }

    /// Single mirror of the *current device's* child state, so LocationPermissionManager
    /// can check it without knowing the childId.
    private static let udSuspendKey = "NLT_TrackingSuspendedForThisDevice"

    private var cache: [String: Status] = [:]

    /// The child whose state applies to this device: the logged-in child's own id.
    /// Falls back to the id LocationManager persists, so it still resolves on a
    /// background relaunch before `AppState` is repopulated.
    var currentDeviceChildId: String? {
        if let uid = AppState.sharedInstance.user?.userId, !uid.isEmpty { return uid }
        if let saved = UserDefaults.standard.string(forKey: "LocationChildUserId"), !saved.isEmpty {
            return saved
        }
        return nil
    }

    func status(forChildId childId: String) -> Status {
        guard !childId.isEmpty else { return .none }
        if let cached = cache[childId] { return cached }
        let raw = UserDefaults.standard.string(forKey: Self.udKey(childId)) ?? ""
        let status = Status(rawValue: raw) ?? Status.none
        cache[childId] = status
        return status
    }

    /// Status of the child logged in on THIS device (child-side screens).
    var myStatus: Status {
        guard let childId = currentDeviceChildId else { return .none }
        return status(forChildId: childId)
    }

    /// `true` while this device's child has an APPROVED no-location-tracking request,
    /// i.e. location must not be uploaded (local tracking continues).
    /// Safe to read from any thread/launch state.
    var isTrackingSuspendedOnThisDevice: Bool {
        // Parent devices are never suspended by a child's request.
        guard !UserDefaults.Main.bool(forKey: .isParent) else { return false }
        if let childId = currentDeviceChildId {
            return status(forChildId: childId) == .approved
        }
        // No id yet (very early launch) — fall back to the persisted mirror.
        return UserDefaults.standard.bool(forKey: Self.udSuspendKey)
    }

    private func setStatus(_ status: Status, forChildId childId: String, notify: Bool = true) {
        guard !childId.isEmpty else { return }
        let previous = self.status(forChildId: childId)
        cache[childId] = status
        UserDefaults.standard.set(status.rawValue, forKey: Self.udKey(childId))

        // Keep the device-level mirror in sync when this is our own child.
        if childId == currentDeviceChildId {
            UserDefaults.standard.set(status == .approved, forKey: Self.udSuspendKey)
        }

        guard previous != status else { return }
        print("📍 [NLT] child \(childId): \(previous.rawValue) → \(status.rawValue)")

        guard notify else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .noLocationTrackingRequestDidChange,
                object: nil,
                userInfo: ["childId": childId]
            )
        }
    }

    /// Wipe everything on logout.
    func clearData() {
        // Scan defaults rather than only the in-memory cache, so entries persisted
        // by a previous launch are cleared too.
        let prefix = Self.udKey("")
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        cache.removeAll()
        UserDefaults.standard.set(false, forKey: Self.udSuspendKey)
    }

    // MARK: - Child-side actions

    /// Child taps "Send Request" in the confirmation popup.
    /// POST child/{childId}/no-location-tracking-mode/request
    func sendRequest(completion: @escaping (Bool, String?) -> Void) {
        guard let childId = currentDeviceChildId else {
            completion(false, "Missing child account")
            return
        }
        post(
            url: WebURL.requestNoLocationTracking(childId: childId),
            childId: childId,
            fallbackStatus: .pending,
            failureMessage: "Failed to send request",
            completion: completion
        )
    }

    /// Child cancels their own pending request.
    /// POST child/{childId}/no-location-tracking-mode/cancel
    func cancel(completion: @escaping (Bool, String?) -> Void) {
        guard let childId = currentDeviceChildId else {
            completion(false, "Missing child account")
            return
        }
        post(
            url: WebURL.cancelNoLocationTracking(childId: childId),
            childId: childId,
            fallbackStatus: .none,
            failureMessage: "Failed to cancel request",
            completion: completion
        )
    }

    // MARK: - Parent-side actions

    /// POST child/{childId}/no-location-tracking-mode/approve
    func approve(childId: String, completion: @escaping (Bool, String?) -> Void) {
        post(
            url: WebURL.approveNoLocationTracking(childId: childId),
            childId: childId,
            fallbackStatus: .approved,
            failureMessage: "Failed to approve request",
            completion: completion
        )
    }

    /// POST child/{childId}/no-location-tracking-mode/reject
    func reject(childId: String, completion: @escaping (Bool, String?) -> Void) {
        post(
            url: WebURL.rejectNoLocationTracking(childId: childId),
            childId: childId,
            fallbackStatus: .rejected,
            failureMessage: "Failed to reject request",
            completion: completion
        )
    }

    /// Parent revokes an approved request (or dismisses a resolved card), putting the
    /// child back under normal tracking. Uses the same /cancel endpoint as the child.
    func cancel(childId: String, completion: @escaping (Bool, String?) -> Void) {
        post(
            url: WebURL.cancelNoLocationTracking(childId: childId),
            childId: childId,
            fallbackStatus: .none,
            failureMessage: "Failed to cancel request",
            completion: completion
        )
    }

    // MARK: - Shared POST plumbing

    private func post(
        url: String,
        childId: String,
        fallbackStatus: Status,
        failureMessage: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        apiCallViewModel.postApiCallWithDisctionaryResponse(aUrl: url, param: [:]) {
            [weak self] (isSuccess, responseDict, _) in
            guard let self = self else { return }

            guard isSuccess else {
                let message = responseDict["defaultMessage"] as? String
                    ?? responseDict["message"] as? String
                    ?? failureMessage
                completion(false, message)
                return
            }

            // Prefer a state the server echoed back; otherwise apply the optimistic one.
            if let serverStatus = Self.parseStatus(from: responseDict) {
                self.setStatus(serverStatus, forChildId: childId)
            } else {
                self.setStatus(fallbackStatus, forChildId: childId)
            }
            completion(true, responseDict["message"] as? String)
        }
    }

    // MARK: - Reading state out of existing responses

    /// Feed any API response that might carry the NLT state (today: `/apps/all`).
    /// No-ops when the payload contains nothing recognisable, so the persisted
    /// optimistic state is never clobbered by a response that simply omits it.
    func applyServerPayload(_ responseDict: [String: Any], childId: String) {
        Self.logLocationKeysOnce(responseDict)
        guard let status = Self.parseStatus(from: responseDict) else { return }
        setStatus(status, forChildId: childId)
    }

    /// One-shot diagnostic: prints every top-level key mentioning "location" so the
    /// real NLT key can be read off a device log and this parser tightened up.
    private static var didLogKeys = false
    private static func logLocationKeysOnce(_ dict: [String: Any]) {
        guard !didLogKeys else { return }
        didLogKeys = true
        let keys = dict.keys.filter { $0.lowercased().contains("location") || $0.lowercased().contains("track") }
        print("📍 [NLT] location/track-related keys in /apps/all: \(keys.isEmpty ? ["<none>"] : Array(keys))")
    }

    /// `true` for keys like `noLocationTrackingMode`, `no_location_tracking`, `nltStatus`.
    private static func isNLTKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized.contains("locationtracking") || normalized.hasPrefix("nlt")
    }

    /// Pulls a status out of an arbitrary response body, tolerating the shapes the
    /// backend might use. Returns nil when nothing NLT-related is present.
    static func parseStatus(from dict: [String: Any]) -> Status? {
        var found: [Status] = []

        for (key, value) in dict where isNLTKey(key) {
            let normalizedKey = key.lowercased().filter { $0.isLetter || $0.isNumber }

            // Shape D: split lists, e.g. noLocationTrackingRequested / …Approved / …Rejected.
            // The key names the status; a non-empty value means that state is live.
            let keyStatus: Status? = {
                if normalizedKey.hasSuffix("requested") || normalizedKey.hasSuffix("pending") { return .pending }
                if normalizedKey.hasSuffix("approved") { return .approved }
                if normalizedKey.hasSuffix("rejected") { return .rejected }
                return nil
            }()

            if let keyStatus = keyStatus {
                if isNonEmpty(value) { found.append(keyStatus) }
                continue
            }

            if let status = status(fromValue: value) {
                found.append(status)
            }
        }

        guard !found.isEmpty else { return nil }
        // An actionable request outranks a historical outcome.
        if found.contains(.pending) { return .pending }
        if found.contains(.approved) { return .approved }
        if found.contains(.rejected) { return .rejected }
        // Present but empty/cleared — an explicit "no request", not "unknown".
        return Status.none
    }

    private static func status(fromValue value: Any) -> Status? {
        switch value {
        // Shape A: plain status string — "REQUESTED" / "APPROVED" / …
        case let string as String:
            return string.isEmpty ? Status.none : Status(serverValue: string)

        // Shape B: bool / 0-1 flag — on means the child's location is hidden.
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() || number == 0 || number == 1 {
                return number.boolValue ? .approved : Status.none
            }
            return nil

        // Shape C: object carrying the status.
        case let object as [String: Any]:
            for key in ["status", "currentStatus", "requestStatus", "state"] {
                if let raw = object[key] as? String, !raw.isEmpty {
                    return Status(serverValue: raw)
                }
            }
            for key in ["isApproved", "approved", "enabled", "active"] {
                if let flag = object[key] as? Bool { return flag ? .approved : Status.none }
            }
            return object.isEmpty ? Status.none : nil

        // Shape D: list of requests — newest entry wins.
        case let list as [[String: Any]]:
            guard let latest = newest(in: list) else { return Status.none }
            return status(fromValue: latest)

        case is NSNull:
            return Status.none

        default:
            return nil
        }
    }

    private static func isNonEmpty(_ value: Any) -> Bool {
        switch value {
        case let list as [Any]: return !list.isEmpty
        case let object as [String: Any]: return !object.isEmpty
        case let string as String: return !string.isEmpty
        case let number as NSNumber: return number.boolValue
        default: return false
        }
    }

    /// Picks the most recently created entry, falling back to the last element.
    private static func newest(in list: [[String: Any]]) -> [String: Any]? {
        guard !list.isEmpty else { return nil }
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoShort = ISO8601DateFormatter()

        func date(_ entry: [String: Any]) -> Date? {
            for key in ["updatedAt", "createdAt", "requestedAt", "created_at", "date"] {
                if let raw = entry[key] as? String,
                   let parsed = isoFull.date(from: raw) ?? isoShort.date(from: raw) {
                    return parsed
                }
            }
            return nil
        }

        if list.contains(where: { date($0) != nil }) {
            return list.max { (date($0) ?? .distantPast) < (date($1) ?? .distantPast) }
        }
        return list.last
    }
}
