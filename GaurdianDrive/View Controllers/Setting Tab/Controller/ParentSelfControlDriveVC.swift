//
//  ParentSelfConrollDriveVC.swift
//  GaurdianDrive
//
//  Created by KETAN on 24/03/26.
//

import UIKit
import SwiftData
import SwiftUI
import FamilyControls
import ManagedSettings
import Combine

class ParentSelfControlDriveVC: UIViewController {

    //Outlets.
    @IBOutlet var lblCurrenSpeed: UILabel!
    @IBOutlet var collViewApprovedAppsList: UICollectionView!
    @IBOutlet var lblDriveModeOn: UILabel!
    @IBOutlet var lblDriveModeHint: UILabel?

    // Variables
    /// The parent's OWN restricted apps. Tokens were picked on this device, so the system
    /// can render their real names — unlike a child's tokens shown on the parent's phone.
    var blockedApps: [ApplicationToken] = []
    private var appStatusesCancellable: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.initilaisation()
        // Init SwiftData once so AppBlockerManager + ParentControlViewModel
        // share the same ModelContainer throughout this session.
        setupSwiftDataAndLoadApps()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.setHidesBackButton(true, animated: true)
        self.tabBarController?.tabBar.isHidden = true
        if rootTab.cons_bottomBar_height != nil {
            rootTab.cons_bottomBar_height.constant = 0
            rootTab.viewBottomTabMain.isHidden = true
        }
        NotificationCenter.default.addObserver(self, selector: #selector(speedUpdated(_:)), name: .speedDidUpdate, object: nil)
        let currentSpeed = LocationPermissionManager.shared.getSpeedMPH()
        updateSpeedUI(speedMPH: currentSpeed)
        let limitText = SpeedUnit.current.format(mph: AppBlockerManager.shared.parentsSpeedLimitMph)
        self.lblDriveModeHint?.text = "Restricted apps will be locked while you drive. Drive Mode starts automatically when your speed goes above \(limitText)."
        // Reload the list every time we appear — picks up changes made in ParentControlView.
        loadBlockedApps()
        // Returning from Select Applications: the saved list may have changed, so make the
        // driving shield match it right away (SwiftData was already written before the pop).
        AppBlockerManager.shared.refreshParentShieldsForNewSelection()
        // fetchFromServer merges asynchronously — refresh the list when it lands.
        appStatusesCancellable = ParentControlViewModel.shared.$appStatuses
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadBlockedApps() }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: .speedDidUpdate, object: nil)
        appStatusesCancellable = nil
    }

    @objc private func speedUpdated(_ notification: Notification) {
        let currentSpeed = LocationPermissionManager.shared.getSpeedMPH()
        updateSpeedUI(speedMPH: currentSpeed)
    }

    private func updateSpeedUI(speedMPH: Double) {
        DispatchQueue.main.async {
            self.lblCurrenSpeed.text = SpeedUnit.current.format(mph: speedMPH).uppercased()
            self.lblDriveModeOn.isHidden = speedMPH <= AppBlockerManager.shared.parentsSpeedLimitMph
        }
    }

    private func setupSwiftDataAndLoadApps() {
        // Reuse the container already created by AppDelegate.checkLogin().
        // Creating a second ModelContainer for the same store causes crashes.
        if AppBlockerManager.shared.modelContainer == nil {
            do {
                let schema = Schema([BlockingSelection.self])
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                let container = try ModelContainer(for: schema, configurations: [config])
                AppBlockerManager.shared.modelContainer = container
                ParentControlViewModel.shared.setModelContext(container.mainContext)
            } catch {
                print("Failed to initialize SwiftData: \(error)")
            }
        }
    }

    /// The shared view model holds only the parent's OWN list (HomeVC "Manage Apps" uses its
    /// own in-memory instance for the child), and ParentControlView edits it in memory — so
    /// read it as-is rather than re-reading SwiftData, whose saved selection may not
    /// round-trip every token.
    private func loadBlockedApps() {
        Task { @MainActor in
            await ParentControlViewModel.shared.loadDataIfNeeded()
            let ownTokens = ParentControlViewModel.shared.ownAppTokens

            // Same source as ParentControlView's "Selected Apps" list (appStatuses), so both
            // screens show the same apps. Array order keeps tiles stable across reloads.
            self.blockedApps = ParentControlViewModel.shared.appStatuses
                .filter { $0.isBlocked && !ownTokens.contains($0.token) }
                .map(\.token)
            print("[SelfDrive] Showing \(self.blockedApps.count) of \(ParentControlViewModel.shared.appStatuses.count) statuses: "
                  + self.blockedApps.map { ParentAppNameResolver.knownName(for: $0) ?? "?" }.joined(separator: ", "))
            self.collViewApprovedAppsList.reloadData()
            // Names arrive via ParentControlViewModel.updateAppName → appStatuses sink → reload.
            ParentAppNameResolver.shared.resolve(self.blockedApps)
        }
    }

}

