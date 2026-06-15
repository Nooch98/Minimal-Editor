import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class VcsPanel extends StatefulWidget {
  final String? rootPath;
  final Map<String, dynamic> uiColors;

  final Function(File) onFileTap;

  const VcsPanel({
    Key? key,
    required this.rootPath,
    required this.uiColors,
    required this.onFileTap,
  }) : super(key: key);

  @override
  State<VcsPanel> createState() => _VcsPanelState();
}

class _VcsPanelState extends State<VcsPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isProcessing = false;
  bool _obscurePassword = true;
  
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();

  List<File> _modifiedFiles = [];
  String _currentBranch = "main";

  List<Map<String, dynamic>> _parsedLogs = [];
  Map<String, dynamic> _parsedStats = {
    "totalCommits": 0,
    "filesTracked": 0,
    "vaultSize": "0 KB",
    "extensions": <String, int>{}
  };
  late TextEditingController _pullIdController;
  late TextEditingController _pullPasswordController;
  bool _obscurePullPassword = true;
  List<dynamic> _pullLogs = [];
  bool _showIdSuggestions = false;

  final String _vcsExecutable = "vcs"; 

  @override
  void initState() {
    super.initState();    
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabSelection);    
    _pullIdController = TextEditingController();
    _pullPasswordController = TextEditingController();    
    _refreshVcsState();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _messageController.dispose();
    _authorController.dispose();
    _passwordController.dispose();
    _pullIdController.dispose();
    _pullPasswordController.dispose();    
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      if (_tabController.index == 1) _fetchLogs();
      if (_tabController.index == 2) _fetchStats();
      if (_tabController.index == 3) {
        _pullIdController.clear(); 
        setState(() => _showIdSuggestions = false);
      }
    }
  }

  String _cleanAsciiColors(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
  }

  Future<ProcessResult?> _runVcsCommand(List<String> arguments, {String? writeToStdin}) async {
    if (widget.rootPath == null) return null;
    
    try {
      if (writeToStdin != null && writeToStdin.isNotEmpty) {
        final process = await Process.start(
          _vcsExecutable,
          arguments,
          workingDirectory: widget.rootPath,
        );

        process.stdin.writeln(writeToStdin);
        await process.stdin.flush();
        
        final rawStdout = await process.stdout.transform(utf8.decoder).join();
        final rawStderr = await process.stderr.transform(utf8.decoder).join();
        final exitCode = await process.exitCode;

        return ProcessResult(
          process.pid, 
          exitCode, 
          _cleanAsciiColors(rawStdout), 
          _cleanAsciiColors(rawStderr)
        );
      } else {
        final result = await Process.run(
          _vcsExecutable,
          arguments,
          workingDirectory: widget.rootPath,
        );

        return ProcessResult(
          result.pid,
          result.exitCode,
          _cleanAsciiColors(result.stdout.toString()),
          _cleanAsciiColors(result.stderr.toString())
        );
      }
    } catch (e) {
      debugPrint("Error executing CLI (\$arguments): \$e");
      return null;
    }
  }

  Future<void> _fetchLogs() async {
    setState(() => _isProcessing = true);
    final result = await _runVcsCommand(["log", "--full"]);
    
    List<Map<String, dynamic>> tempLogs = [];
    if (result != null && result.exitCode == 0) {
      final lines = result.stdout.toString().split('\n');
      Map<String, dynamic>? currentLog;
      List<Map<String, String>> currentFiles = [];
      Map<String, int> currentCategories = {};

      for (var line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        
        final commitMatch = RegExp(r'\[\d+\]\s+(\d+)').firstMatch(trimmed);
        if (commitMatch != null) {
          if (currentLog != null) {
            currentLog["files"] = List<Map<String, String>>.from(currentFiles);
            currentLog["categories"] = Map<String, int>.from(currentCategories);
            tempLogs.add(currentLog);
          }
          
          final String fullId = commitMatch.group(1)!;
          final String shortId = fullId.length >= 7 ? fullId.substring(0, 7) : fullId;

          currentLog = {
            "id": fullId,
            "shortId": shortId,
            "message": "",
            "changesSummary": "",
          };
          currentFiles = [];
          currentCategories = {};
          continue;
        }

        if (currentLog == null) continue;

        if (trimmed.startsWith("Date:")) {
          currentLog["date"] = trimmed.replaceAll("Date:", "").trim();
        } else if (trimmed.startsWith("Author:")) {
          currentLog["author"] = trimmed.replaceAll("Author:", "").trim();
        } else if (trimmed.startsWith("Message:")) {
          currentLog["message"] = trimmed.replaceAll("Message:", "").trim();
        } else if (trimmed.startsWith("Changes:")) {
          currentLog["changesSummary"] = trimmed.replaceAll("Changes:", "").trim();
        } 
        else if (trimmed.contains("file(s)") && (trimmed.contains("├──") || trimmed.contains("└──"))) {
          final cleanLine = trimmed.replaceAll(RegExp(r'[├└──│]'), '').trim();
          final parts = cleanLine.split(':');
          if (parts.length == 2) {
            final catName = parts[0].trim();
            final catCount = int.tryParse(RegExp(r'\d+').stringMatch(parts[1]) ?? '') ?? 0;
            currentCategories[catName] = catCount;
          }
        }
        else if (RegExp(r'^\[[NMD]\]').hasMatch(trimmed)) {
          final status = trimmed.substring(1, 2);
          final filePath = trimmed.substring(3).trim();
          currentFiles.add({
            "status": status,
            "path": filePath,
          });
        }
      }

      if (currentLog != null) {
        currentLog["files"] = currentFiles;
        currentLog["categories"] = currentCategories;
        tempLogs.add(currentLog);
      }
    }

    setState(() {
      _parsedLogs = tempLogs; 
      _isProcessing = false;
    });
  }

  Future<void> _fetchStats() async {
    setState(() => _isProcessing = true);
    final result = await _runVcsCommand(["stats", "--charts"]);
    
    int commits = 0;
    int files = 0;
    String size = "0 KB";
    String growth = "N/A";
    String integrity = "N/A";
    String largest = "N/A";
    Map<String, Map<String, dynamic>> extensionsMap = {};

    if (result != null && result.exitCode == 0) {
      final rawOutput = result.stdout.toString();
      final lines = rawOutput.split('\n');

      for (var line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith("...")) continue;
        
        final lower = trimmed.toLowerCase();
        
        if (lower.contains("total snapshots:")) {
          commits = int.tryParse(RegExp(r'\d+').stringMatch(trimmed.split(':').last) ?? '') ?? 0;
        } else if (lower.contains("snapshot data:")) {
          size = trimmed.split(':').last.trim();
        } else if (lower.contains("growth trend:")) {
          growth = trimmed.split(':').last.trim();
        } else if (lower.contains("integrity coverage:")) {
          integrity = trimmed.split(':').last.trim();
        } else if (lower.contains("largest snapshot:")) {
          largest = trimmed.split(':').last.trim();
        }
        
        else if (lower.contains("files (") && (trimmed.startsWith(".") || trimmed.startsWith("no-ext"))) {
          try {
            final tokens = trimmed.split(RegExp(r'\s+'));
            
            if (tokens.isNotEmpty) {
              final ext = tokens.first;
              
              final filesIndex = tokens.indexOf("files");
              if (filesIndex > 0) {
                final count = int.tryParse(tokens[filesIndex - 1]) ?? 0;
                
                final segmentWithPct = trimmed.substring(trimmed.indexOf('(') + 1, trimmed.indexOf('%')).trim();
                final pct = double.tryParse(segmentWithPct) ?? 0.0;
                
                if (count > 0) {
                  extensionsMap[ext] = {
                    "count": count,
                    "percentage": pct
                  };
                  files += count;
                }
              }
            }
          } catch (e) {
            debugPrint("Error parsing distribution line: $e");
          }
        }
      }
    }

    setState(() {
      _parsedStats = {
        "totalCommits": commits == 0 ? _parsedLogs.length : commits,
        "filesTracked": files,
        "vaultSize": size,
        "growthTrend": growth,
        "integrityCoverage": integrity,
        "largestSnapshot": largest,
        "extensions": extensionsMap
      };
      _isProcessing = false;
    });
  }

  Future<void> _refreshVcsState() async {
    if (widget.rootPath == null) return;

    setState(() => _isProcessing = true);

    if (_tabController.index == 1) { await _fetchLogs(); return; }
    if (_tabController.index == 2) { await _fetchStats(); return; }

    final trackResult = await _runVcsCommand(["track", "current"]);
    if (trackResult != null && trackResult.exitCode == 0) {
      final output = trackResult.stdout.toString().trim();
      
      if (output.contains("Category") || output.isEmpty) {
        _currentBranch = "no vault";
      } else {
        final match = RegExp(r'Name:\s*([^\n\r]+)').firstMatch(output);
        if (match != null && match.group(1) != null) {
          _currentBranch = match.group(1)!.trim(); 
        } else {
          _currentBranch = output.split('\n').last.trim(); 
        }
      }
    } else {
      _currentBranch = "no vault";
    }

    final statusResult = await _runVcsCommand(["status"]);
    if (statusResult != null && statusResult.exitCode == 0) {
      final rawOutput = statusResult.stdout.toString();
      
      if (rawOutput.contains("Category") || rawOutput.contains("vcs status")) {
        if (rawOutput.contains("Category")) {
          setState(() { _modifiedFiles = []; });
          if (mounted) setState(() => _isProcessing = false);
          return;
        }
      }

      final lines = rawOutput.split('\n');
      List<File> tempFiles = [];
      
      for (var line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.startsWith("MOD ") || trimmedLine.startsWith("NEW ")) {
          final relativePath = trimmedLine.substring(4).trim();
          final absolutePath = p.join(widget.rootPath!, relativePath);
          final file = File(absolutePath);
          if (file.existsSync()) tempFiles.add(file);
        }
      }

      setState(() { _modifiedFiles = tempFiles; });
    } else {
      setState(() { _modifiedFiles = []; });
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  Future<void> _triggerPush() async {
    final password = _passwordController.text;
    final message = _messageController.text.trim();
    final author = _authorController.text.trim();

    if (message.isEmpty) {
      _showSnackBar("Please enter a snapshot message.");
      return;
    }
    if (password.isEmpty) {
      _showSnackBar("Please enter your password to perform the Push.");
      return;
    }

    setState(() => _isProcessing = true);
    
    final List<String> arguments = ["push", message];
    if (author.isNotEmpty) arguments.addAll(["-a", author]);

    final String complexStdin = "$password\ny\n";
    final result = await _runVcsCommand(arguments, writeToStdin: complexStdin);

    if (result != null && result.exitCode == 0) {
      final stdoutText = result.stdout.toString();
      if (stdoutText.contains("saved successfully") || stdoutText.contains("amended successfully")) {
        _showSnackBar('Snapshot pushed and saved successfully into your secure Vault!');
        _passwordController.clear();
        _messageController.clear(); 
        await _refreshVcsState(); 
      } else if (stdoutText.contains("No changes to save")) {
        _showSnackBar('ℹ️ No pending changes detected in the active track.');
      } else {
        _showSnackBar('Operation finalized.');
      }
    } else {
      final error = result?.stderr.toString().trim() ?? "Integrity failure or wrong credentials.";
      _showSnackBar('Push CLI Error: $error');
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  void _showSnackBar(String message) {
    final sidebarHex = widget.uiColors["sidebar"] ?? 0x111217;
    final tabActiveHex = widget.uiColors["tabActive"] ?? 0x1A1B26;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(fontSize: 12, color: Color(sidebarHex))),
        backgroundColor: Color(tabActiveHex),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color sidebarFg = Color(widget.uiColors["bgForeground"] ?? 0x111217);
    final Color sidebarBg = Color(widget.uiColors["sidebar"] ?? 0x111217);
    final Color elementBg = Color(widget.uiColors["bg"] ?? 0x1A1B26);
    final Color tabActiveBg = Color(widget.uiColors["tabActive"] ?? 0x1A1B26);
    final Color statusColor = Color(widget.uiColors["statusBar"] ?? 0x24283B);
    
    final Color primaryText = Colors.white;
    final Color secondaryText = primaryText.withOpacity(0.6);
    final Color mutedText = primaryText.withOpacity(0.35);

    if (widget.rootPath == null) {
      return Center(
        child: Text("No project workspace open", style: TextStyle(color: mutedText, fontSize: 13)),
      );
    }

    return Container(
      color: sidebarBg,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "SOURCE CONTROL",
                style: TextStyle(color: secondaryText, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              if (_isProcessing)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: statusColor),
                )
            ],
          ),
          const SizedBox(height: 10),

          Container(
            height: 28,
            decoration: BoxDecoration(color: elementBg, borderRadius: BorderRadius.circular(4)),
            child: TabBar(
              controller: _tabController,
              indicatorColor: statusColor,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: sidebarFg,
              unselectedLabelColor: sidebarFg,
              labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: "CHANGES"),
                Tab(text: "HISTORY"),
                Tab(text: "STATS"),
                Tab(text: "PULL",)
              ],
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildChangesTab(primaryText, secondaryText, mutedText, elementBg, tabActiveBg, statusColor, sidebarFg),
                _buildHistoryTab(primaryText, secondaryText, mutedText, elementBg, statusColor, sidebarFg),
                _buildStatsTab(primaryText, secondaryText, mutedText, elementBg, statusColor, sidebarFg),
                _buildPullTab(primaryText, secondaryText, mutedText, elementBg, tabActiveBg, statusColor, sidebarFg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangesTab(Color primaryText, Color secondaryText, Color mutedText, Color elementBg, Color tabActiveBg, Color statusColor, Color sidebarFg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: elementBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: primaryText.withOpacity(0.05), width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.alt_route, size: 13, color: sidebarFg),
              const SizedBox(width: 6),
              Text(
                _currentBranch,
                style: TextStyle(color: sidebarFg.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.download, size: 13, color: sidebarFg),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _isProcessing ? null : () => _executePull(null, "latest"),
                tooltip: "Pull Latest Snapshot",
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.refresh, size: 13, color: sidebarFg),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _isProcessing ? null : _refreshVcsState,
                tooltip: "Refresh Changes",
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text("CHANGES", style: TextStyle(color: sidebarFg, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Expanded(
          child: _modifiedFiles.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Text(
                    "No local modifications detected.",
                    style: TextStyle(color: sidebarFg, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                )
              : ListView.builder(
                  itemCount: _modifiedFiles.length,
                  itemBuilder: (context, index) {
                    final file = _modifiedFiles[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -3),
                      leading: Icon(Icons.description_outlined, size: 14, color: sidebarFg),
                      title: Text(p.basename(file.path), style: TextStyle(color: sidebarFg, fontSize: 12)),
                      subtitle: Text(
                        p.relative(file.path, from: widget.rootPath),
                        style: TextStyle(color: sidebarFg, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text("M", style: TextStyle(color: sidebarFg, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      onTap: () => widget.onFileTap(file),
                    );
                  },
                ),
        ),
        Divider(color: primaryText.withOpacity(0.08), height: 16),
        Text("SNAPSHOT PROPERTIES", style: TextStyle(color: sidebarFg, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _messageController,
          style: TextStyle(color: sidebarFg, fontSize: 12),
          cursorColor: statusColor,
          decoration: InputDecoration(
            hintText: "Snapshot message (Required)...",
            hintStyle: TextStyle(color: sidebarFg, fontSize: 11),
            filled: true,
            fillColor: tabActiveBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: primaryText.withOpacity(0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: statusColor),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _authorController,
          style: TextStyle(color: sidebarFg, fontSize: 12),
          cursorColor: statusColor,
          decoration: InputDecoration(
            hintText: "Author: Name <email> (Optional)...",
            hintStyle: TextStyle(color: sidebarFg, fontSize: 11),
            filled: true,
            fillColor: tabActiveBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: primaryText.withOpacity(0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: statusColor),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text("SECURITY BOUND", style: TextStyle(color: sidebarFg, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(color: sidebarFg, fontSize: 12),
          cursorColor: statusColor,
          decoration: InputDecoration(
            hintText: "Vault encryption key...",
            hintStyle: TextStyle(color: sidebarFg, fontSize: 11),
            filled: true,
            fillColor: tabActiveBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: primaryText.withOpacity(0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: statusColor),
            ),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 13, color: secondaryText),
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onSubmitted: (_) => _triggerPush(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 30,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: statusColor,
              foregroundColor: primaryText,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            icon: const Icon(Icons.lock_outline, size: 12), 
            label: const Text("Push Encrypted", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: _isProcessing ? null : _triggerPush,
          ),
        ),
      ],
    );
  }

  void _executePull(String? fullId, String shortId) async {
    final String vaultPassword = _pullPasswordController.text.trim();

    if (vaultPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Vault encryption key is required to pull and decrypt snapshots."),
          backgroundColor: Colors.amber.withOpacity(0.3),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);
    ProcessResult? result;
    
    try {
      if (fullId == null) {
        if (Platform.isWindows) {
          result = await Process.run('cmd.exe', [
            '/c', 
            '(echo y && echo $vaultPassword) | vcs pull'
          ]);
        } else {
          result = await Process.run('sh', [
            '-c', 
            'echo -e "y\\n$vaultPassword" | vcs pull'
          ]);
        }
      } else {
        final String idClean = fullId.trim();
        if (Platform.isWindows) {
          result = await Process.run('cmd.exe', [
            '/c', 
            '(echo y && echo $vaultPassword) | vcs pull --id $idClean'
          ]);
        } else {
          result = await Process.run('sh', [
            '-c', 
            'echo -e "y\\n$vaultPassword" | vcs pull --id $idClean'
          ]);
        }
      }
    } catch (e) {
      debugPrint("Error executing VCS pull: $e");
    }

    setState(() => _isProcessing = false);

    if (result != null && result.exitCode == 0) {
      _pullIdController.clear();
      _refreshVcsState(); 
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fullId == null 
              ? "Workspace synchronized and decrypted with latest snapshot." 
              : "Project successfully rolled back and decrypted to snapshot $shortId."),
          backgroundColor: Colors.green.withOpacity(0.2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Pull failed: ${result?.stderr ?? 'Unknown error'}\n${result?.stdout ?? ''}"),
          backgroundColor: Colors.red.withOpacity(0.2),
        ),
      );
    }
  }

  void _loadPullLogs() async {
    try {
      await _fetchLogs(); 
      
      setState(() {
        _pullLogs = _parsedLogs; 
      });
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  Widget _buildPullTab(Color primaryText, Color secondaryText, Color mutedText, Color elementBg, Color tabActiveBg, Color statusColor, Color sidebarFg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: elementBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: primaryText.withOpacity(0.05), width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.sync_alt, size: 13, color: sidebarFg),
              const SizedBox(width: 6),
              Text(
                "SYNC WORKSPACE ON: ",
                style: TextStyle(color: sidebarFg, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              Text(
                _currentBranch,
                style: TextStyle(color: sidebarFg, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Text("LATEST SNAPSHOT SYNC", style: TextStyle(color: sidebarFg, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          "Synchronize and update your editor with the last state saved in the local repository of this track.",
          style: TextStyle(color: sidebarFg, fontSize: 11),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 32,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: elementBg,
              foregroundColor: sidebarFg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: primaryText.withOpacity(0.1)),
              ),
            ),
            icon: Icon(Icons.download_rounded, size: 14, color: sidebarFg), 
            label: const Text("Pull Latest Snapshot", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            onPressed: _isProcessing ? null : () => _executePull(null, "latest"),
          ),
        ),

        const SizedBox(height: 16),
        Divider(color: sidebarFg.withOpacity(0.08), height: 16),
        const SizedBox(height: 8),

        Text("RESTORE SPECIFIC SNAPSHOT", style: TextStyle(color: sidebarFg, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          "Forces the workbench to go back in time to a specific Snapshot using its unique identifier.",
          style: TextStyle(color: sidebarFg, fontSize: 11),
        ),
        const SizedBox(height: 10),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _pullIdController,
              style: TextStyle(color: sidebarFg, fontSize: 11, fontFamily: 'monospace'),
              cursorColor: statusColor,
              onTap: () {
                setState(() => _showIdSuggestions = true);
                _loadPullLogs();
              },
              onChanged: (value) {
                if (!_showIdSuggestions) setState(() => _showIdSuggestions = true);
              },
              decoration: InputDecoration(
                hintText: "Enter or select full Snapshot ID...",
                hintStyle: TextStyle(color: sidebarFg, fontSize: 11, fontFamily: 'sans-serif'),
                filled: true,
                fillColor: tabActiveBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: primaryText.withOpacity(0.05)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: statusColor),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showIdSuggestions ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, 
                    size: 14, 
                    color: sidebarFg
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    setState(() => _showIdSuggestions = !_showIdSuggestions);
                    if (_showIdSuggestions) _loadPullLogs();
                  },
                ),
              ),
            ),
            
            if (_showIdSuggestions && _pullLogs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  maxHeight: 130, 
                ),
                decoration: BoxDecoration(
                  color: elementBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: primaryText.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _pullLogs.length,
                    itemBuilder: (context, index) {
                      final log = _pullLogs[index];
                      final String snapId = log['id'] ?? '';
                      final String msg = log['message'] ?? 'No message';
                      final String shortId = snapId.length >= 7 ? snapId.substring(0, 13) : snapId;

                      final query = _pullIdController.text.trim().toLowerCase();
                      if (query.isNotEmpty && !snapId.toLowerCase().contains(query) && !msg.toLowerCase().contains(query)) {
                        return const SizedBox.shrink();
                      }

                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -3),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          title: Text(
                            msg,
                            style: TextStyle(color: sidebarFg, fontSize: 11, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            "ID: $shortId",
                            style: TextStyle(color: sidebarFg, fontSize: 10, fontFamily: 'monospace'),
                          ),
                          onTap: () {
                            setState(() {
                              _pullIdController.text = snapId; 
                              _showIdSuggestions = false;     
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ] else if (_showIdSuggestions && _pullLogs.isEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.all(6.0),
                child: Text(
                  "Loading available snapshots from VCS...",
                  style: TextStyle(color: sidebarFg, fontSize: 10, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        SizedBox(
          width: double.infinity,
          height: 32,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: elementBg.withOpacity(0.15),
              foregroundColor: sidebarFg,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            icon: const Icon(Icons.history_toggle_off_rounded, size: 14), 
            label: const Text("Pull & Restore ID", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: _isProcessing 
                ? null 
                : () {
                    final targetId = _pullIdController.text.trim();
                    if (targetId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please enter a valid Snapshot ID.")),
                      );
                      return;
                    }
                    final shortStr = targetId.length >= 7 ? targetId.substring(0, 7) : targetId;
                    _executePull(targetId, shortStr);
                  },
          ),
        ),
        
        const SizedBox(height: 16),
        Divider(color: sidebarFg.withOpacity(0.08), height: 16),
        const SizedBox(height: 8),

        Text("SECURITY DECRYPTION BOUND", style: TextStyle(color: sidebarFg, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _pullPasswordController,
          obscureText: _obscurePullPassword,
          style: TextStyle(color: sidebarFg, fontSize: 12),
          cursorColor: statusColor,
          decoration: InputDecoration(
            hintText: "Vault decryption key...",
            hintStyle: TextStyle(color: sidebarFg, fontSize: 11),
            filled: true,
            fillColor: tabActiveBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: primaryText.withOpacity(0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: statusColor),
            ),
            suffixIcon: IconButton(
              icon: Icon(_obscurePullPassword ? Icons.visibility_off : Icons.visibility, size: 13, color: secondaryText),
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _obscurePullPassword = !_obscurePullPassword),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(Color primaryText, Color secondaryText, Color mutedText, Color elementBg, Color statusColor, Color sidebarFg) {
    if (_parsedLogs.isEmpty) {
      return Center(
        child: Text(
          "No snapshot logs found.",
          style: TextStyle(color: sidebarFg, fontSize: 12, fontStyle: FontStyle.italic),
        ),
      );
    }

    return ListView.builder(
      itemCount: _parsedLogs.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final log = _parsedLogs[index];
        
        final List<Map<String, String>> files = log["files"] != null 
            ? List<Map<String, String>>.from(
                (log["files"] as List).map((e) => Map<String, String>.from(e as Map)))
            : [];

        final Map<String, int> categories = log["categories"] != null
            ? Map<String, int>.from(log["categories"] as Map)
            : {};

        final String snapshotId = (log["id"] as String?) ?? "";
        final String shortId = (log["shortId"] as String?) ?? "???????";

        return GestureDetector(
          onSecondaryTapUp: (details) {
            final offset = details.globalPosition;
            
            showMenu(
              context: context,
              position: RelativeRect.fromLTRB(
                offset.dx,
                offset.dy,
                offset.dx + 1,
                offset.dy + 1,
              ),
              color: elementBg,
              elevation: 8,
              items: [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        "Delete Snapshot $shortId", 
                        style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)
                      ),
                    ],
                  ),
                ),
              ],
            ).then((value) {
              if (value == 'delete' && snapshotId.isNotEmpty) {
                _deleteSnapshot(snapshotId, shortId);
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 2.0),
            decoration: BoxDecoration(
              color: secondaryText,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: primaryText.withOpacity(0.04)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                clipBehavior: Clip.antiAlias,
                iconColor: sidebarFg,
                collapsedIconColor: sidebarFg,
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        shortId,
                        style: TextStyle(
                          color: sidebarFg,
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (log["message"] as String?)?.isNotEmpty == true ? log["message"] as String : "No message",
                        style: TextStyle(color: sidebarFg, fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "by ${(log["author"] as String?) ?? 'Unknown'}",
                        style: TextStyle(color: sidebarFg, fontSize: 10),
                      ),
                      Text(
                        (log["date"] as String?) ?? "",
                        style: TextStyle(color: sidebarFg, fontSize: 9),
                      ),
                    ],
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: sidebarFg.withOpacity(0.06), height: 10),
                        
                        if ((log["changesSummary"] as String?)?.isNotEmpty == true) ...[
                          Text(
                            "Summary: ${log["changesSummary"]}",
                            style: TextStyle(color: sidebarFg, fontSize: 10, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                        ],

                        if (categories.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: categories.entries.map((entry) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: primaryText.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: primaryText.withOpacity(0.02)),
                                ),
                                child: Text(
                                  "${entry.key}: ${entry.value}",
                                  style: TextStyle(color: sidebarFg.withOpacity(0.8), fontSize: 9),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                        ],

                        Text(
                          "AFFECTED FILES (${files.length})",
                          style: TextStyle(color: sidebarFg, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 4),

                        Container(
                          constraints: BoxConstraints(maxHeight: files.length > 8 ? 220 : double.infinity),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: files.length,
                            itemBuilder: (context, fileIdx) {
                              final file = files[fileIdx];
                              final status = file["status"] ?? "M";
                              
                              Color statusColorTag = Colors.amber; 
                              String statusLetter = "M";
                              if (status == "N") { statusColorTag = Colors.green; statusLetter = "A"; }
                              if (status == "D") { statusColorTag = Colors.red; statusLetter = "D"; }

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      child: Text(
                                        statusLetter,
                                        style: TextStyle(color: statusColorTag, fontWeight: FontWeight.bold, fontSize: 10, fontFamily: 'monospace'),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        file["path"] ?? "",
                                        style: TextStyle(color: sidebarFg.withOpacity(0.85), fontSize: 11, fontFamily: 'monospace'),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _deleteSnapshot(String fullId, String shortId) async {
    setState(() => _isProcessing = true);

    ProcessResult? result;
    final String idClean = fullId.trim();

    try {
      if (Platform.isWindows) {
        result = await Process.run('cmd.exe', [
          '/c', 
          'echo y | vcs prune --id $idClean'
        ]);
      } else {
        result = await Process.run('sh', [
          '-c', 
          'echo y | vcs prune --id $idClean'
        ]);
      }
    } catch (e) {
      debugPrint("Error executing the deletion process: $e");
    }

    setState(() => _isProcessing = false);

    if (result != null && result.exitCode == 0) {
      _fetchLogs(); 
      if (mounted) _fetchStats();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Snapshot $shortId successfully pruned."),
          backgroundColor: Colors.green.withOpacity(0.2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error pruning snapshot: ${result?.stderr ?? 'Unknown error'}"),
          backgroundColor: Colors.red.withOpacity(0.2),
        ),
      );
    }
  }

  Widget _buildStatsTab(Color primaryText, Color secondaryText, Color mutedText, Color elementBg, Color statusColor, Color sidebarFg) {
    final extensions = (_parsedStats["extensions"] as Map<String, dynamic>?) ?? {};

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.2,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildStatCard("Snapshots", (_parsedStats["totalCommits"] ?? 0).toString(), Icons.history, elementBg, statusColor, primaryText, mutedText, sidebarFg),
              _buildStatCard("Tracked Files", (_parsedStats["filesTracked"] ?? 0).toString(), Icons.folder_zip_outlined, elementBg, statusColor, primaryText, mutedText, sidebarFg),
            ],
          ),
          const SizedBox(height: 8),
          _buildStatCard("Vault Size on Disk", (_parsedStats["vaultSize"] ?? "0 GB").toString(), Icons.sd_storage_outlined, elementBg, statusColor, primaryText, mutedText, sidebarFg, isWide: true),
          
          const SizedBox(height: 16),
          Text("PREDICTIVE & HEALTH METRICS", style: TextStyle(color: sidebarFg, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: elementBg, borderRadius: BorderRadius.circular(4)),
            child: Column(
              children: [
                _buildStatDetailRow("Growth Trend", _parsedStats["growthTrend"] ?? "N/A", primaryText, secondaryText, sidebarFg),
                Divider(color: primaryText.withOpacity(0.04), height: 12),
                _buildStatDetailRow("Integrity Coverage", _parsedStats["integrityCoverage"] ?? "N/A", primaryText, secondaryText, sidebarFg),
                Divider(color: primaryText.withOpacity(0.04), height: 12),
                _buildStatDetailRow("Largest Snapshot", _parsedStats["largestSnapshot"] ?? "N/A", primaryText, secondaryText, sidebarFg),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Text("FILE DISTRIBUTION", style: TextStyle(color: sidebarFg, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),

          if (extensions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text("No extension telemetry detected.", style: TextStyle(color: sidebarFg, fontSize: 11, fontStyle: FontStyle.italic)),
            )
          else
            ...extensions.entries.map((entry) {
              final data = entry.value as Map<String, dynamic>;
              final int count = data["count"] ?? 0;
              final double pctValue = data["percentage"] ?? 0.0;
              final double progressValue = pctValue / 100.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                key: ValueKey(entry.key),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key, style: TextStyle(color: sidebarFg, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                        Text("$count files (${pctValue.toStringAsFixed(1)}%)", style: TextStyle(color: sidebarFg, fontSize: 10, fontFamily: 'monospace')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 5,
                        backgroundColor: primaryText.withOpacity(0.03),
                        valueColor: AlwaysStoppedAnimation<Color>(sidebarFg),
                      ),
                    )
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildStatDetailRow(String label, String value, Color pText, Color sText, Color sFg) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: sFg, fontSize: 11)),
        Text(value, style: TextStyle(color: sFg, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color bg, Color accent, Color pText, Color mText, Color sFg, {bool isWide = false}) {
    return Container(
      width: isWide ? double.infinity : null,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: TextStyle(color: sFg, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                Text(label, style: TextStyle(color: sFg, fontSize: 9), overflow: TextOverflow.ellipsis),
              ],
            ),
          )
        ],
      ),
    );
  }
}
