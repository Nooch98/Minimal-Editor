import 'dart:io';

class OpenFile {
  final File file;
  final String content;
  bool isDirty;
  OpenFile({required this.file, required this.content, this.isDirty = false});
}
