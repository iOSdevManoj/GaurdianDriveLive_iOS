//
//  LocationManager.swift
//  GaurdianDrive
//
//  Created by KETAN on 03/02/26.
//

//
//  LocationManager.swift
//  Stride
//
//  Created by KETAN on 03/02/26.
//

import CoreLocation
import Foundation
import UIKit

final class LocationPermissionManager: NSObject {

    // MARK: - Singleton
    static let shared = LocationPermissionManager()
    private let manager = CLLocationManager()
    private(set) var currentSpeed: Double = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Public access to the current CLLocationManager authorization status.
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    private override init() {
        super.init()
        setup()
        observeAppActive()
    }

    // MARK: - Stored Values
    private(set) var currentLocation: CLLocation?

    // MARK: - Background Location Throttle
    /// UserDefaults key for the last time we sent a location to the server.
    private let udLastSentKey = "LocationLastSentTimestamp"
    /// Persisted key for the last reliably measured speed in MPH.
    /// Survives app kills so the first background wakeup fix can use a meaningful speed.
    private let udLastSpeedKey = "LocationLastReliableSpeedMPH"
    /// Manual calculation tracking
    private var lastLocationForSpeed: CLLocation?
    /// Minimum seconds between API calls (5-second throttle, works across kills).
    private let throttleInterval: TimeInterval = 5

    // MARK: - Background URLSession
    /// A persistent background session with a fixed identifier.
    /// The OS can complete pending upload tasks even if the app is suspended mid-request.
    /// NOTE: Must NOT use a completion-handler API (dataTask closure) — delegates only.
    static let backgroundSessionIdentifier = "com.guardiandrive.locationupload"
    lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: LocationPermissionManager.backgroundSessionIdentifier)
        config.isDiscretionary = false  // send ASAP, don't wait for power/Wi-Fi
        config.sessionSendsLaunchEvents = true  // relaunch app when upload completes
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Setup
    private func setup() {
        manager.delegate = self
        // kCLLocationAccuracyBestForNavigation: automotive-grade accuracy with
        // valid speedAccuracy on every fix — essential for reliable speed tracking
        // in background and killed-mode scenarios.
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone  // must fire when stopped so speed→0 and shields clear
        manager.activityType = .automotiveNavigation

        // We defer allowsBackgroundLocationUpdates until checkPermission() validates authorization.
        // If set while .notDetermined on a fresh install, iOS silently disables background updates
        // until the app is killed and reopened.

        // Start immediately if already authorised — covers cold-launch from
        // a killed state where @MainActor delegate callbacks may be deferred.
        if (manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse)
            && needsContinuousTracking
        {
            configureBackgroundCapabilities()
            manager.startUpdatingLocation()
            #if !targetEnvironment(simulator)
                manager.startMonitoringSignificantLocationChanges()
            #endif
        }
    }

    private func configureBackgroundCapabilities() {
//        #if !targetEnvironment(simulator)
            // MUST be set before starting updates to survive background transitions
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            
            // On Child devices, blue bar indicator helps prevent iOS from killing
            // the app due to resource constraints/idle time.
            let isChild = !UserDefaults.Main.bool(forKey: .isParent)
            manager.showsBackgroundLocationIndicator = isChild
//        #endif
    }
}

// MARK: - PUBLIC METHODS ⭐
extension LocationPermissionManager {

    /// Turn ON location updates
    @MainActor func startUpdating() {
        checkPermission()
    }

    /// Turn OFF location updates
    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    /// Stops everything that can keep GPS on or wake the app in the background:
    /// standard updates, significant-change monitoring and the child's geofence.
    /// Used at logout, and on a parent phone that has no self-drive apps.
    func stopAllTracking() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    /// UserDefaults key written by `AppBlockerManager.updateParentLocationNeed()`:
    /// whether parent self-drive has at least one restricted app.
    static let parentSelfDriveNeedsLocationKey = "ParentSelfDriveNeedsLocation"

    /// Whether this device should run continuous location right now.
    /// - Logged out: no.
    /// - Child: always (drive detection, app blocking, live location for the parent).
    /// - Parent: only while parent self-drive has restricted apps — speed is used only to
    ///   lock those apps. Unknown (never computed yet) counts as yes, the old behaviour.
    var needsContinuousTracking: Bool {
        guard !UserDefaults.Main.string(forKey: .userToken).isEmpty else { return false }
        guard UserDefaults.Main.bool(forKey: .isParent) else { return true }
        return UserDefaults.standard.object(forKey: Self.parentSelfDriveNeedsLocationKey) as? Bool ?? true
    }

    /// Get Latitude anytime
    func getLatitude() -> Double? {
        return currentLocation?.coordinate.latitude
    }

