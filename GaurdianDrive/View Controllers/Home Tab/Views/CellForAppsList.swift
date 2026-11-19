//
//  CellForAppsList.swift
//  GaurdianDrive
//
//  Created by KETAN on 17/12/25.
//

import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit

class CellForAppsList: UICollectionViewCell {

    // MARK: - Outlets
    @IBOutlet var imgApp: UIImageView!
    @IBOutlet var lblAppName: UILabel!
    @IBOutlet var btnDeleteAdd: UIControl!
    @IBOutlet var imgDeleteAdd: UIImageView!
    @IBOutlet var viewForWhiteBG: UIView!

    // MARK: - Variables
    var onActionTap: (() -> Void)?

    private var iconHostingController: UIHostingController<AnyView>?
    private var nameHostingController: UIHostingController<AnyView>?

    override func awakeFromNib() {
        super.awakeFromNib()
        lblAppName.adjustsFontSizeToFitWidth = false
        lblAppName.font =
            UIFont(name: "PlusJakartaSans-Medium", size: 10)
            ?? UIFont.systemFont(ofSize: 10, weight: .medium)
        lblAppName.numberOfLines = 1
        lblAppName.textAlignment = .center
        imgApp.contentMode = .scaleAspectFit
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imgApp.image = nil
        lblAppName.text = nil
        tearDownIconHostingController()
        tearDownNameHostingController()
    }

    // MARK: - Configuration

    func configure(app: ChildRequestedApp, isApproved: Bool, isFromChild: Bool) {
        imgDeleteAdd.image = UIImage(
            named: isApproved ? "ic_removeApp_red" : "ic_addApp_green"
        )

        // Check persistent name cache first using the canonical re-encoded token key
        var bestName = app.displayAppName
        if let appToken = app.getApplicationToken(),
           let tokenData = try? JSONEncoder().encode(appToken) {
            let canonicalKey = tokenData.base64EncodedString()
            if let cached = AppNameResolutionCache.cachedName(forTokenStr: canonicalKey) {
                bestName = cached
            } else if let rawKey = app.token,
                      let cached = AppNameResolutionCache.cachedName(forTokenStr: rawKey) {
                bestName = cached
            }
        }

        let isRealName: Bool = {
            return !bestName.isEmpty
                && bestName != "Unknown"
                && bestName != "Unknown App"
                && bestName != "Removed App"
                && bestName != "Pending Resolution..."
        }()

        let isParent = UserDefaults.Main.bool(forKey: .isParent)

        if isParent {
            // Parent device or Android child: show letter avatar
            tearDownIconHostingController()
            tearDownNameHostingController()
            self.showLetterAvatar(for: bestName)
            lblAppName.text = bestName
            lblAppName.textColor = isFromChild ? .white : .black
        } else if let appToken = app.getApplicationToken() {
            imgApp.backgroundColor = .clear
            imgApp.image = nil
            imgApp.subviews.forEach { $0.removeFromSuperview() }
            updateOrCreateIconHostingController(token: appToken, appName: bestName)

            if isRealName {
                tearDownNameHostingController()
                lblAppName.text = bestName
                lblAppName.textColor = isFromChild ? .white : .black
            } else {
                // Show placeholder text immediately while FamilyControls resolves the name
                lblAppName.text = "..."
                lblAppName.textColor = (isFromChild ? UIColor.white : UIColor.black).withAlphaComponent(0.4)
                updateOrCreateNameHostingController(token: appToken, color: isFromChild ? .white : .black)
            }
        } else {
            // No token — use plain UIKit views; remove any hosted views
            tearDownIconHostingController()
            tearDownNameHostingController()
            self.showLetterAvatar(for: bestName)
            lblAppName.text = bestName
            lblAppName.textColor = isFromChild ? .white : .black
        }

        if isFromChild {
            imgDeleteAdd.isHidden = true
            btnDeleteAdd.isHidden = true
            viewForWhiteBG.backgroundColor = .clear
            viewForWhiteBG.layer.borderWidth = 0
            viewForWhiteBG.layer.borderColor = UIColor.clear.cgColor
        }
    }

    // MARK: - Private helpers

