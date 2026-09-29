import SwiftUI
import RealityKit

@main
struct AstraApp: App {
    @State private var appModel = AppModel()

    init() {
        KeyboardActionComponent.registerComponent()
        TelephoneCordComponent.registerComponent()
        TelephoneCordSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 600, height: 720)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .preferredSurroundingsEffect(.colorMultiply(Color(
                    white: appModel.surroundingsBrightness
                )))
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.resetImmersion()
                }
        }
        .immersionStyle(selection: $appModel.immersionStyle, in: .mixed, .full)
    }
}
