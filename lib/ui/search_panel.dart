import 'dart:io';
import 'package:codeeditor/utils/search_match.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class SearchPanel extends StatefulWidget {
  final Map<String, dynamic> uiColors;
  final List<SearchMatch> results;
  final bool isSearching;
  final Function(String) onSearch;
  final Function(File, int) onFileTap;

  const SearchPanel({
    super.key,
    required this.uiColors,
    required this.results,
    required this.isSearching,
    required this.onSearch,
    required this.onFileTap,
  });

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  String _currentQuery = "";

  @override
  Widget build(BuildContext context) {
    Color resolve(String key, Color fallback) {
      final value = widget.uiColors[key];
      if (value is Color) return value;
      if (value is int) return Color(value);
      if (value is String) {
        try {
          return Color(int.parse(value.replaceFirst('#', '0xFF')));
        } catch (_) {
          return fallback;
        }
      }
      return fallback;
    }

    final Color bg = resolve("bg", const Color(0x1E1E1E));
    final Color defaultFg = (bg.computeLuminance() > 0.5) ? Colors.black87 : Colors.white70;
    final Color fg = resolve("bgForeground", resolve("sidebarForeground", defaultFg));
    final Color accent = resolve("statusBar", resolve("editorCursor.foreground", Colors.blue));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "SEARCH",
              style: TextStyle(color: fg.withOpacity(0.6), fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (val) {
              setState(() => _currentQuery = val);
              widget.onSearch(val);
            },
            style: TextStyle(color: fg, fontSize: 13),
            cursorColor: accent,
            decoration: InputDecoration(
              hintText: "Search in files...",
              hintStyle: TextStyle(color: fg.withOpacity(0.4)),
              filled: true,
              fillColor: bg.withOpacity(0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: fg.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: accent, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.isSearching)
          LinearProgressIndicator(minHeight: 2, backgroundColor: bg, valueColor: AlwaysStoppedAnimation<Color>(accent))
        else
          const SizedBox(height: 2),
        const SizedBox(height: 8),
        Expanded(
          child: widget.results.isEmpty && !widget.isSearching
              ? Center(child: Text("No results", style: TextStyle(color: fg.withOpacity(0.3))))
              : ListView.builder(
                  itemCount: widget.results.length,
                  itemBuilder: (context, index) {
                    final match = widget.results[index];
                    return InkWell(
                      onTap: () => widget.onFileTap(match.file, match.lineNumber),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.description, size: 12, color: fg.withOpacity(0.7)),
                              const SizedBox(width: 6),
                              Text(p.basename(match.file.path), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 18),
                              child: _buildHighlightedText("L${match.lineNumber}: ${match.lineContent.trim()}", _currentQuery, fg.withOpacity(0.7), accent.withOpacity(0.4)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHighlightedText(String text, String query, Color baseColor, Color highlightColor) {
    if (query.isEmpty) return Text(text, style: TextStyle(color: baseColor, fontSize: 11));
    final regExp = RegExp(RegExp.escape(query), caseSensitive: false);
    final matches = regExp.allMatches(text);
    final spans = <TextSpan>[];
    int start = 0;
    for (final match in matches) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
      spans.add(TextSpan(text: text.substring(match.start, match.end), style: TextStyle(backgroundColor: highlightColor, fontWeight: FontWeight.bold, color: baseColor)));
      start = match.end;
    }
    spans.add(TextSpan(text: text.substring(start)));
    return RichText(text: TextSpan(style: TextStyle(color: baseColor, fontSize: 11, fontFamily: 'monospace'), children: spans), maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
