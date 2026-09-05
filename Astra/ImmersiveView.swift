import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var subscriptions: [EventSubscription] = []

    var body: some View {
        RealityView { content in
            let placement = appModel.placement
            content.add(placement.root)
            subscriptions = [
                content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                    placement.manipulationBegan(event.entity)
                },
                content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { event in
                    placement.manipulationUpdated(event.entity)
                },
                content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                    placement.manipulationEnded(event.entity)
                }
            ]
            await placement.load()
        }
        .onDisappear {
            subscriptions.forEach { $0.cancel() }
            subscriptions.removeAll()
            appModel.placement.unload()
        }
    }
}
