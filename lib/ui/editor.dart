import 'dart:convert';
import 'dart:io';

import 'package:codeeditor/ui/search_panel.dart';
import 'package:codeeditor/ui/web_assets.dart';
import 'package:codeeditor/utils/file_tree.dart';
import 'package:codeeditor/utils/open_file.dart';
import 'package:codeeditor/utils/search_match.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

enum SidebarView { explorer, search }

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
  SidebarView _currentSidebarView = SidebarView.explorer;
  double _sidebarWidth = 250.0;
  String? _currentRootPath;
  double _fontSize = 14.0;
  String _fontFamily = 'Consolas';
  int _currentLine = 1;
  int _currentColumn = 1;
  int _errorCount = 0;
  String _currentLang = "text";
  bool _isEditorInitialized = false;
  late FileSystemEntity _settingsWatcher;
  List<SearchMatch> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();
  List<FileSystemEntity> _allFiles = [];
  bool _isSearching = false;

  Map<String, dynamic> _uiColors = {
    "bg": 0xFF1e1e1e,
    "sidebar": 0xFF252526,
    "tabBar": 0xFF252526,
    "tabActive": 0xFF1e1e1e,
    "tabInactive": 0xFF2d2d2d,
    "statusBar": 0xFF007acc,
  };

  @override
  void initState() {
    super.initState();
    _setupWatcher();
    _loadSavedThemes();
    _loadInitialSettings();
    _loadSession();
  }

  void _setupWatcher() {
    final file = File('${Directory.current.path}/settings.json');
    if (!file.existsSync()) return;

    file.parent.watch(events: FileSystemEvent.modify).listen((event) {
      if (event.path.endsWith('settings.json')) {
        _updateEditorConfig();
      }
    });
  }

  Future<void> _saveSession(String rootPath, List<OpenFile> openFiles, int activeIndex) async {
    try {
      final file = File('${Directory.current.path}/session.json');
      
      final sessionData = {
        'last_root_path': rootPath,
        'open_files': openFiles.map((f) => f.file.path).toList(),
        'active_index': activeIndex,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(sessionData));
    } catch (e) {
      debugPrint("Error saving the session: $e");
    }
  }

  Future<void> _loadSession() async {
    try {
      final file = File('${Directory.current.path}/session.json');
      if (await file.exists()) {
        final data = json.decode(await file.readAsString());
        final savedRoot = data['last_root_path'] as String?;
        final List<dynamic> openFiles = data['open_files'] ?? [];
        final int activeIndex = data['active_index'] ?? 0;

        if (savedRoot != null && Directory(savedRoot).existsSync()) {
          setState(() { _currentRootPath = savedRoot; });
          _refreshFolder();

          for (var path in openFiles) {
            final f = File(path);
            if (f.existsSync()) {
              await _openFile(f);
            }
          }
          
          setState(() => _activeTabIndex = activeIndex);
          _syncEditorWithTab();
        }
      }
    } catch (e) {
      debugPrint("Error loading the session: $e");
    }
  }

  Future<void> _saveSettings() async {
    final file = File('${Directory.current.path}/settings.json');
    final config = {
      "theme": _currentTheme,
      "fontFamily": _fontFamily,
      "fontSize": _fontSize
    };
    final encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(config));
    await _updateEditorConfig();
  }

  Future<void> _loadInitialSettings() async {
    final file = File('${Directory.current.path}/settings.json');
    if (await file.exists()) {
      final json = jsonDecode(await file.readAsString());
      setState(() {
        _fontSize = (json['fontSize'] as num?)?.toDouble() ?? 14.0;
        _fontFamily = json['fontFamily'] ?? 'Consolas';
        _currentTheme = json['theme'] ?? 'vs-dark';
      });
    }
    
    await _loadUiColors(_currentTheme);
    _updateEditorConfig();
  }

  Future<void> _applySavedConfig() async {
    if (!_isEditorInitialized) return;

    if (['vs-dark', 'vs', 'hc-black'].contains(_currentTheme)) {
      _webViewController?.evaluateJavascript(source: "monaco.editor.setTheme('$_currentTheme')");
    } else {
      File themeFile = File('${Directory.current.path}/themes/$_currentTheme.json');
      if (await themeFile.exists()) {
        String jsonContent = await themeFile.readAsString();
        _webViewController?.evaluateJavascript(source: "window.defineCustomTheme('$_currentTheme', $jsonContent);");
        _webViewController?.evaluateJavascript(source: "monaco.editor.setTheme('$_currentTheme')");
      }
    }

    await _updateEditorConfig(); 
  }

  Future<void> _loadUiColors(String themeName) async {
    if (['vs-dark', 'vs', 'hc-black'].contains(themeName)) {
      setState(() => _uiColors = {
            "bg": 0xFF1e1e1e,
            "sidebar": 0xFF252526,
            "tabBar": 0xFF252526,
            "tabActive": 0xFF1e1e1e,
            "tabInactive": 0xFF2d2d2d,
            "statusBar": 0xFF007acc,
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

    _saveSession(_currentRootPath!, _openFiles, _activeTabIndex);
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

  Future<void> _saveFileAtIndex(int index) async {
    if (_webViewController == null) return;

    String code;
    if (index == _activeTabIndex) {
      code = await _webViewController!.evaluateJavascript(source: "window.editor.getValue()");
    } else {
      code = await _openFiles[index].file.readAsString();
    }

    File file = _openFiles[index].file;
    await file.writeAsString(code);

    setState(() {
      _openFiles[index].isDirty = false;
    });
  }

  Future<void> _saveFile() async {
    if (_activeTabIndex != -1) {
      await _saveFileAtIndex(_activeTabIndex);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("File saved"), duration: Duration(milliseconds: 500))
        );
      }
    }
  }

  Future<void> _pickDirectory() async {
    if (_currentRootPath != null) {
      bool canProceed = await _confirmChangeProject();
      if (!canProceed) return;
    }

    String? path = await FilePicker.getDirectoryPath();
    
    if (path != null) {
      _resetProjectState();
      
      setState(() {
        _currentRootPath = path;
      });
      _refreshFolder();
    }
  }

  void _resetProjectState() {
    setState(() {
      _currentRootPath = null;
      _rootEntities = [];
      _openFiles.clear();
      _activeTabIndex = -1;
    });
    _webViewController?.evaluateJavascript(source: "window.editor.setValue('');");
  }

  Future<bool> _confirmChangeProject() async {
    final dirtyFiles = _openFiles.where((f) => f.isDirty).toList();
    
    if (dirtyFiles.isEmpty) return true;

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Switch Project"),
        content: Text("You have ${dirtyFiles.length} unsaved file(s). Do you want to save changes before closing the current project?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              for (int i = 0; i < _openFiles.length; i++) {
                if (_openFiles[i].isDirty) {
                  await _saveFileAtIndex(i);
                }
              }
              Navigator.pop(context, true);
            },
            child: const Text("Save and Continue"),
          ),
        ],
      ),
    ) ?? false;
  }

  void _refreshFolder() {
    if (_currentRootPath != null) {
      final rootDir = Directory(_currentRootPath!);

      final Set<String> ignoreList = {
        '.dart_tool', '.git', '.gradle', '.idea', '.vscode', 
        'build', 'node_modules', 'dist', 'packages', '.vcs',
      };

      final gitIgnoreFile = File(p.join(_currentRootPath!, '.gitignore'));
      if (gitIgnoreFile.existsSync()) {
        try {
          final lines = gitIgnoreFile.readAsLinesSync();
          for (var line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
            ignoreList.add(trimmed.replaceAll('/', '').replaceAll('*', ''));
          }
        } catch (e) {
          debugPrint("The .gitignore file could not be read: $e");
        }
      }

      List<FileSystemEntity> entities = rootDir.listSync();
      entities.sort((a, b) {
        bool aIsDir = a is Directory;
        bool bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      List<FileSystemEntity> allFiles = [];

      void _recursiveList(Directory dir) {
        try {
          for (var entity in dir.listSync()) {
            final name = p.basename(entity.path);
            if (entity is Directory) {
              if (!ignoreList.contains(name)) {
                _recursiveList(entity);
              }
            } else if (entity is File) {
              allFiles.add(entity);
            }
          }
        } catch (e) {
          debugPrint("Access denied to: ${dir.path}");
        }
      }

      _recursiveList(rootDir);

      setState(() {
        _rootEntities = entities;
        _allFiles = allFiles;
      });
      _saveSession(_currentRootPath!, _openFiles, _activeTabIndex);
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
    await _saveSession(_currentRootPath!, _openFiles, _activeTabIndex);
  }

  void _syncEditorWithTab() {
    if (_activeTabIndex != -1 && _webViewController != null) {
      final fileData = _openFiles[_activeTabIndex];
      String extension = p.extension(fileData.file.path).replaceAll('.', '');
      String fileName = p.basename(fileData.file.path);
      
      final payload = jsonEncode({
        "code": fileData.content, 
        "lang": extension,
        "fileName": fileName
      });

      _webViewController!.evaluateJavascript(source: "window.setEditorValue($payload)");
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
      "ui": {
        "bg": 4280151070,
        "activityBar": 4280625958,
        "sidebar": 4280625958,
        "tabBar": 4280625958,
        "tabActive": 4280151070,
        "tabInactive": 4281216557,
        "statusBar": 4278248652
      }
    };

    final File themeFile = File('$folderPath/$themeName.json');
    await themeFile.writeAsString(jsonEncode(themeTemplate));
    if (!_themes.contains(themeName)) {
      setState(() => _themes.add(themeName));
    }

    setState(() {
      _currentTheme = themeName;
    });

    await _loadUiColors(themeName);
    await _applySavedConfig();
    await _openFile(themeFile);
  }

  void _openSettings() {
    final String settingsPath = '${Directory.current.path}/settings.json';
    final File settingsFile = File(settingsPath);

    if (!settingsFile.existsSync()) {
      settingsFile.writeAsStringSync('''
  {
    "theme": "vs-dark",
    "fontFamily": "Consolas",
    "fontSize": 14
  }''');
    }

    _openFile(settingsFile); 
  }

  Future<void> _updateEditorConfig() async {
    if (_webViewController == null) return;

    final file = File('${Directory.current.path}/settings.json');
    Map<String, dynamic> settings = {};
    
    if (await file.exists()) {
      final String content = await file.readAsString();
      settings = jsonDecode(content);
    }

    settings.putIfAbsent("fontSize", () => _fontSize.toDouble());
    settings.putIfAbsent("fontFamily", () => _fontFamily);

    final String jsonString = jsonEncode(settings);
    final String jsCode = "window.setEditorOptions($jsonString);";
    
    _webViewController!.evaluateJavascript(source: jsCode);    
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

  Widget _buildStatusBar() {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Color(_uiColors["statusBar"] ?? 0xFF007acc), 
      child: Row(
        children: [
          if (_errorCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(children: [
                const Icon(Icons.error, size: 14, color: Colors.white70), 
                Text(" $_errorCount", style: const TextStyle(color: Colors.white, fontSize: 12))
              ]),
            ),
          Text(
            _activeTabIndex != -1 ? p.extension(_openFiles[_activeTabIndex].file.path).replaceAll('.', '').toUpperCase() : "TEXT",
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          const Text("UTF-8", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 15),
          Text(
            "Ln $_currentLine, Col $_currentColumn", 
            style: const TextStyle(color: Colors.white70, fontSize: 12)
          ),
        ],
      ),
    );
  }

  void _setAllFiles(List<FileSystemEntity> entities) {
    _allFiles = entities;
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }

    setState(() { _isSearching = true; _searchResults = []; });

    final lowerQuery = query.toLowerCase();
    List<SearchMatch> matches = [];

    for (var entity in _allFiles) {
      if (entity is File) {
        try {
          final stream = entity.openRead();
          int lineNumber = 0;
          
          await for (var line in stream.transform(utf8.decoder).transform(const LineSplitter())) {
            lineNumber++;
            if (line.toLowerCase().contains(lowerQuery)) {
              matches.add(SearchMatch(entity, lineNumber, line.trim()));
              if (matches.length > 500) break; 
            }
          }
        } catch (e) {
          // Ignore Bloqued files or binaries
        }
      }
    }

    setState(() {
      _searchResults = matches;
      _isSearching = false;
    });
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
                    onPressed: () => setState(() {
                      _isSidebarVisible = true;
                      _currentSidebarView = SidebarView.explorer;
                    })
                  ),
                  const SizedBox(height: 10),
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white, size: 22),
                    onPressed: () => setState(() {
                      _isSidebarVisible = true;
                      _currentSidebarView = SidebarView.search;
                    }),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.settings, color: Colors.white, size: 22),
                    color: Color(_uiColors["sidebar"]),
                    onSelected: (value) {
                      if (value == 'settings') _openSettings();
                      if (value == 'new_theme') _showCreateThemeDialog(context);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'settings', child: Text("Open Settings", style: TextStyle(color: Colors.white))),
                      const PopupMenuItem(value: 'new_theme', child: Text("Create New Theme", style: TextStyle(color: Colors.white))),
                    ],
                  )
                ],
              ),
            ),
            if (_isSidebarVisible) ...[
              Container(
                width: _sidebarWidth,
                color: Color(_uiColors["sidebar"]),
                child: _currentSidebarView == SidebarView.explorer
                    ? Column(
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
                                      icon: const Icon(Icons.folder_open, size: 16, color: Colors.white70),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: "Open Project",
                                      onPressed: _pickDirectory,
                                    ),
                                    const SizedBox(width: 8),
                                    if (_currentRootPath != null) ...[
                                      IconButton(
                                        icon: const Icon(Icons.note_add, size: 16, color: Colors.white70),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _showCreateRootItemDialog(context, isFolder: false),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.create_new_folder, size: 16, color: Colors.white70),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _showCreateRootItemDialog(context, isFolder: true),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.more_horiz, size: 16, color: Colors.white70),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _currentRootPath == null
                                ? Column(
                                    children: [
                                      ListTile(
                                        leading: Icon(Icons.folder_open, size: 18, color: Color(_uiColors["sidebarForeground"] ?? 0xFFFFFFFF)),
                                        title: Text("Open Folder", style: TextStyle(fontSize: 12, color: Color(_uiColors["sidebarForeground"] ?? 0xFFFFFFFF))),
                                        onTap: _pickDirectory,
                                        dense: true,
                                      ),
                                      ListTile(
                                        leading: Icon(Icons.insert_drive_file, size: 18, color: Color(_uiColors["sidebarForeground"] ?? 0xFFFFFFFF)),
                                        title: Text("Open File", style: TextStyle(fontSize: 12, color: Color(_uiColors["sidebarForeground"] ?? 0xFFFFFFFF))),
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
                                : ListView(
                                    children: _rootEntities.map((e) => FileTreeItem(
                                      entity: e,
                                      onFileTap: _openFile,
                                      onAction: _refreshFolder,
                                      uiColors: _uiColors,
                                    )).toList(),
                                  ),
                          ),
                        ],
                      )
                      :SearchPanel(
                      uiColors: _uiColors,
                      results: _searchResults,
                      onSearch: _performSearch,
                      isSearching: _isSearching,
                      onFileTap: (file, lineNumber) async {
                        await _openFile(file);
                        _webViewController?.evaluateJavascript(
                          source: "window.editor.revealLine($lineNumber); window.editor.setPosition({lineNumber: $lineNumber, column: 1});"
                        );
                      },
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

                        _webViewController?.addJavaScriptHandler(
                          handlerName: 'onSettingsChanged',
                          callback: (args) {
                            final Map<String, dynamic> newConfig = args[0];
                            
                            setState(() {
                              _currentTheme = newConfig['theme'] ?? _currentTheme;
                              _fontSize = (newConfig['fontSize'] as num?)?.toDouble() ?? _fontSize;
                              _fontFamily = newConfig['fontFamily'] ?? _fontFamily;
                            });

                            _webViewController?.evaluateJavascript(source: '''
                              monaco.editor.setTheme('${_currentTheme}');
                              monaco.editor.updateOptions({
                                fontSize: ${_fontSize},
                                fontFamily: '${_fontFamily}'
                              });
                            ''');

                            _saveSettings();
                          }
                        );

                        _webViewController?.addJavaScriptHandler(
                          handlerName: 'onEditorReady', 
                          callback: (args) {
                            _isEditorInitialized = true;            
                            _applySavedConfig();
                          }
                        );
                        
                        _webViewController?.addJavaScriptHandler(handlerName: 'onContentChanged', callback: (args) {
                          if (_activeTabIndex != -1 && !_openFiles[_activeTabIndex].isDirty) {
                            setState(() => _openFiles[_activeTabIndex].isDirty = true);
                          }
                        });       
                        
                        _webViewController?.addJavaScriptHandler(handlerName: 'onSaveCommand', callback: (args) => _saveFile());       
                        
                        _webViewController?.addJavaScriptHandler(handlerName: 'onCursorChanged', callback: (args) {
                          setState(() {
                            _currentLine = args[0]['line'];
                            _currentColumn = args[0]['column'];
                          });
                        });

                        _webViewController?.addJavaScriptHandler(handlerName: 'onMarkersChanged', callback: (args) {
                          setState(() => _errorCount = args[0]);
                        });

                        _registerAllThemesToWebView();
                        _syncEditorWithTab();
                      }
                    ),
                  ),
                  _buildStatusBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
