# Minimal Editor

A lightwight, high-performance code editor built deom scratch with flutter

<img width="1912" height="1032" alt="Captura de pantalla 2026-06-14 052601" src="https://github.com/user-attachments/assets/a8c2c10b-b9f0-4256-9841-e25ae64d7913" />

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
| **RAM Usage (10k lines)** | **90.4MB** | 910.6 MB |
| **Background Processes** | 1 | 9+ |
| **Architecture** | Native Flutter | Electron |

<img width="1912" height="1032" alt="Captura de pantalla 2026-06-14 053210" src="https://github.com/user-attachments/assets/df24e957-5e2c-4a4f-a50a-2cfef251005c" />

> [!NOTE]
> > *The comparison above demonstrates the actual memory footprint. Minimal Editor achieves an incredible ~90MB state by implementing an asynchronous Dart-JS bridge that strips away telemetry, heavy multi-process indexers, and the massive bloat associated with standard Electron wrappers.*

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

* **File system Explorer:** Native tree-view for navigating projects with fast, low-latency file operations and streamlined folder management.
* **Integrated Version Control ([VCS](https://github.com/Nooch98/Portable-VCS)):** Native workspace integration featuring a custom, encrypted local version control dashboard alongside an optimized Git Remote panel to seamlessly pull and push repository changes.
* **Exclusive Internal Clipboard:** A dedicated history panel that intercepts copy actions strictly within Monaco Editor. It handles up to 10 historical records in memory without OS clipboard polling overhead, offering undo (`Ctrl+Z`) support on paste.
* **Reactive Breadcrumbs:** Instant context visualization with a dynamic breadcrumb hierarchy bar placed right below tabs.
* **Context-Aware Status Bar:** Automatic repository recognition that updates the footer UI to track active Git branches in real time.
* **Efficient Editing:** Powered by Monaco Editor, providing industry-standard syntax highlighting without the bloat of a full IDE.
* **Dynamic Theming:** Seamless UI integration that adapts to your custom color schemes.

## 🤖 AI Chat Agent (Experimental)

Minimal Editor now includes an integrated AI Chat Agent designed to act as your autonomous coding collaborator. By leveraging a local-first, modular architecture, the agent assists with deep code navigation, file analysis, and project exploration directly within your workspace.

**Status: 🟢 Experimental (Active Development)**

### 🧠 Core Capabilities
The agent operates via a structured **Thought-Action-Observation** loop, allowing it to reason about your project requirements before executing changes.

* **Autonomous Navigation:** Uses `[LS]` and `[READ]` to build a contextual map of your codebase.
* **Safety-First Execution:** Implements a controlled `[WRITE]` protocol, ensuring the agent remains a tool *under your supervision*.
* **Provider-Agnostic:** Built to be model-agnostic. Use local inference engines for total privacy or cloud APIs for advanced reasoning.

### ⚙️ Compatibility & Providers
Configure your preferred engine via the **Settings Panel**:

| Model Type | Recommended Providers |
| :--- | :--- |
| **Local (Private)** | **Ollama**, **LM Studio** |
| **Cloud (High-Reasoning)** | **Google Gemini API**, **Anthropic Claude**, **OpenAI** |


https://github.com/user-attachments/assets/c493f731-ce99-4ec3-8d86-40ee8a8a42bf


### 🛡️ Safety & Guardrails
As an autonomous experimental feature, i prioritize user control:
* **Human-in-the-Loop:** The agent defaults to `[ASK]` mode for critical changes, ensuring you approve major refactors.
* **Sandboxed Reasoning:** The agent's scope is strictly bounded to the project root to ensure system security.

> [!NOTE]
> **Performance Optimization:** While the architecture supports a wide range of models, I recommend models with high instruction-following capabilities. Initial stabilization and testing have been performed primarily using **LM Studio** and **Gemma 4 (e4b)**.

> [!WARNING]
> This is an experimental feature. Autonomous agents may occasionally produce unexpected results when navigating highly complex file structures. I recommend using this tool in projects under version control (Git) to easily revert any unintended suggestions.

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
