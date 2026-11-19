#!/bin/bash
# Move application(_:didReceiveRemoteNotification:fetchCompletionHandler:) to the main AppDelegate class

sed -i '' '/func application(_ application: UIApplication,/,$d' "/Users/apple/Downloads/GaurdianDrive_iOS/GaurdianDrive/AppDelegate/AppDelegate.swift"
git checkout /Users/apple/Downloads/GaurdianDrive_iOS/GaurdianDrive/AppDelegate/AppDelegate.swift
