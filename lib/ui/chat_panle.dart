import 'dart:convert';
import 'dart:io';
import 'package:codeeditor/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ChatPanel extends StatefulWidget {
  final Map<String, dynamic> uiColors;
  final String? rootPath;
  final List<String> projectFiles;
  final String Function()? getActiveFileContent;
  final Future<String> Function(String filePath) readFile;
  final Function(String action, String argument) onAgentAction;

  const ChatPanel({
    super.key,
    required this.uiColors,
    this.rootPath,
    required this.projectFiles,
    this.getActiveFileContent,
    required this.readFile,
    required this.onAgentAction,
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  bool _isConfiguring = false;
  bool _isAsking = false;
  bool _isProcessing = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  String _pendingSystemOutput = "";

  final Map<String, TextEditingController> _controllers = {
    'model': TextEditingController(text: 'gemma-4-e4b'),
    'baseUrl': TextEditingController(text: 'http://localhost:1234'),
  };

  String _normalizePath(String path) {
    return path.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator);
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) controller.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([bool isAuto = false, String? autoContent]) async {
    final text = autoContent ?? _chatController.text.trim();
    if (text.isEmpty && !isAuto) return;

    if (!isAuto) {
      setState(() {
        ChatService.addMessage("user", text);
        _chatController.clear();
      });
      _scrollToBottom();
    }

    setState(() => _isProcessing = true);

    try {
      final baseUrl = _controllers['baseUrl']!.text.replaceAll(RegExp(r'\/$'), '');

      final List<Map<String, String>> messages = [
        {
          "role": "system",
          "content": """You are an autonomous coding assistant. ROOT PATH: ${widget.rootPath}.
          RULES: 
          1. Use [LS] <path> to list files. 2. Use [READ] <path> to read files. 3. Use [ASK] <question> for human help.
          4. If you receive 'SYSTEM OUTPUT', analyze it to continue your task, but do not repeat it to the user."""
        }
      ];

      messages.addAll(ChatService.messages.map((m) => {
        "role": m["role"] == "ai" ? "assistant" : "user", 
        "content": m["content"]!
      }));
      
      if (_pendingSystemOutput.isNotEmpty) {
        messages.add({"role": "user", "content": _pendingSystemOutput});
        _pendingSystemOutput = "";
      }

      final response = await http.post(
        Uri.parse('$baseUrl/v1/chat/completions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"model": _controllers['model']!.text, "messages": messages}),
      );

      if (response.statusCode == 200) {
        final aiResponse = jsonDecode(response.body)['choices'][0]['message']['content'];

        if (aiResponse.contains("[ASK]")) {
          _handleAsk(aiResponse);
        } else if (aiResponse.contains("[READ]")) {
          await _handleRead(aiResponse);
        } else if (aiResponse.contains("[LS]")) {
          await _handleList(aiResponse);
        } else {
          _finalizeResponse(aiResponse);
        }
      } else {
        _finalizeResponse("Error: ${response.statusCode}");
      }
    } catch (e) {
      _finalizeResponse("Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _handleAsk(String response) {
    setState(() => _isAsking = true);
    _finalizeResponse(response);
  }

  Future<void> _handleRead(String aiResponse) async {
    final match = RegExp(r"\[READ\] (.+)").firstMatch(aiResponse);
    final path = match?.group(1)?.trim().replaceAll('"', '');

    if (path != null) {
      String fullPath = _normalizePath(path.startsWith(widget.rootPath!) ? path : "${widget.rootPath}${Platform.pathSeparator}$path");
      final file = File(fullPath);
      
      if (await file.exists()) {
        final content = await file.readAsString();
        _pendingSystemOutput = "SYSTEM OUTPUT: Content of $fullPath: $content";
        _sendMessage(true); 
      } else {
        _pendingSystemOutput = "SYSTEM ERROR: File does not exist.";
        _sendMessage(true);
      }
    }
  }

  Future<void> _handleList(String aiResponse) async {
    final match = RegExp(r"\[LS\] (.+)").firstMatch(aiResponse);
    final path = match?.group(1)?.trim();

    if (path != null) {
      String fullPath = _normalizePath(path.startsWith(widget.rootPath!) ? path : "${widget.rootPath}${Platform.pathSeparator}$path");
      final dir = Directory(fullPath);

      if (await dir.exists()) {
        final list = await dir.list().map((e) => e.path.split(Platform.pathSeparator).last).toList();
        _pendingSystemOutput = "SYSTEM OUTPUT: Content of $fullPath: ${list.join(', ')}";
        _sendMessage(true);
      } else {
        _pendingSystemOutput = "SYSTEM ERROR: Invalid directory.";
        _sendMessage(true);
      }
    }
  }

  void _finalizeResponse(String response) {
    setState(() => ChatService.addMessage("ai", response));
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    Color get(List<String> keys, Color fallback) {
      for (final key in keys) {
        final val = widget.uiColors[key];
        if (val is Color) return val;
        if (val is int) return Color(val);
      }
      return fallback;
    }

    final Color bg = get(["bg", "sidebarBackground"], const Color(0xFF1E1E1E));
    final Color fg = get(["bgForeground", "sidebarForeground"], Colors.white70);
    final Color accent = get(["statusBar", "editorCursor.foreground"], Colors.blue);

    return Container(
      color: bg,
      child: Column(
        children: [
          _buildHeader(fg),
          if (_isProcessing) LinearProgressIndicator(color: accent, backgroundColor: Colors.transparent),
          Expanded(child: _isConfiguring ? _buildSettingsView(fg, bg, accent) : _buildChatView(fg, accent))
        ],
      ),
    );
  }

  Widget _buildHeader(Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("AI AGENT", style: TextStyle(color: fg.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold)),
          IconButton(
            icon: Icon(_isConfiguring ? Icons.close : Icons.settings, size: 16, color: fg),
            onPressed: () => setState(() => _isConfiguring = !_isConfiguring),
          )
        ],
      ),
    );
  }

  Widget _buildChatView(Color fg, Color accent) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: ChatService.messages.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ChatService.messages[i]["role"]!.toUpperCase(), style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold)),
                  Text(ChatService.messages[i]["content"]!, style: TextStyle(color: fg, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: _isAsking
              ? TextField(
                  autofocus: true,
                  style: TextStyle(color: fg, fontSize: 13),
                  decoration: InputDecoration(hintText: "Response for the agent...", filled: true, fillColor: accent.withOpacity(0.1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(4))),
                  onSubmitted: (value) {
                    setState(() => _isAsking = false);
                    _sendMessage(false, value);
                  },
                )
              : TextField(
                  controller: _chatController,
                  enabled: !_isProcessing,
                  onSubmitted: (_) => _sendMessage(),
                  style: TextStyle(color: fg, fontSize: 13),
                  decoration: InputDecoration(hintText: _isProcessing ? "Processing..." : "Ask AI Agent...", suffixIcon: IconButton(icon: Icon(Icons.send, color: accent, size: 16), onPressed: _isProcessing ? null : () => _sendMessage()), filled: true, fillColor: fg.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none)),
                ),
        )
      ],
    );
  }

  Widget _buildSettingsView(Color fg, Color bg, Color accent) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("AGENT SETTINGS", style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
        _buildTextField(label: "Base URL", controller: _controllers['baseUrl']!),
        _buildTextField(label: "Model ID", controller: _controllers['model']!),
        const SizedBox(height: 20),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: bg), onPressed: () => setState(() => _isConfiguring = false), child: const Text("Save Changes")),
      ],
    );
  }

  Widget _buildTextField({required String label, required TextEditingController controller}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 12, color: Colors.grey), border: const OutlineInputBorder()),
      ),
    );
  }
}
