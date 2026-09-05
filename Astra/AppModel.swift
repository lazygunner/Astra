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
    var immersiveSpaceError: String?
    var immersiveSpaceState = ImmersiveSpaceState.closed
}
