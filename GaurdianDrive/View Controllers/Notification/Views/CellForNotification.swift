//
//  CellForNotification.swift
//  GaurdianDrive
//
//  Created by KETAN on 22/12/25.
//

import UIKit

class CellForNotification: UITableViewCell {
    
    //Outlets....
    @IBOutlet var lblTitle: UILabel!
    @IBOutlet var lblTime: UILabel!
    @IBOutlet var imgProfile: UIImageView!
    @IBOutlet var lblRedDot: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        self.lblRedDot.layer.masksToBounds = true
        self.lblRedDot.layer.cornerRadius = 2.5
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    func setNotificationCellData(aModelData:NotificationModel)
    {
        self.lblTitle.text = aModelData.body
        let displayTime = getTimeAgo(from: aModelData.time)
        self.lblTime.text = displayTime
        self.imgProfile.image = UIImage(named: Self.iconName(forType: aModelData.type))
            ?? UIImage(named: "ic_notification_temp")
        if aModelData.isRead
        {
            self.lblRedDot.isHidden = true
        }else{
            self.lblRedDot.isHidden = false
        }
    }

    /// Asset name for a notification `type` (icons from the Figma "notification types" legend).
    /// Falls back to the generic bell when the asset isn't in the catalog yet.
    static func iconName(forType rawType: String) -> String {
        let type = rawType.uppercased()
        let isNoDrive = type.contains("NDM") || type.contains("NO_DRIVE") || type.contains("NONE_DRIVE")

        if type.contains("FREE_TRIAL") {
            return type.contains("WILL_EXPIRE") ? "ic_notif_free_trial_will_expire" : "ic_notif_free_trial_expired"
        }
        if type.contains("SUBSCRIPTION") {
            return type.contains("WILL_EXPIRE") ? "ic_notif_subscription_will_expire" : "ic_notif_subscription_expired"
        }
        if type.contains("TAMPER") { return "ic_notif_tampered" }
        if type.contains("SPEED") { return "ic_notif_over_speed" }
        if type.contains("ARRIV") || type.contains("REACH") || type.contains("LOCATION") {
            return "ic_notif_location_reached"
        }
        if type.contains("CANCEL_BY_PARENT") { return "ic_notif_cancel_by_parent" }
        if type.contains("APPROVE") { return isNoDrive ? "ic_notif_no_drive_approve" : "ic_notif_approve" }
        if type.contains("REJECT") || type.contains("DECLINE") {
            return isNoDrive ? "ic_notif_no_drive_cancel" : "ic_notif_reject"
        }
        if type.contains("CANCEL") { return isNoDrive ? "ic_notif_no_drive_cancel" : "ic_notif_cancel" }
        if type.contains("REQUEST") { return isNoDrive ? "ic_notif_no_drive_request" : "ic_notif_request" }
        return "ic_notification_temp"
    }
}
