//  ForkSettingsGroup.swift
//  Personal fork only (not upstream).
//
//  The long Settings page, split into the groups the More menu links to. SettingsView keeps every
//  card and all of its state; a group only chooses which cards one page shows.

import SwiftUI

enum ForkSettingsGroup: String, Hashable, CaseIterable {
    case profile, strap, look, alerts, scores, backup, advanced, about

    var title: LocalizedStringKey {
        switch self {
        case .profile:  return "Profile"
        case .strap:    return "Strap settings"
        case .look:     return "Look and feel"
        case .alerts:   return "Live notifications"
        case .scores:   return "Scores and units"
        case .backup:   return "Backup and restore"
        case .advanced: return "Features and experiments"
        case .about:    return "About"
        }
    }
}
