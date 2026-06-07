# Minimal Editor

A lightwight, high-performance code editor built deom scratch with flutter

<img width="1918" height="1052" alt="Captura de pantalla 2026-06-07 155939" src="https://github.com/user-attachments/assets/afcbfbae-0cb8-4f4d-a29b-201ba80707bd" />

**Status: 🚧 Early Development / Pre-alpha**

An independent project focused on providing a clean, distraction-free enviroment for developers who prioritize system efficiency.

## Philosophy: Why Minimal Editor?

Unlike resource-heavy IDEs that bundle excessive background processes, Minimal Editor is built to be lean.

* **Low Resource Footprint:** Designed to run with minimal CPU and RAM usage, making it ideal for older hardware or background task editing.
* **Not a VS Code Derivative:** This is not a fork or a stripped-down version of VS Code. It is an independent application built with Flutter.
* **Architecture:** The only shared component with VS Code is Monaco Editor, which we use exclusively as the core engine for syntax highlighting and code intelligence. The entire shell, file system management, and UI logic are custom-built to keep the application lightweight and responsive.

## Performance Benchmarking
I believe a code editor should be a resource-efficient tool. Unlike other editors such as Visual Studio Code, which often consumes large amounts of RAM and CPU even when idle, Minimal Editor is designed to be virtually invisible in terms of system performance.

The following data was captured while both editors were processing the same source file containing **10,000 lines of code**:

| Feature | Minimal Editor | VS Code |
| :--- | :---: | :---: |
| **RAM Usage (10k lines)** | **212.0 MB** | 911.6 MB |
| **Background Processes** | 1 | 9+ |
| **Architecture** | Native Flutter | Electron |

<img width="1914" height="1054" alt="Captura de pantalla 2026-06-06 055847" src="https://github.com/user-attachments/assets/8feeadfc-a202-4659-90fa-fd7e3f71ae69" />

> [!NOTE]
> *The comparison above demonstrates the memory footprint when opening the same large-scale project file. Minimal Editor maintains a steady, lightweight state, while VS Code's architecture spawns multiple helper processes to manage its environment.*

## Core Features

* **File system Explorer:** Native tree-view for navigating projects with fast, low-latency file operations.
* **Efficient Editing:** Powered by Monaco Editor, providing industry-standard syntax highlighting without the bloat of a full IDE.
* **Dynamic Theming:** Seamless UI integration that adapts to your custom color schemes.
* **Native Performance:** Built with Flutter, ensuring a snappy, fluid interface regardless of the project size.

## Tech Stack

* **Frontend:** Flutter (Desktop-optimized).
* **Editor Engine:** Monaco Editor (via `flutter_inappwebview`).
* **File I/O:** Native `dart:io`.
* **Resource Optimization:** No Electron overhead; custom-managed JS-Dart bridge.

## Roadmap
[ ] Implement global search and replace.
[ ] Lightweight plugin architecture.
[ ] Performance-focused configuration management.
[ ] VCS Integration: Active integration of the [Portable-VCS](https://github.com/Nooch98/Portable-VCS) engine.

## Getting Started
### Prerequisites
* Flutter SDK installed.

### Setup

1. Clone the repository:
```bash
git clone https://github.com/Nooch98/Minimal-Editor
```

2. Navigate to the project directory:
```bash
cd Minimal-Editor
```

3. Install dependecies:
```bash
flutter pub get
```

4. Run the application:
```bash
flutter run
```

## Contributing
As this project aims to be a lightweight alternative for the development community, contributions, feedback, and bug reports are highly encouraged. Please feel free to open an **Issue** or submit a **Pull Request**.
