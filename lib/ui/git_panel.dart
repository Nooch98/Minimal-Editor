import 'dart:io';
import 'package:flutter/material.dart';

class GitPanel extends StatefulWidget {
  final String? rootPath;
  final Map<String, dynamic> uiColors;

  const GitPanel({
    Key? key,
    required this.rootPath,
    required this.uiColors,
  }) : super(key: key);

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  final TextEditingController _commitMessageController = TextEditingController();
  bool _isGitProcessing = false;
  String _currentGitBranch = "Unknown";
  String _gitStatusText = "No repository detected or folder not opened.";
  List<String> _changedFiles = [];

  @override
  void initState() {
    super.initState();
    _refreshGitStatus();
  }

  @override
  void didUpdateWidget(covariant GitPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      _refreshGitStatus();
    }
  }

  Future<ProcessResult?> _runGitCommand(List<String> args) async {
    if (widget.rootPath == null) return null;
    try {
      return await Process.run('git', args, workingDirectory: widget.rootPath);
    } catch (e) {
      debugPrint("Error running git command: $e");
      return null;
    }
  }

  Future<void> _refreshGitStatus() async {
    if (widget.rootPath == null) return;

    setState(() => _isGitProcessing = true);

    final branchResult = await _runGitCommand(['branch', '--show-current']);
    String branch = "Detached / Unknown";
    if (branchResult != null && branchResult.exitCode == 0) {
      branch = branchResult.stdout.toString().trim();
      if (branch.isEmpty) branch = "Main/Master";
    }

    final statusResult = await _runGitCommand(['status', '--short']);
    List<String> files = [];
    String statusSummary = "Your workspace is clean.";

    if (statusResult != null && statusResult.exitCode == 0) {
      final output = statusResult.stdout.toString().trim();
      if (output.isNotEmpty) {
        files = output.split('\n');
        statusSummary = "${files.length} file(s) with pending changes.";
      }
    } else {
      statusSummary = "Error reading status or Git not initialized.";
    }

    setState(() {
      _currentGitBranch = branch;
      _changedFiles = files;
      _gitStatusText = statusSummary;
      _isGitProcessing = false;
    });
  }

  Future<void> _executeGitAction(String action, List<String> args) async {
    setState(() => _isGitProcessing = true);
    
    final result = await _runGitCommand(args);
    
    setState(() => _isGitProcessing = false);

    if (result != null && result.exitCode == 0) {
      _showSnackBar("Git $action executed successfully.");
      _refreshGitStatus();
    } else {
      final errorMsg = result?.stderr.toString() ?? "Unknown terminal error";
      _showSnackBar("Git $action failed: ${errorMsg.trim()}", isError: true);
    }
  }

  Future<void> _handleCommit() async {
    final msg = _commitMessageController.text.trim();
    if (msg.isEmpty) {
      _showSnackBar("Please enter a commit message.", isError: true);
      return;
    }

    setState(() => _isGitProcessing = true);

    final addRes = await _runGitCommand(['add', '.']);
    if (addRes != null && addRes.exitCode == 0) {
      final commitRes = await _runGitCommand(['commit', '-m', msg]);
      if (commitRes != null && commitRes.exitCode == 0) {
        _showSnackBar("Commit created successfully!");
        _commitMessageController.clear();
      } else {
        _showSnackBar("Commit failed: ${commitRes?.stderr}", isError: true);
      }
    } else {
      _showSnackBar("Failed to stage files.", isError: true);
    }

    _refreshGitStatus();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 11, color: Colors.white)),
        backgroundColor: isError ? Colors.redAccent.withOpacity(0.8) : Colors.green.withOpacity(0.8),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryText = Color(widget.uiColors["sidebarForeground"] ?? 0xFFFFFFFF);
    final Color secondaryText = primaryText.withOpacity(0.65);
    final Color mutedText = primaryText.withOpacity(0.4);
    final Color elementBg = Color(widget.uiColors["bg"] ?? 0xFF1E1E1E);
    final Color inputBg = Color(widget.uiColors["activityBar"] ?? 0xFF333333);
    final Color accentColor = const Color(0xFF4D78CC);

    if (widget.rootPath == null) {
      return Center(
        child: Text(
          "Open a workspace folder\nto initialize Git management.",
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedText, fontSize: 11, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "GIT SOURCE CONTROL",
                style: TextStyle(color: primaryText, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 14, color: secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _isGitProcessing ? null : _refreshGitStatus,
              )
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: elementBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: primaryText.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Icon(Icons.hub_rounded, size: 12, color: accentColor),
                const SizedBox(width: 6),
                Text("BRANCH: ", style: TextStyle(color: mutedText, fontSize: 10, fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    _currentGitBranch,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                ),
                if (_isGitProcessing)
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
                  )
              ],
            ),
          ),
          const SizedBox(height: 12),

          Text(
            _gitStatusText.toUpperCase(),
            style: TextStyle(color: secondaryText, fontSize: 9, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 10),

          if (_changedFiles.isNotEmpty) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: elementBg.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _changedFiles.length,
                  itemBuilder: (context, index) {
                    final line = _changedFiles[index];
                    if (line.length < 3) return const SizedBox.shrink();
                    final statusSymbol = line.substring(0, 2);
                    final filePath = line.substring(2).trim();

                    Color statusColor = Colors.amber;
                    if (statusSymbol.contains('M')) statusColor = Colors.amber;
                    if (statusSymbol.contains('A') || statusSymbol.contains('?')) statusColor = Colors.green;
                    if (statusSymbol.contains('D')) statusColor = Colors.redAccent;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      child: Row(
                        children: [
                          Text(
                            statusSymbol.trim(),
                            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              filePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: primaryText.withOpacity(0.8), fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            const Spacer(),
          ],

          Text("STAGING & COMMIT", style: TextStyle(color: mutedText, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _commitMessageController,
            maxLines: 2,
            style: TextStyle(color: primaryText, fontSize: 11),
            cursorColor: accentColor,
            decoration: InputDecoration(
              hintText: "Commit message (Stages all changes...)",
              hintStyle: TextStyle(color: mutedText, fontSize: 10),
              filled: true,
              fillColor: inputBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: primaryText.withOpacity(0.05)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: accentColor),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 28,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor.withOpacity(0.15),
                foregroundColor: accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              icon: const Icon(Icons.check, size: 12),
              label: const Text("Stage & Commit", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              onPressed: _isGitProcessing ? null : _handleCommit,
            ),
          ),

          const SizedBox(height: 12),
          Divider(color: primaryText.withOpacity(0.08), height: 1),
          const SizedBox(height: 12),

          Text("REMOTE REPOSITORY SYNC", style: TextStyle(color: mutedText, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryText,
                      side: BorderSide(color: primaryText.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      backgroundColor: elementBg,
                    ),
                    icon: Icon(Icons.download, size: 13, color: secondaryText),
                    label: const Text("Pull", style: TextStyle(fontSize: 11)),
                    onPressed: _isGitProcessing ? null : () => _executeGitAction("Pull", ['pull']),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryText,
                      side: BorderSide(color: primaryText.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      backgroundColor: elementBg,
                    ),
                    icon: Icon(Icons.upload, size: 13, color: secondaryText),
                    label: const Text("Push", style: TextStyle(fontSize: 11)),
                    onPressed: _isGitProcessing ? null : () => _executeGitAction("Push", ['push']),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}