    /// Get Longitude anytime
    func getLongitude() -> Double? {
        return currentLocation?.coordinate.longitude
    }

    /// Optional: get both together
    func getCoordinates() -> (lat: Double, lng: Double)? {
        guard let loc = currentLocation else { return nil }
        return (loc.coordinate.latitude, loc.coordinate.longitude)
    }

    func getSpeedMetersPerSecond() -> Double {
        return currentSpeed
    }

    func getSpeedKMH() -> Double {
        return currentSpeed * 3.6
    }

    func getSpeedMPH() -> Double {
        let mph = currentSpeed * 2.23694
        return (mph * 100).rounded() / 100
    }
}

// MARK: - Permission Logic
extension LocationPermissionManager {

    @MainActor fileprivate func checkPermission() {
        let isChild = !UserDefaults.Main.bool(forKey: .isParent)

        switch manager.authorizationStatus {

        case .notDetermined:
            // Apple requires requesting WhenInUse first on iOS 13+.
            // Requesting Always directly will result in a silent downgrade to "Provisional Always"
            // or the prompt won't show the correct options.
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse:
            // Upgrade to Always so background tracking works for both Child and Parent
            manager.requestAlwaysAuthorization()
            showSettingsAlert(isChild: isChild)
            if needsContinuousTracking {
                configureBackgroundCapabilities()
                manager.startUpdatingLocation()
//            #if !targetEnvironment(simulator)
                manager.startMonitoringSignificantLocationChanges()
//            #endif
            } else {
                stopAllTracking()
            }

        case .authorizedAlways:
            if needsContinuousTracking {
                configureBackgroundCapabilities()
                manager.startUpdatingLocation()
//            #if !targetEnvironment(simulator)
                manager.startMonitoringSignificantLocationChanges()
//            #endif
            } else {
                stopAllTracking()
            }

        case .denied, .restricted:
            showSettingsAlert(isChild: isChild)

        @unknown default:
            break
        }
        
        // If authorization changes, immediately trigger a sync to the backend
        // so the parent is notified if location was tampered with (turned off).
        if isChild {
            ChildPermissionSyncManager.shared.syncIfNeeded()
        }
    }

    @MainActor private func showSettingsAlert(isChild: Bool) {
        // PermissionsManager is triggered by ChildHomeVC / HomeVC on viewWillAppear
        // and didBecomeActive — no need to call it again here.
    }
}

// MARK: - App Active
extension LocationPermissionManager {

