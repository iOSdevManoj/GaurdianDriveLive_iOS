//
//  ViewForNoLocationTrackingRequest.swift
//  GaurdianDrive
//
//  Confirmation popup shown before the child sends a "No Location Tracking"
//  request to their parent. Mirrors the presentation style of
//  ViewForNoDriveRequest (full-screen dismissible backdrop + centered card)
//  but has no form fields — just a description and a single "Send Request"
//  action, matching the design provided.
//

import UIKit

class ViewForNoLocationTrackingRequest: UIView {

    // MARK: - Outlets
    @IBOutlet weak var btnSendReq: UIButton!

    // MARK: - Callbacks
    var onSubmit: (() -> Void)?
    var onCloseView: (() -> Void)?

    // MARK: - XIB Initialisation
    static func loadXib() -> ViewForNoLocationTrackingRequest {
        let nib = UINib(nibName: "ViewForNoLocationTrackingRequest", bundle: nil)
        return nib.instantiate(withOwner: nil, options: nil).first as! ViewForNoLocationTrackingRequest
    }
}

// MARK: - Click events
extension ViewForNoLocationTrackingRequest {

    @IBAction func tapToSubmitRequest(_ sender: UIButton) {
        onSubmit?()
    }

    @IBAction func tapToCloseView(_ sender: UIButton) {
        onCloseView?()
    }
}
