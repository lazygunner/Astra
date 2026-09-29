import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var tab = 0

    var body: some View {
        let placement = appModel.placement
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YVR 600C").font(.title.bold())
                    Text("空间视频控制台").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    ToggleImmersiveSpaceButton()
                    ToggleImmersiveSpaceButton(controlsFullImmersion: true)
                }
            }
            .padding(24)
            Picker("控制台", selection: $tab) {
                Text("播放与投影").tag(0)
                Text("数字键视频").tag(1)
                Text("模型调整").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = appModel.immersiveSpaceError ?? placement.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        if appModel.immersiveSpaceState == .open {
                            Button("重新加载模型") { Task { await placement.load() } }
                                .disabled(placement.isLoading)
                        }
                    }
                    if let warning = appModel.spatialTrackingWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if placement.isLoading { ProgressView("正在加载模型…") }
                    switch tab {
                    case 1:
                        VideoPresetControls(video: placement.screenVideo)
                    case 2:
                        if placement.isReady { ModelAdjustmentControls(placement: placement) }
                        else { ContentUnavailableView("尚未放置模型", systemImage: "cube.transparent", description: Text("放置模型后可调整大小、朝向和零件。")) }
                    default:
                        if !placement.isReady {
                            Label("先放置模型，即可播放；也可提前配置数字键视频。", systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        ScreenVideoControls(video: placement.screenVideo)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(placement.isReady ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(placement.isReady ? "模型已就绪" : "模型未放置")
                Spacer()
                Text(placement.screenVideo.lastModelAction).lineLimit(1)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(minWidth: 540, idealWidth: 600, maxWidth: .infinity, minHeight: 580)
    }
}

private struct ModelAdjustmentControls: View {
    @Bindable var placement: ModelPlacement
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("模型调整").font(.title2.bold())
            Text("捏合上方机身拖动；双手拉开缩放、转动旋转。拆解期间停用模型播放按键。")
                .foregroundStyle(.secondary)
            HStack {
                Button(placement.assembly.isExpanded ? "收合模型" : "爆炸展开", systemImage: "arrow.up.left.and.arrow.down.right") { placement.assembly.toggleExpansion() }
                Button(placement.assembly.partsAreUnlocked ? "锁定零件" : "解锁零件", systemImage: "lock") { placement.assembly.toggleParts() }
            }
            .disabled(!placement.assembly.canExpand || placement.isManipulating || placement.assembly.isAnimating)
            Text("\(placement.assembly.partCount) 个零件 · " + (placement.assembly.partsAreUnlocked ? "单独操作" : "整体操作"))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 16) {
                HStack {
                    Text("整体缩放")
                    Spacer()
                    Text(placement.scale, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                Slider(value: Binding(get: { placement.scale }, set: { placement.setScale($0) }), in: 0.25...3)
                    .accessibilityLabel("模型缩放")
                HStack {
                    Button("左转", systemImage: "rotate.left") { placement.rotate(degrees: 15) }
                    Button("右转", systemImage: "rotate.right") { placement.rotate(degrees: -15) }
                    Spacer()
                    Button("降低", systemImage: "arrow.down") { placement.moveHeight(-0.1) }
                    Button("升高", systemImage: "arrow.up") { placement.moveHeight(0.1) }
                }
                Button("重置位置与大小") { placement.reset() }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .disabled(placement.isManipulating || placement.assembly.isAnimating)
        }
    }
}

#Preview { ContentView().environment(AppModel()) }