    fileprivate func observeAppActive() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @MainActor @objc fileprivate func appActive() {
        checkPermission()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationPermissionManager: @preconcurrency CLLocationManagerDelegate {

    @MainActor func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkPermission()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {

        // When waking up in the background from a killed state, iOS gives very little execution time.
        // We begin a background task to guarantee that @MainActor tasks in AppBlockerManager finish.
        if UIApplication.shared.applicationState != .active {
            if backgroundTask == .invalid {
                backgroundTask = UIApplication.shared.beginBackgroundTask(
                    withName: "LocationUpdateProcess"
                ) { [weak self] in
                    if let task = self?.backgroundTask, task != .invalid {
                        UIApplication.shared.endBackgroundTask(task)
                        self?.backgroundTask = .invalid
                    }
                }
            }
        }

        guard let location = locations.last else { return }
        currentLocation = location

        // 1. Get speed from system
        var speedMS = location.speed
        
        // 2. Fallback: Manual calculation (Crucial for Xcode Simulator/GPX)
        if speedMS <= 0 {
            if let last = lastLocationForSpeed {
                let time = location.timestamp.timeIntervalSince(last.timestamp)
                let distance = location.distance(from: last)
                
                if time > 0.5 { 
                    if distance > 0.1 {
                        speedMS = distance / time
                    } else if time < 3.0 {
                        // If we haven't moved, but it's been less than 3 seconds,
                        // keep the previous speed to avoid "0.0 mph" flicker.
                        speedMS = currentSpeed
                    } else {
                        speedMS = 0
                    }
                } else {
                    // Too fast update, keep previous
                    speedMS = currentSpeed
                }
            }
        }
        lastLocationForSpeed = location

        // 3. Filter noise (Min 1.5 m/s ≈ 3.3 mph)
        let minReliableSpeed: Double = 1.5 
        
        if speedMS >= minReliableSpeed {
            currentSpeed = speedMS
            let mph = (speedMS * 2.23694 * 100).rounded() / 100
            UserDefaults.standard.set(mph, forKey: udLastSpeedKey)
        } else {
            currentSpeed = 0
            UserDefaults.standard.set(0.0, forKey: udLastSpeedKey)
        }

        //        print("Lat:", location.coordinate.latitude)
        //        print("Lng:", location.coordinate.longitude)
        //        print("Speed m/s:", currentSpeed)

        // Broadcast speed updates so other VCs can listen
        NotificationCenter.default.post(
            name: .speedDidUpdate,
            object: nil,
            userInfo: ["speedMPH": getSpeedMPH()]
        )

        // 1. App is in the background (Killed mode or backgrounded)
        // 2. OR Socket feature flag is disabled, forcing API Everywhere
        let isChild = !UserDefaults.Main.bool(forKey: .isParent)
        let isForeground = UIApplication.shared.applicationState == .active
        let shouldUseRestAPI = !isForeground || !FeatureFlag.isSocketFeatureEnabled
        
        if isChild && shouldUseRestAPI {
            let speedMPH = getSpeedMPH()
            // Same trigger AppBlockerManager uses for shields, so the driveMode sent to
            // the server always matches what the child's phone is doing.
            let effectiveLimit = DriveMode.triggerMph
            let isDriving = speedMPH > effectiveLimit //effectiveLimit
            let driveMode: String
            if isDriving {
                driveMode =
                    ChildHomeViewModel.shared.hasActiveNoDriveApproval
                    ? "No-Drive mode active"
                    : "Drive mode active"
            } else {
                driveMode = "Normal"
            }
            sendLocationToServer(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                speedMPH: speedMPH,
                driveMode: driveMode
            )
        }

        // ⭐ Geofence Chaining for "Killed Mode" Survival
        // Tracking apps use this to wake back up after a force-quit.
        if isChild {
            setupNextRegion(center: location.coordinate)
        }

        // Give the async MainActor Task 1.5 seconds to apply shields natively, then manually release it so iOS is happy.
        if self.backgroundTask != .invalid {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if let task = self?.backgroundTask, task != .invalid {
                    UIApplication.shared.endBackgroundTask(task)
                    self?.backgroundTask = .invalid
                }
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print(error.localizedDescription)
    }

    // MARK: - Region Monitoring (Killed Mode Resurrection)

    /// Creates a 200m geofence around the current location. If the app is killed,
    /// leaving this region wakes the app up entirely in the background.
    private func setupNextRegion(center: CLLocationCoordinate2D) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        // Clear old regions to prevent limit exhaustion
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }

        // 30 meters is the minimum reliable distance Apple recommends for region triggers without high battery drain
        let region = CLCircularRegion(
            center: center, radius: 30, identifier: "KilledModeResurrection")
        region.notifyOnExit = true
        region.notifyOnEntry = false

        manager.startMonitoring(for: region)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // App woke up from Killed Mode!
        print("📍 [Location] Woke up from killed mode via region exit: \(region.identifier)")

        // CRITICAL GAP: When iOS wakes the app for didExitRegion while locked, we only have a few
        // seconds of execution time. If startUpdatingLocation() doesn't get a GPS fix fast enough,
        // the OS suspends the app again before didUpdateLocations can fire and start continuous polling!
        // We MUST bridge this gap with a background task.
        var gapTask: UIBackgroundTaskIdentifier = .invalid
        gapTask = UIApplication.shared.beginBackgroundTask(withName: "KilledResurrectionGap") {
            if gapTask != .invalid {
                UIApplication.shared.endBackgroundTask(gapTask)
                gapTask = .invalid
            }
        }

        // Re-apply background settings — this delegate fires on a killed-mode relaunch
        // where setup() may have run before checkPermission() could set these flags.
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        #endif

        // Request best-for-navigation accuracy temporarily so the first fix
        // after wake has a valid speedAccuracy (not -1). Without this, the
        // first update would use the persisted last-known speed even if speed
        // has changed since the app was killed.
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation

        // Immediately trigger a fresh GPS update to get actual speed and location.
        // didUpdateLocations will fire, send the API call, and set the next 30m region.
        manager.startUpdatingLocation()

        // Give GPS up to 10 seconds to spin up and hit didUpdateLocations, then drop the task.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if gapTask != .invalid {
                UIApplication.shared.endBackgroundTask(gapTask)
                gapTask = .invalid
            }
        }
    }
}

// MARK: - Background Location API
extension LocationPermissionManager {

