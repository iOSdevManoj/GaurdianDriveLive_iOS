//
//  MapViewVC.swift
//  GaurdianDrive
//
//  Created by KETAN on 26/12/25.
//

import CoreLocation
import GoogleMaps
import GooglePlaces
import UIKit

class MapViewVC: UIViewController {

    //Outlets...
    @IBOutlet weak var mapView: GMSMapView!
    @IBOutlet weak var lblLocation: UILabel!
    @IBOutlet weak var lblChildName: UILabel!
    @IBOutlet weak var btnGetAddress: UIButton!
    @IBOutlet weak var viewForSearch: UIControl!
    @IBOutlet weak var cons_btnAddress_hight: NSLayoutConstraint!

//    //Variables..
    let geocoder = CLGeocoder()
    private var centerPin: UIImageView?
    private var liveMarker = GMSMarker()
    var childData = UserModel()
    var locationForChild = CLLocationCoordinate2D()
    var isFromAddress = false
    let locationManager = CLLocationManager()
    private var pollingTimer: Timer?
    let apiCallViewModel = ApiCallViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        //Hide tabbar....
        self.tabBarController?.tabBar.isHidden = true
        if rootTab.cons_bottomBar_height != nil {
            rootTab.cons_bottomBar_height.constant = 0
            rootTab.viewBottomTabMain.isHidden = true
        }

        self.initialisation()
        
        NotificationCenter.default.addObserver(self, selector: #selector(socketLocationUpdated(_:)), name: .socketDidReceiveLocation, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.startApiPollingIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.stopApiPolling()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func socketLocationUpdated(_ notification: Notification) {
        guard !self.isFromAddress else { return }
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? String,
              let data = message.data(using: .utf8) else { return }
        
        do {
            let location = try JSONDecoder().decode(ChildLocation.self, from: data)
            guard self.childData.userId == location.childId else { return }
            
            DispatchQueue.main.async {
                self.locationForChild = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                // Keep the current zoom level so we don't snap back to zoom 15 if the user zoomed in/out
                self.showLocationWithPin(lat: location.latitude, lng: location.longitude, zoom: self.mapView.camera.zoom)
            }
        } catch {
            print("MapViewVC: Error decoding ChildLocation", error)
        }
    }

    private func startApiPollingIfNeeded() {
        guard !FeatureFlag.isSocketFeatureEnabled, !self.isFromAddress, !self.childData.userId.isEmpty else { return }
        stopApiPolling()
        
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        print("⏱️ [MapViewVC] Sockets disabled — starting 5-second REST API polling.")
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.apiCallForGetChildLastLocation()
        }
    }
    
    private func stopApiPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    @objc private func appWillEnterForeground() {
        guard !FeatureFlag.isSocketFeatureEnabled, !self.isFromAddress, !self.childData.userId.isEmpty else { return }
        if pollingTimer == nil {
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.apiCallForGetChildLastLocation()
            }
        }
    }

    private func apiCallForGetChildLastLocation() {
        let childId = self.childData.userId
        let strUrl = WebURL.getLastLocation(childId: childId)

        apiCallViewModel.getApiCallWithDisctionaryResponse(aUrl: strUrl, aParams: [String: Any]()) { [weak self] (isSuccess, responseDict) in
            guard let self = self else { return }
            if isSuccess {
                let lat = Double("\(responseDict["latitude"] ?? 0.0)") ?? 0.0
                let lng = Double("\(responseDict["longitude"] ?? 0.0)") ?? 0.0
                
                if lat != 0 && lng != 0 {
                    DispatchQueue.main.async {
                        self.locationForChild = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                        self.showLocationWithPin(lat: lat, lng: lng, zoom: self.mapView.camera.zoom)
                    }
                }
            }
        }
    }
}

extension MapViewVC {
    //MARK: - Initialisation..
    func initialisation() {
        self.mapView.delegate = self

        if !self.isFromAddress {
            mapView.isMyLocationEnabled = false
            mapView.settings.myLocationButton = false
            self.showLocationWithPin(
                lat: self.locationForChild.latitude, lng: self.locationForChild.longitude)
            self.lblChildName.text = childData.name
            self.viewForSearch.isHidden = true
            self.cons_btnAddress_hight.constant = 0
            // Intentionally DO NOT turn on location tracking for parent
        } else {
            mapView.isMyLocationEnabled = true
            mapView.settings.myLocationButton = true
            locationManager.delegate = self
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
            self.viewForSearch.isHidden = false
            self.lblChildName.isHidden = true
            self.cons_btnAddress_hight.constant = 45
            self.setupCenterPin()
        }
    }

    func showLocationWithPin(lat: Double, lng: Double, zoom: Float = 15) {

        let position = CLLocationCoordinate2D(latitude: lat, longitude: lng)

        // resize your custom pin image
        let img = UIImage(named: "ic_map_pin")?
            .aspectFitCanvas(size: CGSize(width: 32, height: 42))

        liveMarker.icon = img
        liveMarker.groundAnchor = CGPoint(x: 0.5, y: 1.0)
        liveMarker.position = position
        liveMarker.map = mapView

        // zoom camera
        let camera = GMSCameraPosition.camera(withTarget: position, zoom: zoom)
        mapView.animate(to: camera)

        self.getAddress(from: CLLocation(latitude: lat, longitude: lng))
    }

