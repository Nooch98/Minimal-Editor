import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class FileTreeItem extends StatefulWidget {
  final FileSystemEntity entity;
  final Function(File) onFileTap;
  final VoidCallback onAction;
  final Map<String, dynamic> uiColors;
  final int depth;

  const FileTreeItem({
    super.key,
    required this.entity,
    required this.onFileTap,
    required this.onAction,
    required this.uiColors,
    this.depth = 0,
  });

  @override
  State<FileTreeItem> createState() => _FileTreeItemState();
}

class _FileTreeItemState extends State<FileTreeItem> {
  bool _isExpanded = false;

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
      default: return Icons.insert_drive_file;
    }
  }

  void _showNameDialog(bool isFolder) {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: Color(widget.uiColors["bg"]),
          textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white),
        ),
        child: AlertDialog(
          backgroundColor: Color(widget.uiColors["sidebar"]),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                String name = controller.text;
                if (name.isNotEmpty) {
                  String parentPath = widget.entity is Directory ? widget.entity.path : p.dirname(widget.entity.path);
                  String newPath = p.join(parentPath, name);
                  isFolder ? await Directory(newPath).create() : await File(newPath).create();
                  widget.onAction();
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

  void _showContextMenu(Offset position) async {
    final result = await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: Color(widget.uiColors["sidebar"]),
      items: [
        if (widget.entity is Directory) ...[
          const PopupMenuItem(value: "new_file", child: Text("New File", style: TextStyle(color: Colors.white, fontSize: 13))),
          const PopupMenuItem(value: "new_folder", child: Text("New Folder", style: TextStyle(color: Colors.white, fontSize: 13))),
        ],
        const PopupMenuItem(value: "delete", child: Text("Delete", style: TextStyle(color: Colors.red, fontSize: 13))),
      ],
    );

    if (result == "delete") {
      await widget.entity.delete(recursive: true);
      widget.onAction();
    } else if (result == "new_file") {
      _showNameDialog(false);
    } else if (result == "new_folder") {
      _showNameDialog(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFile = widget.entity is File;
    final name = p.basename(widget.entity.path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
          onTap: () {
            if (isFile) {
              widget.onFileTap(widget.entity as File);
            } else {
              setState(() => _isExpanded = !_isExpanded);
            }
          },
          child: Container(
            padding: EdgeInsets.only(left: widget.depth * 12.0 + 8.0, top: 4, bottom: 4),
            child: Row(
              children: [
                if (!isFile) Icon(_isExpanded ? Icons.arrow_drop_down : Icons.arrow_right, size: 16, color: Colors.white70),
                Icon(
                  isFile ? _getIconForExtension(p.extension(widget.entity.path).replaceAll('.', '')) : Icons.folder,
                  size: 16,
                  color: isFile ? _getColorForExtension(p.extension(widget.entity.path)) : Colors.amber,
                ),
                const SizedBox(width: 6),
                Text(name, style: const TextStyle(fontSize: 13, color: Colors.white70)),
              ],
            ),
          ),
        ),
        if (_isExpanded && !isFile) ..._buildChildren(),
      ],
    );
  }

  List<Widget> _buildChildren() {
    try {
      final dir = widget.entity as Directory;
      List<FileSystemEntity> children = dir.listSync();
      children.sort((a, b) {
        if (a is Directory && b is File) return -1;
        if (a is File && b is Directory) return 1;
        return a.path.compareTo(b.path);
      });
      return children.map((e) => FileTreeItem(
        entity: e,
        onFileTap: widget.onFileTap,
        onAction: widget.onAction,
        uiColors: widget.uiColors,
        depth: widget.depth + 1,
      )).toList();
    } catch (e) {
      return [const Text("Error", style: TextStyle(color: Colors.red))];
    }
  }
}