    /// Sends the child's current location + speed to the server.
    /// Uses a UserDefaults-persisted 5-second throttle so it works even after the app is killed and
    /// relaunched by iOS for background location delivery.
    ///
    /// Uses a background URLSession + uploadTask so the OS can complete the request
    /// even if the app is suspended between the location relaunch and network completion.
    fileprivate func sendLocationToServer(
        latitude: Double,
        longitude: Double,
        speedMPH: Double,
        driveMode: String
    ) {
        // Approved No-Location-Tracking: the child keeps tracking locally — speed
        // updates and the speed→shield pipeline are unaffected — but nothing is
        // uploaded, so the parent sees no live location.
        guard !NoLocationTrackingRequestStore.shared.isTrackingSuspendedOnThisDevice else {
            print("📍 [Location] No-Location-Tracking approved — skipping location upload")
            return
        }

        let now = Date()
        let lastSent = UserDefaults.standard.object(forKey: udLastSentKey) as? Date ?? .distantPast

        guard now.timeIntervalSince(lastSent) >= throttleInterval else {
            return  // 5-second throttle — skip this update
        }

        // Read child ID — prefer in-memory AppState, fall back to persisted UserDefaults value.
        let childId: String
        if let uid = AppState.sharedInstance.user?.userId, !uid.isEmpty {
            childId = uid
            UserDefaults.standard.set(uid, forKey: "LocationChildUserId")  // keep fresh copy
        } else if let saved = UserDefaults.standard.string(forKey: "LocationChildUserId"),
            !saved.isEmpty
        {
            childId = saved
        } else {
            print("⚠️ [Location] No child userId found — skipping location API call")
            return
        }

        // Read auth token the same way APIManager does.
        let token = UserDefaults.Main.string(forKey: .userToken)

        guard !token.isEmpty else {
            print("⚠️ [Location] No auth token found — skipping location API call")
            return
        }

        // Mark as sent BEFORE the network call so concurrent updates are throttled.
        UserDefaults.standard.set(now, forKey: udLastSentKey)

        let urlString = WebURL.updateCurrentLocation(childId: childId)
        guard let url = URL(string: urlString) else { return }

        let payload: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "speed": SpeedUnit.current.apiValue(fromMph: speedMPH),
            "driveMode": driveMode,
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        // Background sessions require uploadTask(with:fromFile:) — uploading from NSData
        // in memory is NOT supported. Write the JSON payload to a temp file.
        // CRITICAL: We use .noFileProtection so nsurlsessiond can read this file while the phone is locked.
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        do {
            try body.write(to: tempFile, options: .noFileProtection)
        } catch {
            print("❌ [Location] Failed to write temp upload file: \(error)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        
        // We use the normal URLSession even in the background because didUpdateLocations 
        // creates a UIBackgroundTask. This prevents iOS from intentionally delaying 
        // background uploads by 2+ minutes to save battery.
        let task = URLSession.shared.uploadTask(with: request, fromFile: tempFile) { data, response, error in
            if let error = error {
                print("❌ [Location] Upload failed: \(error.localizedDescription)")
            } else if let httpResp = response as? HTTPURLResponse {
                print("📍 [Location] Upload response HTTP \(httpResp.statusCode)")
            }
            
            // Clean up the temp file
            try? FileManager.default.removeItem(at: tempFile)
        }
        task.resume()
        print("📍 [Location] Queued upload lat=\(latitude) lng=\(longitude) speed=\(speedMPH) mph")
    }
}

// MARK: - URLSession Delegate (background upload responses)
extension LocationPermissionManager: URLSessionDataDelegate, URLSessionTaskDelegate {

    /// Called when the server sends response data back (HTTP body).
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let body = String(data: data, encoding: .utf8) ?? ""
        if let httpResp = dataTask.response as? HTTPURLResponse {
            print("📍 [Location] Upload response HTTP \(httpResp.statusCode): \(body)")
        }
    }

    /// Called when the upload task finishes (success or failure).
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            print("❌ [Location] Upload failed: \(error.localizedDescription)")
        } else if let httpResp = task.response as? HTTPURLResponse {
            print("✅ [Location] Upload completed — HTTP \(httpResp.statusCode)")
        }
    }

    /// Called when ALL pending background tasks finish.
    /// The stored completion handler (saved by AppDelegate) must be called to tell the
    /// OS the app has finished processing so it can take a new snapshot.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let completion = AppDelegate.backgroundSessionCompletionHandler {
                AppDelegate.backgroundSessionCompletionHandler = nil
                completion()
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    /// Posted every time the GPS speed updates.
    /// userInfo["speedMPH"] contains the current speed as Double (MPH).
    static let speedDidUpdate = Notification.Name("SpeedDidUpdate")

    /// Posted when ParentHomeViewModel data is refreshed from a push notification.
    /// userInfo["childId"] contains the refreshed child's ID as String.
    static let parentHomeDataDidUpdate = Notification.Name("ParentHomeDataDidUpdate")
    
    /// Posted when the GuardianSocketManager receives a new location update message.
    /// userInfo["message"] contains the JSON string payload.
    static let socketDidReceiveLocation = Notification.Name("SocketDidReceiveLocation")

    /// Posted when ChildHomeViewModel data is refreshed from a push notification.
    static let childHomeDataDidUpdate = Notification.Name("ChildHomeDataDidUpdate")

    static let getSubscriptionStatus = Notification.Name("SubscriptionStatus")

}