    private func showLetterAvatar(for name: String) {
        imgApp.isHidden = false
        imgApp.image = nil
        imgApp.subviews.forEach { $0.removeFromSuperview() }

        let palette: [UIColor] = [
            UIColor(red: 0.29, green: 0.56, blue: 0.89, alpha: 1),
            UIColor(red: 0.20, green: 0.74, blue: 0.47, alpha: 1),
            UIColor(red: 0.91, green: 0.43, blue: 0.35, alpha: 1),
            UIColor(red: 0.57, green: 0.36, blue: 0.84, alpha: 1),
            UIColor(red: 0.98, green: 0.69, blue: 0.21, alpha: 1),
            UIColor(red: 0.16, green: 0.71, blue: 0.87, alpha: 1),
            UIColor(red: 0.91, green: 0.30, blue: 0.58, alpha: 1),
            UIColor(red: 0.26, green: 0.63, blue: 0.28, alpha: 1),
        ]
        let cleanName = name.isEmpty ? "?" : name
        let seed = Int(cleanName.unicodeScalars.first?.value ?? 65)
        let bgColor = palette[seed % palette.count]
        let letter = String(cleanName.prefix(1)).uppercased()

        imgApp.backgroundColor = bgColor
        imgApp.layer.cornerRadius = 10
        imgApp.clipsToBounds = true

        let lbl = UILabel()
        lbl.text = letter
        lbl.textColor = .white
        lbl.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        imgApp.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: imgApp.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: imgApp.centerYAnchor)
        ])
    }

    /// Update an existing icon hosting controller's rootView, or create one if needed.
    private func updateOrCreateIconHostingController(token: ApplicationToken, appName: String) {
        let newView = AnyView(
            AppIconView(token: token, appName: appName)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        imgApp.viewWithTag(999)?.removeFromSuperview()
        imgApp.subviews.forEach { $0.removeFromSuperview() }
        if let hc = iconHostingController {
            // Reuse: just swap the view model — no blank flash
            hc.rootView = newView
            // Ensure the view is still embedded (it shouldn't have been removed)
            if hc.view.superview == nil {
                imgApp.embed(hc)
            }
        } else {
            let hc = UIHostingController(rootView: newView)
            hc.view.tag = 999
            hc.view.backgroundColor = .clear
            imgApp.embed(hc)
            iconHostingController = hc
        }
    }

    /// Update an existing name hosting controller's rootView, or create one if needed.
    private func updateOrCreateNameHostingController(token: ApplicationToken, color: Color) {
        // Use LabelWithNameCapture so the resolved name is cached and the UIKit label updated
        let newView = AnyView(
            LabelWithNameCapture(token: token) { [weak self] (resolvedName: String) in
                guard let self = self, AppNameResolution.isResolved(resolvedName) else { return }
                // Cache under canonical key for future opens
                if let tokenData = try? JSONEncoder().encode(token) {
                    AppNameResolutionCache.store(name: resolvedName, forTokenStr: tokenData.base64EncodedString())
                }
                // Update the UIKit label directly — no cell reload needed
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.tearDownNameHostingController()
                    self.lblAppName.text = resolvedName
                    self.lblAppName.textColor = color == .white ? .white : .black
                    self.lblAppName.alpha = 1.0
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        lblAppName.viewWithTag(998)?.removeFromSuperview()
        lblAppName.subviews.forEach { $0.removeFromSuperview() }
        if let hc = nameHostingController {
            hc.rootView = newView
            if hc.view.superview == nil {
                lblAppName.embed(hc)
            }
        } else {
            let hc = UIHostingController(rootView: newView)
            hc.view.tag = 998
            hc.view.backgroundColor = .clear
            lblAppName.embed(hc)
            nameHostingController = hc
        }
    }

    private func tearDownIconHostingController() {
        iconHostingController?.view.removeFromSuperview()
        iconHostingController = nil
        imgApp.viewWithTag(999)?.removeFromSuperview()
        imgApp.subviews.forEach { $0.removeFromSuperview() }
    }

    private func tearDownNameHostingController() {
        nameHostingController?.view.removeFromSuperview()
        nameHostingController = nil
        lblAppName.viewWithTag(998)?.removeFromSuperview()
        lblAppName.subviews.forEach { $0.removeFromSuperview() }
    }
}

// MARK: - Click Events
extension CellForAppsList {
    @IBAction func tapToDeleteAdd(_ sender: UIControl) {
        onActionTap?()
    }
}
