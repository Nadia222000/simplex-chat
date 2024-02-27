//
//  AppSettings.swift
//  SimpleX (iOS)
//
//  Created by Avently on 26.02.2024.
//  Copyright © 2024 SimpleX Chat. All rights reserved.
//

import Foundation
import SimpleXChat

extension AppSettings {
    public func importIntoApp() {
        let def = UserDefaults.standard
        if let val = networkConfig { setNetCfg(val) }
        if let val = privacyEncryptLocalFiles { privacyEncryptLocalFilesGroupDefault.set(val) }
        if let val = privacyAcceptImages {
            privacyAcceptImagesGroupDefault.set(val)
            def.setValue(val, forKey: DEFAULT_PRIVACY_ACCEPT_IMAGES)
        }
        if let val = privacyLinkPreviews { def.setValue(val, forKey: DEFAULT_PRIVACY_LINK_PREVIEWS) }
        if let val = privacyShowChatPreviews { def.setValue(val, forKey: DEFAULT_PRIVACY_SHOW_CHAT_PREVIEWS) }
        if let val = privacySaveLastDraft { def.setValue(val, forKey: DEFAULT_PRIVACY_SAVE_LAST_DRAFT) }
        if let val = privacyProtectScreen { def.setValue(val, forKey: DEFAULT_PRIVACY_PROTECT_SCREEN) }
        if let val = notificationMode { ChatModel.shared.notificationMode = val.toNotificationsMode() }
        if let val = notificationPreviewMode { ntfPreviewModeGroupDefault.set(val) }
        if let val = webrtcPolicyRelay { def.setValue(val, forKey: DEFAULT_WEBRTC_POLICY_RELAY) }
        if let val = webrtcICEServers { def.setValue(val, forKey: DEFAULT_WEBRTC_ICE_SERVERS) }
        if let val = confirmRemoteSessions { def.setValue(val, forKey: DEFAULT_CONFIRM_REMOTE_SESSIONS) }
        if let val = connectRemoteViaMulticast { def.setValue(val, forKey: DEFAULT_CONNECT_REMOTE_VIA_MULTICAST) }
        if let val = connectRemoteViaMulticastAuto { def.setValue(val, forKey: DEFAULT_CONNECT_REMOTE_VIA_MULTICAST_AUTO) }
        if let val = developerTools { def.setValue(val, forKey: DEFAULT_DEVELOPER_TOOLS) }
        if let val = confirmDBUpgrades { confirmDBUpgradesGroupDefault.set(val) }
        if let val = androidCallOnLockScreen { def.setValue(val.rawValue, forKey: ANDROID_DEFAULT_CALL_ON_LOCK_SCREEN) }
        if let val = iosCallKitEnabled { callKitEnabledGroupDefault.set(val) }
        if let val = iosCallKitCallsInRecents { callKitEnabledGroupDefault.set(val) }
    }

    public static var current: AppSettings {
        let def = UserDefaults.standard
        var c = AppSettings.defaults
        c.networkConfig = getNetCfg()
        c.privacyEncryptLocalFiles = privacyEncryptLocalFilesGroupDefault.get()
        c.privacyAcceptImages = privacyAcceptImagesGroupDefault.get()
        c.privacyLinkPreviews = def.bool(forKey: DEFAULT_PRIVACY_LINK_PREVIEWS)
        c.privacyShowChatPreviews = def.bool(forKey: DEFAULT_PRIVACY_SHOW_CHAT_PREVIEWS)
        c.privacySaveLastDraft = def.bool(forKey: DEFAULT_PRIVACY_SAVE_LAST_DRAFT)
        c.privacyProtectScreen = def.bool(forKey: DEFAULT_PRIVACY_PROTECT_SCREEN)
        c.notificationMode = NotificationMode.from(ChatModel.shared.notificationMode)
        c.notificationPreviewMode = ntfPreviewModeGroupDefault.get()
        c.webrtcPolicyRelay = def.bool(forKey: DEFAULT_WEBRTC_POLICY_RELAY)
        c.webrtcICEServers = def.stringArray(forKey: DEFAULT_WEBRTC_ICE_SERVERS)
        c.confirmRemoteSessions = def.bool(forKey: DEFAULT_CONFIRM_REMOTE_SESSIONS)
        c.connectRemoteViaMulticast = def.bool(forKey: DEFAULT_CONNECT_REMOTE_VIA_MULTICAST)
        c.connectRemoteViaMulticastAuto = def.bool(forKey: DEFAULT_CONNECT_REMOTE_VIA_MULTICAST_AUTO)
        c.developerTools = def.bool(forKey: DEFAULT_DEVELOPER_TOOLS)
        c.confirmDBUpgrades = confirmDBUpgradesGroupDefault.get()
        c.androidCallOnLockScreen = LockScreenCalls(rawValue: def.string(forKey: ANDROID_DEFAULT_CALL_ON_LOCK_SCREEN)!)
        c.iosCallKitEnabled = callKitEnabledGroupDefault.get()
        c.iosCallKitCallsInRecents = callKitEnabledGroupDefault.get()
        return c
    }
}
