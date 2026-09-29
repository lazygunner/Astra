//
//  ToggleImmersiveSpaceButton.swift
//  Astra
//
//  Created by 关一鸣 on 9/5/26.
//

import SwiftUI

struct ToggleImmersiveSpaceButton: View {
    var controlsFullImmersion = false

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.immersiveSpaceState {
                    case .open:
                        if controlsFullImmersion {
                            appModel.toggleFullImmersion(reduceMotion: reduceMotion)
                            return
                        }
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                        // Don't set immersiveSpaceState to .closed because there
                        // are multiple paths to ImmersiveView.onDisappear().
                        // Only set .closed in ImmersiveView.onDisappear().

                    case .closed:
                        appModel.immersiveSpaceError = nil
                        appModel.pendingFullImmersion = controlsFullImmersion ? reduceMotion : nil
                        appModel.immersiveSpaceState = .inTransition
                        appModel.immersiveSpaceDidOpen = false
                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                            case .opened:
                                appModel.immersiveSpaceDidOpen = true
                                // Don't set immersiveSpaceState to .open because there
                                // may be multiple paths to ImmersiveView.onAppear().
                                // Only set .open in ImmersiveView.onAppear().
                                break

                            case .error:
                                appModel.resetImmersion()
                                appModel.immersiveSpaceError = "无法打开空间，请稍后重试。"
                                appModel.immersiveSpaceState = .closed

                            case .userCancelled:
                                // On error, we need to mark the immersive space
                                // as closed because it failed to open.
                                fallthrough
                            @unknown default:
                                appModel.resetImmersion()
                                // On unknown response, assume space did not open.
                                appModel.immersiveSpaceState = .closed
                        }

                    case .inTransition:
                        // This case should not ever happen because button is disabled for this case.
                        break
                }
            }
        } label: {
            Text(controlsFullImmersion
                 ? (appModel.isChangingImmersion ? "正在切换…" : (appModel.isFullyImmersed ? "恢复真实环境" : "进入全沉浸"))
                 : (appModel.immersiveSpaceState == .open ? "收起模型" : "放置模型"))
                .frame(minWidth: controlsFullImmersion ? 120 : nil)
        }
        .disabled(appModel.immersiveSpaceState == .inTransition || appModel.isChangingImmersion)
        .animation(.none, value: 0)
        .fontWeight(.semibold)
    }
}
