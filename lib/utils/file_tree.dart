import 'dart:io';
import 'package:codeeditor/utils/open_file.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class FileTreeItem extends StatefulWidget {
  final FileSystemEntity entity;
  final Function(File) onFileTap;
  final VoidCallback onAction;
  final Map<String, dynamic> uiColors;
  final int depth;
  final List<OpenFile> openFiles;

  const FileTreeItem({
    super.key,
    required this.entity,
    required this.onFileTap,
    required this.onAction,
    required this.uiColors,
    required this.openFiles,
    this.depth = 0,
  });

  @override
  State<FileTreeItem> createState() => _FileTreeItemState();
}

class _FileTreeItemState extends State<FileTreeItem> {
  bool _isExpanded = false;
  bool _isLoading = false;
  List<FileSystemEntity>? _children;

  @override
  void didUpdateWidget(covariant FileTreeItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openFiles != oldWidget.openFiles) {
      setState(() {}); 
    }
  }
  

  void _showNameDialog(bool isFolder) {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        final Color sidebarBg = Color(widget.uiColors["sidebar"] ?? 0xFF252526);
        final Color textThemeColor = sidebarBg.computeLuminance() > 0.5 ? Colors.black : Colors.white;

        return Theme(
          data: Theme.of(context).copyWith(
            dialogBackgroundColor: Color(widget.uiColors["bg"] ?? 0xFF1E1E1E),
            textTheme: Theme.of(context).textTheme.apply(bodyColor: textThemeColor),
          ),
          child: AlertDialog(
            backgroundColor: sidebarBg,
            title: Text(
              isFolder ? "New Folder" : "New File", 
              style: TextStyle(color: textThemeColor, fontSize: 16),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: textThemeColor, fontSize: 14),
              decoration: InputDecoration(
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: textThemeColor.withOpacity(0.3)),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  controller.dispose();
                  Navigator.pop(ctx);
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  String name = controller.text.trim();
                  if (name.isNotEmpty) {
                    String parentPath = widget.entity is Directory 
                        ? widget.entity.path 
                        : p.dirname(widget.entity.path);
                    String newPath = p.join(parentPath, name);
                    try {
                      isFolder ? await Directory(newPath).create() : await File(newPath).create();
                      widget.onAction();
                      if (_isExpanded) _loadChildren();
                    } catch (e) {
                      debugPrint("Error creating element: $e");
                    }
                    controller.dispose();
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
                child: const Text("Create"),
              )
            ],
          ),
        );
      },
    );
  }

  void _showContextMenu(Offset position) async {
    final Color sidebarBg = Color(widget.uiColors["sidebar"] ?? 0xFF252526);
    final Color itemTextColor = sidebarBg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: sidebarBg,
      elevation: 4,
      items: [
        if (widget.entity is Directory) ...[
          PopupMenuItem(value: "new_file", child: Text("New File", style: TextStyle(color: itemTextColor, fontSize: 13))),
          PopupMenuItem(value: "new_folder", child: Text("New Folder", style: TextStyle(color: itemTextColor, fontSize: 13))),
        ],
        const PopupMenuItem(value: "delete", child: Text("Delete", style: TextStyle(color: Colors.redAccent, fontSize: 13))),
      ],
    );

    if (!mounted || result == null) return;

    if (result == "delete") {
      try {
        await widget.entity.delete(recursive: true);
        widget.onAction();
      } catch (e) {
        debugPrint("Error deleting element: $e");
      }
    } else if (result == "new_file") {
      _showNameDialog(false);
    } else if (result == "new_folder") {
      _showNameDialog(true);
    }
  }

  Future<void> _loadChildren() async {
    if (widget.entity is! Directory) return;
    
    setState(() {
      _isLoading = true;
    });

    final List<FileSystemEntity> loadedChildren = [];
    final Set<String> ignoreList = {
      '.dart_tool', '.git', '.gradle', '.idea', '.vscode', 
      'build', 'node_modules', 'dist', 'packages', '.vcs'
    };

    try {
      final dir = widget.entity as Directory;
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (!ignoreList.contains(p.basename(entity.path))) {
          loadedChildren.add(entity);
        }
      }

      loadedChildren.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      if (mounted) {
        setState(() {
          _children = loadedChildren;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error listing directory: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded && _children == null) {
      _loadChildren();
    }
  }

  Color _getColorForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart': return Colors.cyan;
      case 'json': return Colors.orange;
      case 'js': case 'ts': return Colors.amber;
      case 'html': return Colors.deepOrange;
      case 'css': return Colors.blue;
      case 'md': return Colors.green;
      default: return const Color(0xFF90A4AE);
    }
  }

  IconData _getIconForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart': return Icons.code;
      case 'json': return Icons.data_object;
      case 'js': case 'ts': return Icons.javascript;
      case 'html': return Icons.html;
      case 'css': return Icons.css;
      case 'md': return Icons.description_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFile = widget.entity is File;
    final name = p.basename(widget.entity.path);
    final openFileEntry = widget.openFiles.firstWhere(
      (f) => f.file.path == widget.entity.path,
      orElse: () => OpenFile(file: File(''), content: ''),
    );
    final bool isDirty = openFileEntry.file.path.isNotEmpty && openFileEntry.isDirty;

    Color themeForegroundColor;
    if (widget.uiColors["sidebarForeground"] != null) {
      themeForegroundColor = Color(widget.uiColors["sidebarForeground"]);
    } else {
      final Color sidebarBg = Color(widget.uiColors["sidebar"] ?? 0xFF252526);
      themeForegroundColor = sidebarBg.computeLuminance() > 0.5 ? const Color(0xFF1A1A1A) : const Color(0xFFE0E0E0);
    }

    final Color textColor = themeForegroundColor;
    final Color arrowColor = themeForegroundColor.withOpacity(0.55);
    final Color mutedTextColor = themeForegroundColor.withOpacity(0.35);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
          onTap: () => isFile ? widget.onFileTap(widget.entity as File) : _toggleExpand(),
          child: Container(
            color: Colors.transparent, 
            padding: EdgeInsets.only(left: widget.depth * 10.0 + 6.0, top: 4, bottom: 4),
            child: Row(
              children: [
                Icon(
                  isFile ? null : (_isExpanded ? Icons.arrow_drop_down : Icons.arrow_right), 
                  size: 16, 
                  color: arrowColor,
                ),
                if (isFile) const SizedBox(width: 16),
                Icon(
                  isFile ? _getIconForExtension(p.extension(widget.entity.path).replaceAll('.', '')) : Icons.folder,
                  size: 15,
                  color: isFile ? _getColorForExtension(p.extension(widget.entity.path).replaceAll('.', '')) : const Color(0xEFFFCA28),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name, 
                    style: TextStyle(fontSize: 12.5, color: textColor, fontFamily: 'monospace'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isDirty) 
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Text(
                    "M", 
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 10, 
                      fontWeight: FontWeight.bold
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded && !isFile) _buildChildrenList(arrowColor, mutedTextColor),
      ],
    );
  }

  Widget _buildChildrenList(Color progressColor, Color emptyTextColor) {
    if (_isLoading) {
      return Padding(
        padding: EdgeInsets.only(left: (widget.depth + 1) * 10.0 + 22.0, top: 4, bottom: 4),
        child: SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.2, 
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ),
      );
    }

    if (_children == null || _children!.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: (widget.depth + 1) * 10.0 + 22.0, top: 3, bottom: 3),
        child: Text(
          "Empty folder", 
          style: TextStyle(color: emptyTextColor, fontSize: 11, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _children!.map((e) => FileTreeItem(
        key: ValueKey(e.path),
        entity: e,
        onFileTap: widget.onFileTap,
        onAction: widget.onAction,
        uiColors: widget.uiColors,
        openFiles: widget.openFiles,
        depth: widget.depth + 1,
      )).toList(),
    );
  }
}
