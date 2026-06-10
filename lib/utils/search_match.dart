import 'dart:io';

class SearchMatch {
  final File file;
  final int lineNumber;
  final String lineContent;

  SearchMatch(this.file, this.lineNumber, this.lineContent);
}
