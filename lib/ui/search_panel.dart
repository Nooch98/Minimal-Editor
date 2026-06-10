import 'dart:io';
import 'package:codeeditor/utils/search_match.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class SearchPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "SEARCH",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: onSearch,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Search in files...",
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Color(uiColors["bg"] ?? 0xFF1E1E1E),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (isSearching)
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
          )
        else
          const SizedBox(height: 2),
          
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final match = results[index];
              final fileName = p.basename(match.file.path);

              return InkWell(
                onTap: () => onFileTap(match.file, match.lineNumber),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.description, size: 12, color: Colors.white30),
                          const SizedBox(width: 6),
                          Text(
                            fileName, 
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 18),
                        child: Text(
                          "L${match.lineNumber}: ${match.lineContent.trim()}",
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
}
