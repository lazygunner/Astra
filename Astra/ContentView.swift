import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let placement = appModel.placement
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("YVR 600C", systemImage: "cube.transparent")
                    .font(.largeTitle.bold())
                Text("空间模型工作台").font(.title3).foregroundStyle(.secondary)
                Text("注视模型并捏合拖动，松手即可放置。双手捏合后拉开或收拢以缩放，转动双手以旋转。")
                    .foregroundStyle(.secondary)
                ToggleImmersiveSpaceButton()
                if let error = appModel.immersiveSpaceError {
                    Text(error).foregroundStyle(.red)
                }
                if placement.isLoading {
                    ProgressView("正在加载模型…")
                }
                if let error = placement.errorMessage {
                    Text(error).foregroundStyle(.red)
                    if appModel.immersiveSpaceState == .open {
                        Button("重新加载") { Task { await placement.load() } }
                            .disabled(placement.isLoading)
                    }
                }
                if placement.isReady {
                    Divider()
                    HStack {
                        Button(placement.assembly.isExpanded ? "收合模型" : "爆炸展开",
                               systemImage: "arrow.up.left.and.arrow.down.right") {
                            placement.assembly.toggleExpansion()
                        }
                        Button(placement.assembly.partsAreUnlocked ? "锁定零件" : "解锁零件",
                               systemImage: placement.assembly.partsAreUnlocked ? "lock.open" : "lock") {
                            placement.assembly.toggleParts()
                        }
                    }
                    .disabled(!placement.assembly.canExpand || placement.isManipulating || placement.assembly.isAnimating)
                    Text(placement.assembly.canExpand
                         ? "\(placement.assembly.partCount) 个零件 · " + (placement.assembly.partsAreUnlocked ? "可单独捏合操作零件" : "当前操作整个模型")
                         : "此模型未检测到可拆分的零件层级")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack {
                        Text("整体缩放")
                        Spacer()
                        Text(placement.scale, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    Slider(value: Binding(get: { placement.scale }, set: { placement.setScale($0) }), in: 0.25...3)
                        .accessibilityLabel("模型缩放")
                        .disabled(placement.isManipulating || placement.assembly.isAnimating)
                    HStack {
                        Button("左转 15°", systemImage: "rotate.left") { placement.rotate(degrees: 15) }
                        Button("右转 15°", systemImage: "rotate.right") { placement.rotate(degrees: -15) }
                    }
                    .disabled(placement.isManipulating || placement.assembly.isAnimating)
                    HStack {
                        Button("降低", systemImage: "arrow.down") { placement.moveHeight(-0.1) }
                        Button("升高", systemImage: "arrow.up") { placement.moveHeight(0.1) }
                        Spacer()
                        Button("重置") { placement.reset() }
                    }
                    .disabled(placement.isManipulating || placement.assembly.isAnimating)
                    Text("初始最大尺寸 60 厘米 · 自由空间放置")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(32)
        }
        .frame(width: 480)
    }
}

#Preview {
    ContentView().environment(AppModel())
}
