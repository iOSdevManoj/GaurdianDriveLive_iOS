#!/bin/bash
# Replaces handleChildDataNotification and handleParentDataNotification signatures

sed -i '' 's/private func handleParentDataNotification(_ userInfo: \[AnyHashable: Any\]) {/private func handleParentDataNotification(_ userInfo: \[AnyHashable: Any\], completion: @escaping () -> Void = {}) {/g' "/Users/apple/Downloads/GaurdianDrive_iOS/GaurdianDrive/AppDelegate/AppDelegate.swift"

sed -i '' 's/private func handleChildDataNotification(_ userInfo: \[AnyHashable: Any\]) {/private func handleChildDataNotification(_ userInfo: \[AnyHashable: Any\], completion: @escaping () -> Void = {}) {/g' "/Users/apple/Downloads/GaurdianDrive_iOS/GaurdianDrive/AppDelegate/AppDelegate.swift"

