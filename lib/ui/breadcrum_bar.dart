import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class BreadcrumbsBar extends StatelessWidget {
  final String? activeFilePath;
  final String? rootPath;
  final Map<String, dynamic> uiColors;

  const BreadcrumbsBar({
    Key? key,
    required this.activeFilePath,
    required this.rootPath,
    required this.uiColors,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color barBackground = Color(uiColors["tabBar"] ?? 0xFF252526).withOpacity(0.95);
    final Color textColor = Color(uiColors["sidebarForeground"] ?? 0xFFFFFFFF);
    final Color mutedColor = textColor.withOpacity(0.4);
    final Color activeColor = textColor.withOpacity(0.85);

    if (activeFilePath == null) {
      return Container(
        height: 22,
        decoration: BoxDecoration(
          color: barBackground,
        ),
      );
    }

    List<String> segments = [];
    if (rootPath != null && activeFilePath!.startsWith(rootPath!)) {
      String relative = p.relative(activeFilePath!, from: rootPath);
      segments = p.split(relative);
    } else {
      segments = p.split(activeFilePath!);
      if (segments.length > 3) {
        segments = segments.sublist(segments.length - 3);
      }
    }

    return Container(
      height: 22,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: barBackground, 
        border: Border(
          bottom: BorderSide(color: Colors.black.withOpacity(0.2), width: 1),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: segments.length,
        separatorBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right, size: 11, color: mutedColor),
        ),
        itemBuilder: (context, index) {
          final isLast = index == segments.length - 1;
          final segmentName = segments[index];
          final isFile = isLast && p.extension(segmentName).isNotEmpty;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFile ? Icons.insert_drive_file_outlined : Icons.folder_open_outlined,
                size: 11,
                color: isLast ? activeColor : mutedColor,
              ),
              const SizedBox(width: 4),
              Text(
                segmentName,
                style: TextStyle(
                  color: isLast ? activeColor : mutedColor,
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}