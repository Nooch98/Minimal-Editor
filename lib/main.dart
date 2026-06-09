import 'package:codeeditor/ui/editor.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: EditorScaffold()));
}
