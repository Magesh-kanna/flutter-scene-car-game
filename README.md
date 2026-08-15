# 🏎️ Turbo Car Runner 3D

A 3D endless highway runner game built with **Flutter**, **Flutter Scene (`flutter_scene: ^0.16.0`)**, and the **Impeller 3D GPU Engine**.

Inspired by classic lane runners (like Subway Surfers) with 3D traffic avoidance, gold nut collectibles, jump mechanics, dynamic camera perspective, and responsive controls across mobile, tablet, and desktop.

---

## ✨ Features

- **🎮 3D Graphics Powered by Impeller & Flutter Scene**: Real-time 3D rendering with GLB 3D models, dynamic lighting, studio environment reflection maps, and directional shadows.
- **🛣️ 3-Lane Highway Runner**: Dodge oncoming traffic (trucks, police cars, taxis, delivery vans) and road obstacles (traffic cones, wooden crates).
- **🚀 Jump & Quick Drop Mechanics**: Jump over cones and crates, or quick-drop to ground level.
- **📱 Fully Responsive Design**:
  - **Dynamic 3D Camera FOV**: Adapts field-of-view and camera anchor in real-time for ultra-wide, landscape, tablet, and portrait mobile screens.
  - **Adaptive HUD**: Scaled stats pill showing distance traveled, gold nut collectibles, score, and best score.
  - **Ergonomic Dual Controls**:
    - **Mobile/Touch**: On-screen thumb controls (Left/Right, Jump/Drop) + swipe gestures anywhere on screen.
    - **Desktop/Keyboard**: Arrow keys, A/D, SPACE to jump, S/Down arrow to quick drop, P/ESC to pause.
  - **Adaptive Layouts**: Responsive Start Menu, Paused Modal, and Game Over score summary supporting portrait and short landscape modes.
- **⚡ High-Performance Object Pooling**: Zero runtime garbage collection spikes using pre-warmed entity slot recycling and 60 FPS synchronous ticker loops.

---

## 🕹️ Controls

| Action | Desktop / Keyboard | Mobile / Touch Screen |
| :--- | :--- | :--- |
| **Switch Left** | `A` or `Left Arrow` | Tap ◀ button or **Swipe Left** |
| **Switch Right** | `D` or `Right Arrow` | Tap ▶ button or **Swipe Right** |
| **Jump** | `SPACE` or `Up Arrow` / `W` | Tap ▲ button or **Swipe Up** |
| **Quick Drop** | `S` or `Down Arrow` | Tap ▼ button or **Swipe Down** |
| **Pause / Resume** | `P` or `ESC` | Tap Pause (⏸) / Play (▶) button |

---

## 🛠️ Getting Started

### Prerequisites

- Flutter SDK (with Impeller support, Flutter >= 3.24.0)
- Compatible platform (macOS, iOS, Android, Linux, Windows)

### Installation & Run

1. Clone this repository:
   ```bash
   git clone https://github.com/Magesh-kanna/flutter-scene-car-game.git
   cd flutter-scene-car-game
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run on your target device (Impeller enabled by default):
   ```bash
   # macOS Desktop
   fvm flutter run -d macos --enable-impeller --enable-flutter-gpu   

   # iOS Simulator / Device
   fvm flutter run -d ios --enable-impeller --enable-flutter-gpu

   # Android Device
   fvm flutter run -d android --enable-impeller --enable-flutter-gpu
   ```

---

## 📦 3D Assets & Credits

- 3D Models by [Kenney.nl](https://kenney.nl/) (Car Kit & City Kit Roads) - CC0 1.0 Universal.

