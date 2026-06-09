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

## Configuration Management
Minimal Editor uses a dynamic, file-based configuration system. Instead of navigating through complex, nested menu layers, all editor behaviors and visual preferences are managed via a `settings.json` file located in the root of your application folder.

### How it Works
The application establishes a direct bridge between your `settings.json` file and the **Monaco Editor** engine.

1. **Dynamic Sync:** Any changes made to the `settings.json` file are automatically detected and reflected in the editor instance in real-time.
2. **Standardized Schema:** Since we use the industry-standard Monaco Editor engine, you can apply any configuration supported by the [Monaco Editor API.](https://microsoft.github.io/monaco-editor/typedoc/index.html)
3. **No Bloat:** By keeping settings as a simple JSON file, we avoid the overhead of heavy configuration databases or background management services.

#### Customizing your Experience
To customize the editor, simply modify the `settings.json` file. Here is an example of the available flexibility:

```json
{
  "theme": "vs-dark",
  "fontSize": 13,
  "fontFamily": "CaskaydiaCove Nerd Font",
  "fontLigatures": "liga",
  "fontVariations": true,
  "cursorBlinking": "solid",
  "wordWrap": "on",
  "renderLineHighlight": "line",
  "renderWhitespace": "none",
  "glyphMargin": true,
  "overviewRulerBorder": false,
  "hideCursorInOverviewRuler": true,
  "fastScrollSensitivity": 10,
  "scrollbar": {
    "vertical": "hidden",
    "horizontal": "hidden"
  },
  "guides": {
    "indentation": true,
    "bracketPairs": true
  },
  "bracketPairColorization": {
    "enabled": true,
    "independentColorPoolPerBracketType": true
  },
  "autoClosingBrackets": "always",
  "colorDecorators": true,
  "multiCursorModifier": "ctrlCmd",
  "showFoldingControls": "never",
  "selectionHighlight": true,
  "quickSuggestions": {
    "other": true
  },
  "suggestOnTriggerCharacters": false,
  "tabCompletion": "on",
  "minimap": {
    "enabled": true,
    "maxColumn": 50
  },
  "stickyScroll": {
    "scrollWithEditor": true
  },
  "largeFileOptimizations": true,
  "unicodeHighlight": {
    "nonBasicASCII": false
  },
  "tabSize": 4,
  "insertSpaces": true,
  "detectIndentation": false
}
```
> Simply save the file, and Minimal Editor will instantly apply your changes.

> [!WARNING]
> Ensure that your `settings.json` file is properly formatted. If the JSON structure is invalid, the configuration changes will not be applied.

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
