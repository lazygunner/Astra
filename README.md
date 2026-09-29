# Astra — YVR 600C & Spatial Computing Showcase

A visionOS application for exploring, manipulating, and interacting with high-fidelity 3D assets on Apple Vision Pro.

The 3D assets in this repository—including the **YVR 600C** retro-futuristic terminal and the **Hotline Glass Cube** room—were generated using **GPT-6 Astra**.

---

## 📺 Featured Demos & Community Discussions (视频与社区)

- 📱 **Reddit (r/VisionPro)**: [GPT-6 Astra just saved Apple Vision Pro.](https://www.reddit.com/r/VisionPro/comments/1w86few/gpt6_astra_just_saved_apple_vision_pro/)
  > *"From a single 2D reference image to a full Blender 3D model and a functional visionOS app—completely end-to-end in one shot! 3D content pipeline costs are about to plummet, breathing massive new life into Vision Pro and spatial computing."*
- 📺 **Bilibili (XR老关)**: [用 GPT-6 把《控制》的热线电话室搬到家里](https://www.bilibili.com/video/BV1F5YJ63EGW/)
  > 视频演示使用 GPT-6 Astra 基于多视角参考图复刻经典游戏《Control》（控制）中的热线电话玻璃房场景，并在 Apple Vision Pro 中实现可抓握旋转的实体听筒与动态弹簧线缆交互。

---

## ✨ Features (核心特性)

### 1. 🖥️ YVR 600C Terminal & Exploded View (复古终端与爆炸图分解)
- **Spatial Gestures**: Place, translate, rotate, and scale the model naturally using visionOS system gestures.
- **16-Mesh Animated Exploded View**: Smoothly expand the model into its 16 constituent mesh groups to inspect internal structures.
- **Independent Part Manipulation**: Unlock individual parts to reposition, rotate, and scale them separately in 3D space, with one-touch reassembly and reset.
- **Housing Manipulation Proxy**: Grab the upper housing to reposition the assembled model without interfering with interactive keys.

### 2. 🎬 Curved Screen Video & Real-World Wall Projector (曲面屏播放与真实墙面投影)
- **Screen Video Playback**:
  - Load MP4 / MOV videos from Photos library or local Files.
  - Runtime UV remapping on the curved screen mesh (without altering the bundled USDZ asset).
  - Preserves video aspect ratio via symmetrical center cropping without stretching.
  - Video seamlessly follows the screen geometry during motion and exploded-view animations.
  - Select **恢复原屏幕** to stop playback and restore original screen display.
- **Physical Wall Video Projector (visionOS 27+)**:
  - Uses RealityKit `SpotLightComponent.ProjectiveTexture` and `SurroundingsLight` to cast video light onto real-world room walls and physical surfaces.
  - Low-level GPU synchronization via `LowLevelTexture.replace(using:)` for smooth frame submission.
  - Fits decoded frames into a black square mask (up to 1024 px) with presentation aspect ratio preserved and Core Image vertical flip applied.
  - **Projection Test Mode**: Toggle **测试墙面投影** to cast a static checkerboard with a red cross to test physical surface detection and lighting before playing video.

### 3. ⌨️ Direct-Touch Model Controls & Video Presets (实体触控按键与预设切换)
- **Direct-Touch Model Colliders**:
  - Native key entities configured with `InputTargetComponent(allowedInputTypes: .all)` and solid `CollisionComponent` shapes.
  - System taps routed through `TapGesture().targetedToAnyEntity()` without invisible SwiftUI attachment latency.
- **Keyboard Shortcuts**:
  - Left main keyboard area: Play / Pause toggle.
  - Right number-pad area: Video projector toggle.
  - Synthesized sound feedback for key presses and unavailable actions.
- **5 Engraved Preset Keys (1–5)**:
  - Direct selection keys below the screen mapped to preset slots 1–5.
  - Videos configured via Photos or Files are copied to `Application Support` with an atomically saved manifest persisting across app restarts.
- **Visual Debugging**:
  - Enable **显示按键触碰区域** under **数字键视频** to display cyan bounding boxes matching the exact physical colliders for reach and gaze validation.

### 4. ☎️ Hotline Glass Cube & Interactive Telephone Handset (热线电话玻璃房与动态电话线)
- **Immersive Scene Inspired by *Control***:
  - Step into the atmospheric Hotline Glass Room replicated directly in spatial computing.
- **Interactive Handset (`AstraTelephoneHandset`)**:
  - Pinch to pick up and rotate the telephone handset using visionOS system manipulation (direct and indirect touch).
  - Automatically animates back to resting cradle pose when released; position/scale reset also restores that pose.
- **Real-Time Dynamic Coiled Cord Geometry (`TelephoneCordGeometry`)**:
  - Parametric 3D coiled spring geometry generated in real-time by a dedicated RealityKit system.
  - Fixed base socket and handset socket: wire coils dynamically stretch, compress, and narrow as the handset moves.
  - Reusable mesh buffer updating only on endpoint or orientation changes, avoiding physics solver jitters or drift.

---

## 🚀 Getting Started (快速上手)

### Requirements (系统与设备要求)
- **Hardware**: Apple Vision Pro (physical device recommended for spatial gesture, touch, and lighting validation).
- **Software**: visionOS 26 or later (visionOS 27+ and Apple6 GPU feature support required for projective textures).
- **Toolchain**: Xcode 27 or later.

### Building & Running (编译与运行)
1. Clone this repository and open `Astra.xcodeproj`.
2. Select the `Astra` scheme and configure your developer Signing Team.
3. Build and run on Apple Vision Pro or the visionOS Simulator.
4. Select **放置模型** (Place Model) or toggle the **Immersive Space** button to begin.

> **Note**: The user interface controls are currently in Chinese.

---

## 🛠️ Verification & Asset Tooling (测试与工具脚本)

The repository provides standalone test and asset preparation tools:

- **Telephone Cord Geometry Checks**:
  ```bash
  swiftc -O -parse-as-library Astra/TelephoneCordGeometry.swift Tests/TelephoneCordGeometryChecks.swift -o /tmp/astra-cord-checks && /tmp/astra-cord-checks
  ```
  Validates socket attachment, coincident/rotated endpoints, mesh topology, wire thickness, and drift-free return.

- **Handset USDZ Separation Tool (Python `usd-core`)**:
  ```bash
  python3 Scripts/prepare_handset.py source.usdz output.usdz
  ```
  Separates connected components of the merged USDZ asset (shell, seams, earpieces) while preserving normals, UVs, and materials.

- **Handset Asset Topology Verification**:
  ```bash
  python3 Tests/HandsetAssetChecks.py source.usdz output.usdz
  ```
  Compares face count (preserving all 134,857 faces), UVs, normals, and materials between raw and split assets.

- **Video Presets Persistence Checks**:
  ```bash
  swiftc -parse-as-library Astra/VideoPresets.swift Tests/VideoPresetsChecks.swift -o /tmp/video-presets-checks && /tmp/video-presets-checks
  ```

---

## 📚 References & Acknowledgments (致谢与参考)

- **Apple Sample Code**: Exploded-view and part manipulation patterns are inspired by Apple's [Manipulating Models with RealityKit](https://developer.apple.com/documentation/realitykit/manipulating-models-with-realitykit) sample. See [ThirdPartyNotices](ThirdPartyNotices/ManipulatingModelsWithRealityKit-LICENSE.txt).
- **Apple WWDC26**: Physical-space lighting and projective textures ([WWDC26 Session 279](https://developer.apple.com/videos/play/wwdc2026/279/)).
- **RealityKit API**:
  - [InputTargetComponent](https://developer.apple.com/documentation/realitykit/inputtargetcomponent)
  - [ManipulationComponent.HitTarget](https://developer.apple.com/documentation/realitykit/manipulationcomponent/hittarget)
  - [LowLevelTexture.replace(using:)](https://developer.apple.com/documentation/realitykit/lowleveltexture/replace(using:))
- **DarkString**: [visionOS 27 Projective Texture Tutorial](https://www.darkstring.com/en/articles/visionos27-tutorial-projective-texture).
- **PocketShowRoomV2**: Direct touch button architecture pattern inspired by `viewshine-weixinzhineng/PocketShowRoomV2`.
