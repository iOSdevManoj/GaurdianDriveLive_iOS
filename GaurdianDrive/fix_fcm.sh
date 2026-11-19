#!/bin/bash
# A script to modify AppDelegate to observe FCMToken and trigger saveDeviceTokenForRegisterUser

# Check if observer is already there
if grep -q 'NotificationCenter.default.addObserver(self, selector: #selector(fcmTokenUpdated)' "/Users/apple/Downloads/GaurdianDrive_iOS/GaurdianDrive/AppDelegate/AppDelegate.swift"; then
    echo "Observer already exists"
else
    # Insert observer in didFinishLaunchingWithOptions
    sed -i '' '/self.checkLogin()/i\
        NotificationCenter.default.addObserver(self, selector: #selector(fcmTokenUpdated), name: Notification.Name("FCMToken"), object: nil)\
' "/Users/apple/Downloads/GaurdianDrive_iOS/GaurdianDrive/AppDelegate/AppDelegate.swift"

    # Insert the selector function
    sed -i '' '/func saveDeviceTokenForRegisterUser/i\
    @objc func fcmTokenUpdated(_ notification: Notification) {\
        if UserDefaults.Main.string(forKey: .userToken) != "" {\
            self.saveDeviceTokenForRegisterUser()\
        }\
    }\
\
' "/Users/apple/Downloads/GaurdianDrive_iOS/GaurdianDrive/AppDelegate/AppDelegate.swift"
    echo "Added FCMToken observer to AppDelegate"
fi
