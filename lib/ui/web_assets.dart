class WebAssets {
  static const String htmlContent = '''
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <style>
        body, html { margin: 0; padding: 0; height: 100%; width: 100%; overflow: hidden; background-color: #1e1e1e; }
        #container { width: 100%; height: 100%; }
        .monaco-editor .ghost-text-style {
            color: #888888 !important;
            font-style: italic !important;
            opacity: 0.7 !important;
            pointer-events: none !important;
            padding-left: 0px !important;
            background-color: transparent !important;
        }
    </style>
</head>
<body>
    <div id="container"></div>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.44.0/min/vs/loader.min.js"></script>
    <script>
        require.config({ paths: { 'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.44.0/min/vs' }});
        window.editor = null;
        window.isEditorReady = false;
        window.pendingQueue = [];
        window.isSettingsFile = false; 
        let cursorTimeout = null;
        let completionTimeout = null;
        let ghostTextDecoration = [];
        let currentGhostText = "";
        
        window.editorModels = {};

        require(['vs/editor/editor.main'], function() {
            window.editor = monaco.editor.create(document.getElementById('container'), {
                value: '// IDE Ready...',
                language: 'dart',
                theme: 'vs-dark',
                automaticLayout: true
            });

            window.isEditorReady = true;

            if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('onEditorReady');
            }

            while(window.pendingQueue.length > 0) {
                window.pendingQueue.shift()();
            }

            window.applyGhostText = function(text) {
                if (!window.editor) return;
                window.currentGhostText = text;
                const position = window.editor.getPosition();
                
                if (!text) {
                    window.ghostTextDecoration = window.editor.deltaDecorations(window.ghostTextDecoration, []);
                    return;
                }

                const firstLine = text.split('\\n')[0];

                window.ghostTextDecoration = window.editor.deltaDecorations(window.ghostTextDecoration, [
                    {
                        range: new monaco.Range(position.lineNumber, position.column, position.lineNumber, position.column),
                        options: {
                            isWholeLine: false,
                            afterContentClassName: 'ghost-text-style',
                            after: { 
                                content: firstLine
                            }
                        }
                    }
                ]);
            };

            window.editor.onDidChangeModelContent((e) => {
                if (e.changes.length > 0 && e.changes[0].text === "") {
                    window.applyGhostText("");
                    currentGhostText = "";
                }

                if (completionTimeout) clearTimeout(completionTimeout);
                
                completionTimeout = setTimeout(() => {
                  const position = window.editor.getPosition();
                  const model = window.editor.getModel();
                  const maxLines = 50; 
                  const startLine = Math.max(1, position.lineNumber - maxLines);
                  const endLine = Math.min(model.getLineCount(), position.lineNumber + maxLines);
                  const codeBefore = model.getValueInRange(new monaco.Range(startLine, 1, position.lineNumber, position.column));
                  const codeAfter = model.getValueInRange(new monaco.Range(position.lineNumber, position.column, endLine, model.getLineMaxColumn(endLine)));
                  if (window.flutter_inappwebview) {
                      window.flutter_inappwebview.callHandler('requestCompletion', {
                          codeBefore: codeBefore,
                          codeAfter: codeAfter
                      });
                  }
                }, 800);
            });

            window.editor.addCommand(monaco.KeyCode.Tab, function() {
                if (currentGhostText !== "") {
                    const position = window.editor.getPosition();
                    window.editor.executeEdits("ghost-text", [{
                        range: new monaco.Range(position.lineNumber, position.column, position.lineNumber, position.column),
                        text: currentGhostText
                    }]);
                    window.applyGhostText(""); 
                    currentGhostText = "";
                } else {
                    window.editor.trigger('keyboard', 'tab', null);
                }
            }, '');

            window.editor.onDidChangeCursorPosition((e) => {
                window.applyGhostText(""); 
                currentGhostText = "";
                if (cursorTimeout) clearTimeout(cursorTimeout);
                cursorTimeout = setTimeout(() => {
                    if (window.flutter_inappwebview) {
                        window.flutter_inappwebview.callHandler('onCursorChanged', {
                            line: e.position.lineNumber,
                            column: e.position.column
                        });
                    }
                }, 50);
            });

            window.editor.onDidChangeModelDecorations(() => {
                if (window.flutter_inappwebview) {
                    const markers = monaco.editor.getModelMarkers({});
                    window.flutter_inappwebview.callHandler('onMarkersChanged', markers.length);
                }
            });

            window.editor.onKeyDown(function(e) {
                if ((e.ctrlKey || e.metaKey) && e.keyCode === monaco.KeyCode.KeyC) {
                    setTimeout(function() {
                        var selectedText = window.editor.getModel().getValueInRange(window.editor.getSelection());
                        if (selectedText && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                            window.flutter_inappwebview.callHandler('onTextCopied', selectedText);
                        }
                    }, 10);
                }
            });

            window.addEventListener('keydown', function(e) {
                if ((e.ctrlKey || e.metaKey) && e.keyCode == 83) {
                    e.preventDefault();
                    if (window.flutter_inappwebview) {
                        window.flutter_inappwebview.callHandler('onSaveCommand');
                    }
                }
            });

            window.dispatchEvent(new CustomEvent('editorReady'));
        });

        window.updateTheme = function(themeName) {
            if (window.editor) monaco.editor.setTheme(themeName);
        };

        window.setEditorValue = function(data) {
            if (!window.isEditorReady) {
                window.pendingQueue.push(() => window.setEditorValue(data));
                return;
            }
            if (!window.editor) return;
            window.isSettingsFile = (data.fileName === 'settings.json');
            const fileId = data.filePath || data.fileName;
            let language = data.lang;
            const languageMap = { 'js': 'javascript', 'ts': 'typescript', 'yml': 'yaml', 'dart': 'dart', 'json': 'json' };
            if (languageMap[language]) language = languageMap[language];

            if (!window.editorModels[fileId]) {
                const modelUri = monaco.Uri.file(fileId);
                const newModel = monaco.editor.createModel(data.code, language, modelUri);
                newModel.onDidChangeContent(function(e) {
                    if (window.flutter_inappwebview) {
                        window.flutter_inappwebview.callHandler('onContentChanged');
                        if (window.isSettingsFile) {
                            try { const config = JSON.parse(window.editor.getValue()); window.flutter_inappwebview.callHandler('onSettingsChanged', config); } catch (err) {}
                        }
                    }
                });
                window.editorModels[fileId] = newModel;
            }
            window.editor.setModel(window.editorModels[fileId]);
        };

        window.closeEditorModel = function(filePath) {
            if (window.editorModels[filePath]) {
                window.editorModels[filePath].dispose();
                delete window.editorModels[filePath];
            }
        };
        
        window.defineCustomTheme = function(themeName, themeJson) {
            if (typeof monaco !== 'undefined') {
                monaco.editor.defineTheme(themeName, themeJson);
                monaco.editor.setTheme(themeName);
            } else {
                setTimeout(() => window.defineCustomTheme(themeName, themeJson), 500);
            }
        };

        window.setEditorOptions = (options) => {
            if (window.editor) window.editor.updateOptions(options);
            else setTimeout(() => window.setEditorOptions(options), 200);
        };
    </script>
</body>
</html>
  ''';
}
