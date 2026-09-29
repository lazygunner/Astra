//
//  AppModel.swift
//  Astra
//
//  Created by 关一鸣 on 9/5/26.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let placement = ModelPlacement()
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceDidOpen = false
    var immersiveSpaceError: String?
    var immersiveSpaceState = ImmersiveSpaceState.closed {
        didSet {
            if immersiveSpaceState == .open, let reduceMotion = pendingFullImmersion {
                pendingFullImmersion = nil
                toggleFullImmersion(reduceMotion: reduceMotion)
            }
        }
    }
    var pendingFullImmersion: Bool?
    var spatialTrackingWarning: String?
    var immersionStyle: ImmersionStyle = .mixed
    var surroundingsBrightness = 1.0
    var isChangingImmersion = false
    private var immersionTask: Task<Void, Never>?

    var isFullyImmersed: Bool { immersionStyle is FullImmersionStyle }

    func toggleFullImmersion(reduceMotion: Bool) {
        guard immersiveSpaceState == .open, !isChangingImmersion else { return }
        let entering = !isFullyImmersed
        isChangingImmersion = true
        immersionTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            defer {
                if !Task.isCancelled { isChangingImmersion = false }
            }
            if !entering { immersionStyle = .mixed }
            do {
                // Fade passthrough first; full style then removes it completely.
                // Drive the preference explicitly because it isn't an animatable value.
                let steps = reduceMotion ? 1 : 45
                for step in 1...steps {
                    try await Task.sleep(for: .milliseconds(20))
                    let progress = Double(step) / Double(steps)
                    let eased = progress * progress * (3 - 2 * progress)
                    surroundingsBrightness = entering ? 1 - eased : eased
                }
                if entering { immersionStyle = .full }
            } catch {
                // Dismissal cancels the transition and restores defaults below.
            }
        }
    }

    func resetImmersion() {
        pendingFullImmersion = nil
        immersionTask?.cancel()
        immersionTask = nil
        immersionStyle = .mixed
        surroundingsBrightness = 1
        isChangingImmersion = false
    }
}