//MARK: - Initialisations..
extension ParentSelfControlDriveVC
{
    func initilaisation()
    {
        self.lblDriveModeOn.isHidden = true // This will be shown while speed is above 15 mph
        // Dedicated cell — deliberately NOT the shared CellForAppsList, whose parent path
        // shows letter avatars for the child's (other-device) tokens.
        self.collViewApprovedAppsList.register(
            SelfDriveAppCell.self, forCellWithReuseIdentifier: SelfDriveAppCell.reuseId)

    }
}

//MARK: - Action events -
extension ParentSelfControlDriveVC {
    @IBAction private func tapToBack(_ sender: UIControl) {
        self.navigationController?.popViewController(animated: true)
    }
    @IBAction private func tapToAddApproveApps(_ sender: UIControl) {
        guard let container = AppBlockerManager.shared.modelContainer else { return }
        
        let parentControlView = ParentControlView(onBack: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })
        .modelContainer(container)

        let hostingController = UIHostingController(rootView: parentControlView)
        hostingController.navigationItem.hidesBackButton = true
        self.navigationController?.pushViewController(hostingController, animated: true)
    }
}

//MARK: - Collectionview delegates and datasource...
extension ParentSelfControlDriveVC: UICollectionViewDelegate, UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout
{
    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        return CGSize(width: 100, height: 100)
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
        -> Int
    {
        return blockedApps.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let cell =
            collectionView.dequeueReusableCell(
                withReuseIdentifier: SelfDriveAppCell.reuseId, for: indexPath) as! SelfDriveAppCell
        let token = blockedApps[indexPath.row]
        cell.configure(token: token, name: ParentAppNameResolver.knownName(for: token))
        return cell
    }
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        return 10
    }
}

//MARK: - Self-drive app cell -

/// Tile for one of the parent's own restricted apps (icon + real name).
///
/// Shows the resolved/cached name as plain text (like the child side). Until a name is
/// resolved, falls back to the system-drawn `Label(token).labelStyle(.titleOnly)`.
final class SelfDriveAppCell: UICollectionViewCell {
    static let reuseId = "SelfDriveAppCell"

    private let cardView = UIView()
    private var hostingController: UIHostingController<SelfDriveAppTile>?
    private var currentToken: ApplicationToken?

    override init(frame: CGRect) {
        super.init(frame: frame)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(named: "WhiteColor") ?? .white
        cardView.layer.cornerRadius = 8
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = (UIColor(named: "AppBorderGray") ?? .lightGray).cgColor
        cardView.clipsToBounds = true
        contentView.addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(token: ApplicationToken, name: String?) {
        let tile = SelfDriveAppTile(token: token, name: name)
        // Different app in a reused cell → drop the old hosting controller entirely so no
        // system-drawn view from the previous app survives.
        if currentToken != token, let old = hostingController {
            old.view.removeFromSuperview()
            hostingController = nil
        }
        currentToken = token
        if let hc = hostingController {
            hc.rootView = tile
        } else {
            let hc = UIHostingController(rootView: tile)
            hc.view.backgroundColor = .clear
            cardView.embed(hc)
            hostingController = hc
        }
    }
}

struct SelfDriveAppTile: View {
    let token: ApplicationToken
    let name: String?

    var body: some View {
        VStack(spacing: 6) {
            AppIconView(token: token, appName: name ?? "")
                .frame(width: 52, height: 52)
            Group {
                if let name {
                    Text(name)
                } else {
                    Label(token).labelStyle(.titleOnly)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color("AppDarkBlue"))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // System-drawn Label text follows the color scheme, not foregroundColor.
        .environment(\.colorScheme, .light)
        // Reused cells swap `token` in place; without a new identity the system-drawn
        // Label(token) can keep showing the PREVIOUS app. Force a fresh view per token.
        .id(token)
    }
}
