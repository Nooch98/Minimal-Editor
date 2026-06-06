import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'web_assets.dart';

class OpenFile {
  final File file;
  final String content;
  bool isDirty;
  OpenFile({required this.file, required this.content, this.isDirty = false});
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: EditorScaffold()));
}

class EditorScaffold extends StatefulWidget {
  const EditorScaffold({super.key});
  @override
  State<EditorScaffold> createState() => _EditorScaffoldState();
}

class _EditorScaffoldState extends State<EditorScaffold> {
  InAppWebViewController? _webViewController;
  List<FileSystemEntity> _rootEntities = [];
  List<OpenFile> _openFiles = [];
  int _activeTabIndex = -1;
  final List<String> _themes = ['vs-dark', 'vs', 'hc-black'];
  String _currentTheme = 'vs-dark';
  bool _isSidebarVisible = true;
  double _sidebarWidth = 250.0;
  String? _currentRootPath;

  // Default UI color map
  Map<String, dynamic> _uiColors = {
    "bg": 0xFF1e1e1e,
    "sidebar": 0xFF252526,
    "tabBar": 0xFF252526,
    "tabActive": 0xFF1e1e1e,
    "tabInactive": 0xFF2d2d2d,
  };

  @override
  void initState() {
    super.initState();
    _loadSavedThemes();
  }

  Future<void> _loadUiColors(String themeName) async {
    if (['vs-dark', 'vs', 'hc-black'].contains(themeName)) {
      setState(() => _uiColors = {
            "bg": 0xFF1e1e1e,
            "sidebar": 0xFF252526,
            "tabBar": 0xFF252526,
            "tabActive": 0xFF1e1e1e,
            "tabInactive": 0xFF2d2d2d,
          });
      return;
    }
    final file = File('${Directory.current.path}/themes/$themeName.json');
    if (await file.exists()) {
      final json = jsonDecode(await file.readAsString());
      if (json.containsKey("ui")) {
        setState(() => _uiColors = Map<String, dynamic>.from(json["ui"]));
      }
    }
  }

  void _closeFile(int index) {
    setState(() {
      _openFiles.removeAt(index);
      if (_activeTabIndex >= _openFiles.length) {
        _activeTabIndex = _openFiles.length - 1;
      }
      if (_openFiles.isEmpty) {
        _activeTabIndex = -1;
        _webViewController?.evaluateJavascript(source: "window.setEditorValue({code: '', lang: 'text'})");
      } else {
        _syncEditorWithTab();
      }
    });
  }

