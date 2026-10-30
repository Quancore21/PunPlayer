//
//  PunPlayer — UI/ScreenMetrics.swift
//  Pre-computes and caches device screen dimensions at launch so the player
//  layout never animates or stretches in real time during navigation transitions.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

/// Caches device screen dimensions and layout metrics at app launch.
/// Immutable value type: pure, thread-safe, and crash-proof.
struct ScreenMetrics {
    static let shared = ScreenMetrics()

    let screenSize: CGSize
    let isCompact: Bool
    let availableContentHeight: CGFloat
    let artworkSide: CGFloat
    let drawerWidth: CGFloat
    let controlsFootprint: CGFloat
    let headerFootprint: CGFloat

    private init() {
        let bounds = UIScreen.main.bounds
        let width = bounds.width > 0 ? bounds.width : 390
        let height = bounds.height > 0 ? bounds.height : 844
        self.screenSize = CGSize(width: width, height: height)

        let compact = height < 700
        self.isCompact = compact

        let ctrlFootprint: CGFloat = compact ? 210 : 240
        let hdrFootprint: CGFloat = 52
        let vMargins: CGFloat = 16
        self.controlsFootprint = ctrlFootprint
        self.headerFootprint = hdrFootprint

        let availableWidth = max(120, width - 44)
        // Approximate safe area vertical padding (status bar + home indicator)
        let safeVertical: CGFloat = height >= 800 ? 81 : 20
        let contentH = max(400, height - safeVertical)
        self.availableContentHeight = contentH

        let availableForArt = max(90, contentH - ctrlFootprint - hdrFootprint - vMargins)
        let maxAllowedArt = min(availableWidth, compact ? 190 : 275)

        self.artworkSide = max(90, min(maxAllowedArt, availableForArt))
        self.drawerWidth = min(width * 0.92, 420)
    }
}
