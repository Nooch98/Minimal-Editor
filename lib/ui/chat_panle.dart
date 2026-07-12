import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:codeeditor/services/chat_service.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

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
  bool _isProcessing = false;
  Map<String, String>? _pendingWriteAction;

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _pendingSystemOutput = "";
  bool _writeCompleted = false;

  final TextEditingController _apiKeyController = TextEditingController();
  String _selectedProvider = 'ChatGPT';
  static const List<String> _providers = ['ChatGPT', 'Anthropic', 'Ollama', 'LM Studio', 'Gemini'];

  final Map<String, TextEditingController> _controllers = {
    'model': TextEditingController(text: 'gemma-4-e4b'),
    'baseUrl': TextEditingController(text: 'http://localhost:1234'),
    'mcpUrl': TextEditingController(text: 'http://127.0.0.1:8080'),
  };

  @override
  void initState() {
    super.initState();
    _startMcpServer();
    _loadSettings();
    _loadChatHistory();
  }

  Future<void> _startMcpServer() async {
    final app = shelf_router.Router();

    app.post('/mcp/call', (Request request) async {
      try {
        final body = await request.readAsString();
        final payload = jsonDecode(body);
        final String tool = payload['tool'];
        final Map<String, dynamic> args = payload['args'];

        final result = await _executeLocalTool(tool, args);
        
        return Response.ok(
          jsonEncode({"result": result}), 
          headers: {'Content-Type': 'application/json'}
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({"error": e.toString()}));
      }
    });

    await io.serve(app, '127.0.0.1', 8080);
    debugPrint("Servidor MCP interno corriendo en puerto 8080");
  }

  Future<String> _executeLocalTool(String tool, Map<String, dynamic> args) async {
    switch (tool) {
      case "read_file":
        final String path = args['path'] ?? '';
        if (path.isEmpty) return "ERROR: No path.";
        return await widget.readFile(path);

      case "ls":
        final dir = Directory(_toAbsolutePath(args['path'] ?? "."));
        if (await dir.exists()) {
          final entities = await dir.list().map((e) => e.path.split(Platform.pathSeparator).last).toList();
          return entities.join(', ');
        }
        return "Directory not found.";

      case "write_file":
        try {
          final String path = args['path'] ?? '';
          final String content = args['content'] ?? "";
          final bool append = args['append'] == true;
          final File file = File(_toAbsolutePath(path));
          
          if (!await file.exists()) return "ERROR: File not found.";

          if (append) {
            await file.writeAsString("\n$content", mode: FileMode.append);
            return "SUCCESS: Line appended to '$path'. TASK COMPLETE.";
          } else {
            String currentContent = await file.readAsString();
            if (currentContent == content) {
              return "SUCCESS: Content already matches. TASK COMPLETE.";
            }
            await file.writeAsString(content);
            return "SUCCESS: File '$path' updated. TASK COMPLETE.";
          }
        } catch (e) {
          return "ERROR: Could not write: $e";
        }

      case "append_file":
          try {
            final String path = args['path'] ?? '';
            final String content = args['content'] ?? "";
            final File file = File(_toAbsolutePath(path));
            
            if (!await file.exists()) return "ERROR: File not found.";
            
            await file.writeAsString("\n$content", mode: FileMode.append);
            return "SUCCESS: Line appended. TASK COMPLETE.";
          } catch (e) {
            return "ERROR: $e";
          }

      case "exec":
        final String command = args['command'] ?? "";
        final result = await Process.run(Platform.isWindows ? 'cmd' : '/bin/sh', 
            [Platform.isWindows ? '/c' : '-c', command], workingDirectory: widget.rootPath);
        return "Output: ${result.stdout}\nExit code: ${result.exitCode}";

      default:
        return "Tool '$tool' not recognized.";
    }
  }

  Future<void> _clearChatHistory() async {
    ChatService.clearChatHistory();
    if (await _chatFile.exists()) await _chatFile.delete();
    setState(() {});
  }

  File get _settingsFile => File('${widget.rootPath}${Platform.pathSeparator}agent_settings.json');
  File get _chatFile => File('${widget.rootPath}${Platform.pathSeparator}${widget.rootPath!.split(Platform.pathSeparator).last}_chat.json');

  Future<void> _saveSettings() async {
    final settings = {
      "provider": _selectedProvider,
      "apiKey": _apiKeyController.text,
      "baseUrl": _controllers['baseUrl']!.text,
      "mcpUrl": _controllers['mcpUrl']!.text,
      "model": _controllers['model']!.text,
    };
    await _settingsFile.writeAsString(jsonEncode(settings));
  }

  Future<void> _loadSettings() async {
    if (await _settingsFile.exists()) {
      try {
        final data = jsonDecode(await _settingsFile.readAsString());
        setState(() {
          _selectedProvider = data['provider'] ?? 'ChatGPT';
          _apiKeyController.text = data['apiKey'] ?? '';
          _controllers['baseUrl']!.text = data['baseUrl'] ?? 'http://localhost:1234';
          _controllers['mcpUrl']!.text = data['mcpUrl'] ?? 'http://127.0.0.1:8080';
          _controllers['model']!.text = data['model'] ?? 'gemma-4-e4b';
        });
      } catch (e) { debugPrint("Error loading settings: $e"); }
    }
  }

  Future<void> _saveChatHistory() async {
    final history = ChatService.messages.map((m) => m).toList();
    await _chatFile.writeAsString(jsonEncode(history));
  }

  Future<void> _loadChatHistory() async {
    if (await _chatFile.exists()) {
      try {
        final List<dynamic> data = jsonDecode(await _chatFile.readAsString());
        setState(() {
          ChatService.clearChatHistory();
          for (var m in data) { ChatService.addMessage(m['role'], m['content']); }
        });
      } catch (e) { debugPrint("Error loading chat history: $e"); }
    }
  }

  String _toAbsolutePath(String path) {
    if (path.isEmpty || path == ".") return widget.rootPath!;
    final file = File(path);
    if (file.isAbsolute) return path;
    return '${widget.rootPath}${Platform.pathSeparator}$path';
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) controller.dispose();
    _chatController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<String> _callMcpTool(String toolName, Map<String, dynamic> args) async {
    try {
      final response = await http.post(
        Uri.parse(_controllers['mcpUrl']!.text + '/mcp/call'), 
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"tool": toolName, "args": args}),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['result'].toString();
      }
      return "Error MCP: ${response.statusCode}";
    } catch (e) {
      return "Error de conexión MCP: $e";
    }
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
      _saveChatHistory();
    }

    setState(() => _isProcessing = true);

    try {
      final baseUrl = _controllers['baseUrl']!.text.replaceAll(RegExp(r'\/$'), '');
      
      final history = ChatService.messages;
      final recentMessages = history.length > 15 ? history.sublist(history.length - 15) : history;

      final String systemInstructions = """
        You are an expert autonomous software engineer.
        You have access to MCP tools.
        
        RULES:
        1. DO NOT USE ANY TAGS LIKE <|tool_call|>. 
        2. Output ONLY raw JSON when calling tools: { "tool": "tool_name", "args": { ... } }
        3. ALWAYS read a file first using 'read_file' before attempting to modify it.
        4. IF the file already contains the information you are trying to add, DO NOT write to it.
        5. WHEN UPDATING FILES:
          - Use { "tool": "write_file", "args": { "path": "filename", "content": "new_line", "append": true } } to add content to the END of a file.
          - Use { "tool": "write_file", "args": { "path": "filename", "content": "full_file_content" } } ONLY if you intend to completely replace the file content.
        6. AFTER any tool execution, if the task is complete, stop immediately. Do not loop 'ls' or 'read_file'.
      """;

      final List<Map<String, String>> messages = [{"role": "system", "content": systemInstructions}];
      messages.addAll(recentMessages.map((m) => {"role": m["role"] == "ai" ? "assistant" : "user", "content": m["content"]!}));
      
      if (_pendingSystemOutput.isNotEmpty) {
        messages.add({"role": "user", "content": _pendingSystemOutput});
        _pendingSystemOutput = "";
      }

      final headers = {'Content-Type': 'application/json'};
      if (_apiKeyController.text.isNotEmpty) headers['Authorization'] = 'Bearer ${_apiKeyController.text}';

      final response = await http.post(
        Uri.parse('$baseUrl/v1/chat/completions'),
        headers: headers,
        body: jsonEncode({"model": _controllers['model']!.text, "messages": messages}),
      );

      if (response.statusCode == 200) {
        final aiResponse = jsonDecode(response.body)['choices'][0]['message']['content'];
        _parseAgentResponse(aiResponse);
      } else {
        _finalizeResponse("Error de conexión: ${response.statusCode}");
      }
    } catch (e) {
      _finalizeResponse("Error crítico: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _parseAgentResponse(String response) async {
    String cleanResponse = response
        .replaceAll('<|tool_call>', '')
        .replaceAll('<tool_call|>', '')
        .trim();

    final jsonMatches = RegExp(r'\{.*?"tool".*?\}', dotAll: true).allMatches(cleanResponse);

    if (jsonMatches.isNotEmpty) {
      List<String> results = [];

      for (final match in jsonMatches) {
        String jsonString = match.group(0)!;        
        int openBraces = '{'.allMatches(jsonString).length;
        int closeBraces = '}'.allMatches(jsonString).length;
        while (openBraces > closeBraces) {
          jsonString += '}';
          closeBraces++;
        }
        
        try {
          Map<String, dynamic> json = jsonDecode(jsonString);
          final Map<String, dynamic> toolData = json.containsKey('call') ? json['call'] : json;
          
          String tool = toolData['tool']?.toString().toLowerCase() ?? "";
          Map<String, dynamic> rawArgs = Map<String, dynamic>.from(toolData['args'] ?? {});

          if (tool == 'fs' || tool == 'filesystem' || tool == 'file_manager' || tool == 'mcp') {
            if (rawArgs.containsKey('command')) tool = 'exec';
            else if (rawArgs.containsKey('read')) { tool = 'read_file'; rawArgs['path'] = rawArgs['read']; }
            else tool = 'ls';
          } else if (tool.contains('write') || tool == 'save') {
              tool = 'write_file';
          } else if (tool == 'list' || tool == 'list_files' || tool == 'list_directory') {
            tool = 'ls';
          } else if (tool == 'append' || tool == 'append_file') {
            tool = 'append_file';
          }

          if (!['append_file', 'read_file', 'ls', 'exec'].contains(tool)) {
              results.add("Result of $tool: ERROR. write_file is disabled. Use append_file.");
              continue;
          }

          Map<String, dynamic> args = {};
          args['path'] = rawArgs['path'] ?? rawArgs['filename'] ?? rawArgs['file'] ?? '.';
          if (rawArgs.containsKey('content')) args['content'] = rawArgs['content'];
          if (rawArgs.containsKey('command')) args['command'] = rawArgs['command'];

          debugPrint("Executing tool: $tool with args: $args");
          final result = await _callMcpTool(tool, args);
          results.add("Result of $tool: $result");
          
        } catch (e) {
          debugPrint("JSON Error: $e");
        }
      }

      if (results.isNotEmpty) {
        String summary = results.join("\n");
        if (summary.contains("TASK COMPLETE")) {
          _finalizeResponse("Task completed: $summary");
          return;
        }
        _pendingSystemOutput = "MCP TOOL RESULTS:\n$summary";
        _sendMessage(true);
        return;
      }
    }

    _finalizeResponse(response);
  }

  Future<void> _handleExec(String command) async {
    _pendingSystemOutput = "SYSTEM OUTPUT: Executing command: '$command'...\n";
    
    try {
      final isWindows = Platform.isWindows;
      final shell = isWindows ? 'cmd' : '/bin/sh';
      final flag = isWindows ? '/c' : '-c';

      final process = await Process.start(
        shell, 
        [flag, command], 
        workingDirectory: widget.rootPath,
        runInShell: true,
      );
      
      process.stdout.transform(utf8.decoder).listen((data) {
        _pendingSystemOutput += data;
      });
      
      process.stderr.transform(utf8.decoder).listen((data) {
        _pendingSystemOutput += "ERROR: $data";
      });

      final exitCode = await process.exitCode;
      _pendingSystemOutput += "\nSYSTEM OUTPUT: Command finished with exit code $exitCode";
      
    } catch (e) {
      _pendingSystemOutput += "\nSYSTEM ERROR: Could not execute command: $e";
    }
    
    _sendMessage(true, "Command execution finished. Review the output above.");
  }

  Future<void> _executeWrite() async {
    final path = _pendingWriteAction!["path"]!;
    final content = _pendingWriteAction!["content"]!;
    final fullPath = _toAbsolutePath(path);
    
    try {
      await File(fullPath).writeAsString(content, flush: true);
      _pendingSystemOutput = "SYSTEM OUTPUT: File $path updated successfully.";
    } catch (e) {
      _pendingSystemOutput = "SYSTEM ERROR: Could not write: $e";
    } finally {
      setState(() => _pendingWriteAction = null);
    }
    _sendMessage(true);
  }

  Future<void> _handleRead(String aiResponse) async {
  final match = RegExp(r"\[READ\] (.+)").firstMatch(aiResponse) ?? RegExp(r"path:(.+?)[\} ]").firstMatch(aiResponse);
  final rawPath = match?.group(1)?.trim();
  
  if (rawPath != null) {
    final fullPath = _toAbsolutePath(rawPath);
    final file = File(fullPath);
    
    if (await file.exists()) {
      final content = await file.readAsString();
      _pendingSystemOutput = "SYSTEM OUTPUT: File Content of $rawPath:\n\n---\n$content\n---";
    } else {
      _pendingSystemOutput = "SYSTEM ERROR: File not found: $rawPath";
    }    
    _sendMessage(true, "The file content has been loaded. Please proceed with your analysis.");
  }
}

  Future<void> _handleList(String aiResponse) async {
    final match = RegExp(r"\[LS\] (.+)").firstMatch(aiResponse);
    final rawPath = match?.group(1)?.trim() ?? ".";
    final fullPath = _toAbsolutePath(rawPath);
    final dir = Directory(fullPath);

    if (await dir.exists()) {
      final entities = await dir.list().map((e) => e.path.split(Platform.pathSeparator).last).toList();
      _pendingSystemOutput = "SYSTEM OUTPUT: Directory $rawPath contains: ${entities.join(', ')}";
    } else {
      _pendingSystemOutput = "SYSTEM ERROR: Cannot list $rawPath.";
    }
    _sendMessage(true);
  }

  void _finalizeResponse(String response) {
    setState(() => ChatService.addMessage("ai", response));
    _saveChatHistory();
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
          _buildHeader(fg, accent),
          if (_isProcessing) LinearProgressIndicator(color: accent, backgroundColor: Colors.transparent),
          Expanded(child: _isConfiguring ? _buildSettingsView(fg, bg, accent) : _buildChatView(fg, accent))
        ],
      ),
    );
  }

  Widget _buildHeader(Color fg, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("AI AGENT", style: TextStyle(color: fg.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold)),
          Row(
            children: [
              IconButton(icon: Icon(Icons.delete_sweep, size: 16, color: fg), onPressed: _clearChatHistory),
              IconButton(icon: Icon(_isConfiguring ? Icons.close : Icons.settings, size: 16, color: fg), onPressed: () => setState(() => _isConfiguring = !_isConfiguring)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildChatView(Color fg, Color accent) {
    final markdownStyle = MarkdownStyleSheet(
      p: TextStyle(color: fg, fontSize: 13, height: 1.5),
      code: TextStyle(
        fontFamily: 'monospace',
        backgroundColor: fg.withOpacity(0.15),
        color: accent,
        fontSize: 12,
      ),
      blockquote: TextStyle(color: fg.withOpacity(0.7), fontStyle: FontStyle.italic),
      listBullet: TextStyle(color: accent),
      strong: TextStyle(color: fg, fontWeight: FontWeight.bold),
      h1: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.bold),
      h2: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.bold),
    );

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: ChatService.messages.length,
            itemBuilder: (context, i) {
              final msg = ChatService.messages[i];
              final isUser = msg["role"] == "user";
              String content = msg["content"]!;

              String? reasoning;
              final rMatch = RegExp(r"<reasoning>(.*?)</reasoning>", dotAll: true).firstMatch(content);
              if (rMatch != null) {
                reasoning = rMatch.group(1)?.trim();
                content = content.replaceFirst(rMatch.group(0)!, "").trim();
              }

              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                  decoration: BoxDecoration(
                    color: isUser ? accent.withOpacity(0.15) : fg.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (reasoning != null) ...[
                        Text("🤔 Reasoning:", style: TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(reasoning, style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: fg.withOpacity(0.6))),
                        const Divider(height: 16, thickness: 0.5),
                      ],
                      MarkdownBody(
                        data: content,
                        selectable: true,
                        styleSheet: markdownStyle,
                        builders: {
                          'code': CodeBlockBuilder(fg: fg, accent: accent),
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_pendingWriteAction != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Agent wants to modify:", style: TextStyle(color: fg, fontSize: 10)),
                Text(_pendingWriteAction!['path']!, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => setState(() => _pendingWriteAction = null), child: const Text("Deny")),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: accent), onPressed: _executeWrite, child: const Text("Approve")),
                  ],
                )
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _chatController,
            maxLines: 4,
            minLines: 1,
            enabled: !_isProcessing,
            style: TextStyle(color: fg, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Ask AI agent...",
              filled: true,
              fillColor: fg.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              suffixIcon: IconButton(icon: Icon(Icons.send, color: accent, size: 16), onPressed: _isProcessing ? null : () => _sendMessage()),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildSettingsView(Color fg, Color bg, Color accent) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("PROVIDER", style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: _selectedProvider,
          dropdownColor: bg,
          isExpanded: true,
          items: _providers.map((p) => DropdownMenuItem(value: p, child: Text(p, style: TextStyle(color: fg)))).toList(),
          onChanged: (v) => setState(() => _selectedProvider = v!),
        ),
        const SizedBox(height: 10),
        _buildTextField(label: "API Key (Optional)", controller: _apiKeyController, obscure: true),
        _buildTextField(label: "Base URL", controller: _controllers['baseUrl']!),
        _buildTextField(label: "MCP URL", controller: _controllers['mcpUrl']!),
        _buildTextField(label: "Model ID", controller: _controllers['model']!),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: bg),
          onPressed: () { _saveSettings(); setState(() => _isConfiguring = false); },
          child: const Text("Save Changes"),
        ),
      ],
    );
  }

  Widget _buildTextField({required String label, required TextEditingController controller, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 12, color: Colors.grey), border: const OutlineInputBorder()),
      ),
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final Color fg;
  final Color accent;

  CodeBlockBuilder({required this.fg, required this.accent});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: Icon(Icons.copy, size: 14, color: accent),
              onPressed: () => Clipboard.setData(ClipboardData(text: element.textContent)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SelectableText(
              element.textContent,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