  Future<void> _loadSavedThemes() async {
    final String folderPath = '${Directory.current.path}/themes';
    final directory = Directory(folderPath);
    if (await directory.exists()) {
      final List<FileSystemEntity> entities = await directory.list().toList();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          String themeName = p.basenameWithoutExtension(entity.path);
          if (!_themes.contains(themeName)) {
            setState(() => _themes.add(themeName));
          }
        }
      }
    }
  }

  Future<void> _registerAllThemesToWebView() async {
    final String folderPath = '${Directory.current.path}/themes';
    final dir = Directory(folderPath);
    if (await dir.exists()) {
      await for (var entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          String themeName = p.basenameWithoutExtension(entity.path);
          String jsonContent = await entity.readAsString();
          _webViewController?.evaluateJavascript(source: "window.defineCustomTheme('$themeName', $jsonContent);");
        }
      }
    }
  }

  Future<void> _saveFile() async {
    if (_activeTabIndex != -1 && _webViewController != null) {
      String code = await _webViewController!.evaluateJavascript(source: "window.editor.getValue()");
      File file = _openFiles[_activeTabIndex].file;
      await file.writeAsString(code);

      setState(() {
        _openFiles[_activeTabIndex].isDirty = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("File saved"), duration: Duration(milliseconds: 500)));
      }
    }
  }

  Future<void> _pickDirectory() async {
    String? path = await FilePicker.getDirectoryPath();
    if (path != null) {
      setState(() {
        _currentRootPath = path;
      });
      _refreshFolder();
    }
  }

  void _refreshFolder() {
    if (_currentRootPath != null) {
      List<FileSystemEntity> entities = Directory(_currentRootPath!).listSync();
      entities.sort((a, b) {
        bool aIsDir = a is Directory;
        bool bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      setState(() {
        _rootEntities = entities;
      });
    }
  }

  Future<void> _openFile(File file) async {
    int existingIndex = _openFiles.indexWhere((f) => f.file.path == file.path);
    if (existingIndex != -1) {
      setState(() => _activeTabIndex = existingIndex);
    } else {
      String content = await file.readAsString();
      setState(() {
        _openFiles.add(OpenFile(file: file, content: content, isDirty: false));
        _activeTabIndex = _openFiles.length - 1;
      });
    }
    _syncEditorWithTab();
  }

  void _syncEditorWithTab() {
    if (_activeTabIndex != -1 && _webViewController != null) {
      final fileData = _openFiles[_activeTabIndex];
      String extension = p.extension(fileData.file.path).replaceAll('.', '');
      final payload = jsonEncode({"code": fileData.content, "lang": extension});

      _webViewController!.evaluateJavascript(source: "window.setEditorValue($payload)");
      _webViewController!.evaluateJavascript(source: "monaco.editor.setTheme('$_currentTheme')");
    }
  }

  Future<void> _createThemeFile(String themeName) async {
    final String folderPath = '${Directory.current.path}/themes';
    await Directory(folderPath).create(recursive: true);

    final Map<String, dynamic> themeTemplate = {
      "base": "vs-dark",
      "inherit": true,
      "rules": [],
      "colors": {"editor.background": "#1e1e1e"},
      "ui": _uiColors 
    };

    final File themeFile = File('$folderPath/$themeName.json');
    await themeFile.writeAsString(jsonEncode(themeTemplate));

    if (!_themes.contains(themeName)) {
      setState(() => _themes.add(themeName));
    }

    _webViewController?.evaluateJavascript(source: "window.defineCustomTheme('$themeName', ${jsonEncode(themeTemplate)});");
    await _openFile(themeFile);
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
          canvasColor: Color(_uiColors["sidebar"]),
          textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color(_uiColors["sidebar"]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Editor Settings", 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)
              ),
              const SizedBox(height: 10),
              DropdownButton<String>(
                value: _currentTheme,
                isExpanded: true,
                dropdownColor: Color(_uiColors["sidebar"]),
                style: const TextStyle(color: Colors.white),
                items: _themes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (val) async {
                  if (val == null) return;
                  setState(() => _currentTheme = val);
                  await _loadUiColors(val);
                  
                  if (['vs-dark', 'vs', 'hc-black'].contains(val)) {
                    _webViewController?.evaluateJavascript(source: "monaco.editor.setTheme('$val')");
                  } else {
                    File themeFile = File('${Directory.current.path}/themes/$val.json');
                    if (await themeFile.exists()) {
                      String jsonContent = await themeFile.readAsString();
                      _webViewController?.evaluateJavascript(source: "window.defineCustomTheme('$val', $jsonContent);");
                    }
                  }
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.add), 
                label: const Text("Create New Theme"), 
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCreateThemeDialog(context);
                }
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateThemeDialog(BuildContext context) {
    TextEditingController nameCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: Color(_uiColors["bg"]),
          textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white),
        ),
        child: AlertDialog(
          backgroundColor: Color(_uiColors["sidebar"]),
          title: const Text("New Theme", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Theme Name",
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text("Cancel", style: TextStyle(color: Colors.white70))
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty) {
                  _createThemeFile(nameCtrl.text);
                  Navigator.pop(ctx);
                }
              }, 
              child: const Text("Create and Load"),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateRootItemDialog(BuildContext context, {required bool isFolder}) {
    TextEditingController nameCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: Color(_uiColors["bg"]),
          textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white),
        ),
        child: AlertDialog(
          backgroundColor: Color(_uiColors["sidebar"]),
          title: Text(isFolder ? "New Folder" : "New File", style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: isFolder ? "Folder Name" : "File Name",
              hintStyle: const TextStyle(color: Colors.white54),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white30),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty && _currentRootPath != null) {
                  try {
                    final path = p.join(_currentRootPath!, nameCtrl.text);
                    if (isFolder) {
                      await Directory(path).create();
                    } else {
                      await File(path).create();
                    }
                    _refreshFolder();
                    Navigator.pop(ctx);
                  } catch (e) {
                    debugPrint("Error creating ${isFolder ? 'folder' : 'file'}: $e");
                  }
                }
              },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) && event.logicalKey == LogicalKeyboardKey.keyS) {
          _saveFile();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Color(_uiColors["bg"]),
        body: Row(
          children: [
            Container(
              width: 48,
              color: Color(_uiColors["activityBar"] ?? 0xFF333333), 
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  IconButton(
                    icon: const Icon(Icons.file_copy, color: Colors.white, size: 22), 
                    onPressed: () => setState(() => _isSidebarVisible = !_isSidebarVisible)
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white, size: 22), 
                    onPressed: _openSettings
                  ),
                ],
              ),
            ),
            if (_isSidebarVisible) ...[
              Container(
                width: _sidebarWidth,
                color: Color(_uiColors["sidebar"]),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("EXPLORER", style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.note_add, size: 16, color: Colors.white70),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  if (_currentRootPath != null) {
                                    _showCreateRootItemDialog(context, isFolder: false);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.create_new_folder, size: 16, color: Colors.white70),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  if (_currentRootPath != null) {
                                    _showCreateRootItemDialog(context, isFolder: true);
                                  }
                                },
                              ),
                              const Icon(Icons.more_horiz, size: 16, color: Colors.white70),
                            ],
                          )
                        ],
                      ),
                    ),
                    if (_rootEntities.isEmpty)
                      Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.folder_open, size: 18),
                            title: const Text("Open Folder", style: TextStyle(fontSize: 12)),
                            onTap: _pickDirectory,
                            dense: true,
                          ),
                          ListTile(
                            leading: const Icon(Icons.insert_drive_file, size: 18),
                            title: const Text("Open File", style: TextStyle(fontSize: 12)),
                            onTap: () async {
                              final result = await FilePicker.pickFiles();
                              if (result != null && result.files.single.path != null) {
                                _openFile(File(result.files.single.path!));
                              }
                            },
                            dense: true,
                          )
                        ],
                      )
                    else
                      Expanded(
                        child: ListView(
                          children: _rootEntities.map((e) => FileTreeItem(
                            entity: e,
                            onFileTap: _openFile,
                            onAction: _refreshFolder,
                            uiColors: _uiColors,
                          )).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) => setState(() => _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(150.0, 500.0)),
                  child: Container(width: 1, color: Colors.black),
                ),
              ),
            ],
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 35,
                    color: Color(_uiColors["tabBar"]),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _openFiles.length,
                      itemBuilder: (context, index) {
                        bool isActive = _activeTabIndex == index;
                        return InkWell(
                          onTap: () {
                            setState(() => _activeTabIndex = index);
                            _syncEditorWithTab();
                          },
                          child: Container(
                            padding: const EdgeInsets.only(left: 16, right: 8),
                            decoration: BoxDecoration(color: Color(isActive ? _uiColors["tabActive"] : _uiColors["tabInactive"]), border: const Border(right: BorderSide(color: Colors.black, width: 1))),
                            alignment: Alignment.center,
                            child: Row(
                              children: [
                                Text(p.basename(_openFiles[index].file.path), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(width: 8),
                                if (_openFiles[index].isDirty) const Icon(Icons.circle, color: Colors.yellow, size: 8),
                                IconButton(icon: const Icon(Icons.close, size: 14, color: Colors.white70), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _closeFile(index)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: InAppWebView(
                      initialData: InAppWebViewInitialData(data: WebAssets.htmlContent),
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                        _webViewController?.addJavaScriptHandler(handlerName: 'onContentChanged', callback: (args) {
                          if (_activeTabIndex != -1 && !_openFiles[_activeTabIndex].isDirty) setState(() => _openFiles[_activeTabIndex].isDirty = true);
                        });
                        _webViewController?.addJavaScriptHandler(handlerName: 'onSaveCommand', callback: (args) => _saveFile());
                        _registerAllThemesToWebView();
                        _syncEditorWithTab();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FileTreeItem extends StatelessWidget {
  final FileSystemEntity entity;
  final Function(File) onFileTap;
  final VoidCallback onAction;
  final Map<String, dynamic> uiColors;

  const FileTreeItem({
    super.key,
    required this.entity,
    required this.onFileTap,
    required this.onAction,
    required this.uiColors,
  });

  Color _getColorForExtension(String ext) {
    int hash = ext.hashCode;
    return Color(0xFF000000 | (hash & 0xFFFFFF)).withOpacity(0.8);
  }

  IconData _getIconForExtension(String ext) {
    switch (ext) {
      case 'dart': return Icons.code;
      case 'json': return Icons.data_object;
      case 'js': case 'ts': return Icons.javascript;
      case 'html': return Icons.html;
      case 'css': return Icons.css;
      case 'png': case 'jpg': case 'jpeg': case 'svg': return Icons.image;
      case 'md': return Icons.description;
      case 'yaml': case 'yml': case 'toml': return Icons.settings;
      case 'txt': case 'log': return Icons.text_snippet;
      case 'exe': case 'bat': case 'sh': return Icons.terminal;
      default: return Icons.insert_drive_file;
    }
  }

  Widget _buildPopupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      color: Color(uiColors["sidebar"]),
      icon: const Icon(Icons.more_vert, size: 16, color: Colors.white54),
      onSelected: (value) async {
        if (value == "delete") {
          await entity.delete(recursive: true);
          onAction();
        } else {
          _showNameDialog(context, value == "new_folder");
        }
      },
      itemBuilder: (context) => [
        if (entity is Directory) ...[
          const PopupMenuItem(value: "new_file", child: Text("New File", style: TextStyle(color: Colors.white))),
          const PopupMenuItem(value: "new_folder", child: Text("New Folder", style: TextStyle(color: Colors.white))),
        ],
        const PopupMenuItem(value: "delete", child: Text("Delete", style: TextStyle(color: Colors.red))),
      ],
    );
  }

  void _showNameDialog(BuildContext context, bool isFolder) {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: Color(uiColors["bg"]),
          textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white),
        ),
        child: AlertDialog(
          backgroundColor: Color(uiColors["sidebar"]),
          title: Text(isFolder ? "New Folder" : "New File", style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                String name = controller.text;
                if (name.isNotEmpty) {
                  String parentPath = entity is Directory ? entity.path : p.dirname(entity.path);
                  String newPath = p.join(parentPath, name);
                  isFolder ? await Directory(newPath).create() : await File(newPath).create();
                  onAction();
                  Navigator.pop(ctx);
                }
              },
              child: const Text("Create"),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (entity is File) {
      String ext = p.extension(entity.path).toLowerCase().replaceAll('.', '');
      return ListTile(
        visualDensity: VisualDensity.compact,
        leading: Icon(_getIconForExtension(ext), size: 14, color: _getColorForExtension(ext)),
        title: Text(p.basename(entity.path), style: const TextStyle(fontSize: 12, color: Colors.white70)),
        trailing: _buildPopupMenu(context),
        onTap: () => onFileTap(entity as File),
        dense: true,
      );
    } else {
      final dir = entity as Directory;
      List<FileSystemEntity> children = [];
      try {
        children = dir.listSync().toList();
        children.sort((a, b) {
          bool aIsDir = a is Directory;
          bool bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
        });
      } catch (e) {
        debugPrint("Could not list: ${dir.path}");
      }

      return ExpansionTile(
        visualDensity: VisualDensity.compact,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: const Icon(Icons.folder, size: 14, color: Colors.amber),
        title: Text(p.basename(dir.path), style: const TextStyle(fontSize: 12, color: Colors.white)),
        trailing: _buildPopupMenu(context),
        children: children.map((e) => FileTreeItem(
          entity: e,
          onFileTap: onFileTap,
          onAction: onAction,
          uiColors: uiColors,
        )).toList(),
      );
    }
  }
}