    func setupCenterPin() {

        let pin = UIImageView()
        pin.image = UIImage(named: "ic_map_pin")
        pin.translatesAutoresizingMaskIntoConstraints = false
        pin.contentMode = .scaleAspectFit

        view.addSubview(pin)

        NSLayoutConstraint.activate([
            pin.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            pin.centerYAnchor.constraint(equalTo: mapView.centerYAnchor),
            pin.widthAnchor.constraint(equalToConstant: 32),
            pin.heightAnchor.constraint(equalToConstant: 42),
        ])

        centerPin = pin
    }
}

//MARK: - Setup Mapview all functions..
extension MapViewVC {
    //MARK: - Get Address
    private func getAddress(from location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let place = placemarks?.first else { return }

            let address = [
                place.name,
                place.locality,
                place.administrativeArea,
                place.country,
            ].compactMap { $0 }.joined(separator: ", ")

            print("📍 Address:", address)
            self.lblLocation.text = address
        }
    }
}

//MARK: - Click Events.....
extension MapViewVC {
    @IBAction func tapToBack(_ sender: UIControl) {
        self.navigationController?.popViewController(animated: true)
    }
    @IBAction func tapToSearch(_ sender: UIControl) {
        if self.isFromAddress {
            let autocomplete = GMSAutocompleteViewController()
            autocomplete.delegate = self
            present(autocomplete, animated: true)
        }
    }
    @IBAction func tapToGetAddress(_ sender: UIButton) {
        if self.isFromAddress {
            if let vcs = navigationController?.viewControllers {

                for vc in vcs {

                    if let addressVC = vc as? AddNewAddressVC {
                        addressVC.setupMapAddressFromLocation(
                            locationCordinate: self.locationForChild,
                            strAddress: self.lblLocation.text!)
                        navigationController?.popToViewController(addressVC, animated: true)
                        break
                    }
                }
            }
        }
    }
}
extension MapViewVC: CLLocationManagerDelegate {

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {

        guard let location = locations.last else { return }

        let coordinate = location.coordinate

        let camera = GMSCameraPosition.camera(
            withLatitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zoom: 16
        )

        mapView.animate(to: camera)

        locationForChild = coordinate
        getAddress(from: location)

        locationManager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {

        switch manager.authorizationStatus {

        case .authorizedWhenInUse, .authorizedAlways:
            if self.isFromAddress {
                locationManager.startUpdatingLocation()
                mapView.isMyLocationEnabled = true
            }

        case .denied, .restricted:
            if self.isFromAddress {
                showDefaultLocation()
                self.showLocationPermissionAlert()
            }

        case .notDetermined:

            locationManager.requestWhenInUseAuthorization()

        @unknown default:
            break
        }
    }

    func showDefaultLocation() {

        let defaultLocation = CLLocationCoordinate2D(
            latitude: 39.8283,
            longitude: -98.5795
        )

        let camera = GMSCameraPosition.camera(
            withLatitude: defaultLocation.latitude,
            longitude: defaultLocation.longitude,
            zoom: 8
        )

        mapView.animate(to: camera)

        locationForChild = defaultLocation

        getAddress(
            from: CLLocation(
                latitude: defaultLocation.latitude,
                longitude: defaultLocation.longitude
            ))
    }

    func showLocationPermissionAlert() {

        let alert = UIAlertController(
            title: "Location Permission",
            message: "Please enable location to get current position.",
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(title: "Settings", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }
}

//MARK: - Places Api Delegates...
extension MapViewVC: GMSAutocompleteViewControllerDelegate {

    func viewController(
        _ viewController: GMSAutocompleteViewController,
        didAutocompleteWith place: GMSPlace
    ) {

        dismiss(animated: true)

        let coordinate = place.coordinate

        let camera = GMSCameraPosition.camera(
            withLatitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zoom: 16
        )

        mapView.animate(to: camera)

        lblLocation.text = place.formattedAddress

        locationForChild = coordinate
    }

    func viewController(
        _ viewController: GMSAutocompleteViewController,
        didFailAutocompleteWithError error: Error
    ) {

        print(error.localizedDescription)
    }

    func wasCancelled(_ viewController: GMSAutocompleteViewController) {

        dismiss(animated: true)
    }
}

//MARK: - Mapview Delegates...
extension MapViewVC: GMSMapViewDelegate {
    func moveMapToLocation(lat: Double, lng: Double, zoom: Float = 16) {
        let camera = GMSCameraPosition.camera(
            withLatitude: lat,
            longitude: lng,
            zoom: zoom
        )
        mapView.animate(to: camera)
    }

    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {

        if self.isFromAddress {

            let center = mapView.camera.target

            locationForChild = center

            getAddress(
                from: CLLocation(
                    latitude: center.latitude,
                    longitude: center.longitude
                ))
        }
    }
}

extension UIImage {
    func aspectFitCanvas(size: CGSize) -> UIImage {

        let widthRatio = size.width / self.size.width
        let heightRatio = size.height / self.size.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(
            width: self.size.width * ratio,
            height: self.size.height * ratio
        )

        let origin = CGPoint(
            x: (size.width - newSize.width) / 2,
            y: (size.height - newSize.height) / 2
        )

        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        self.draw(in: CGRect(origin: origin, size: newSize))
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return img ?? self
    }
}
