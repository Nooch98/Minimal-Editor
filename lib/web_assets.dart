class WebAssets {
  static const String htmlContent = '''
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <style>
        body, html { margin: 0; padding: 0; height: 100%; width: 100%; overflow: hidden; background-color: #1e1e1e; }
        #container { width: 100%; height: 100%; }
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

            window.editor.onDidChangeCursorPosition((e) => {
                if (window.flutter_inappwebview) {
                    window.flutter_inappwebview.callHandler('onCursorChanged', {
                        line: e.position.lineNumber,
                        column: e.position.column
                    });
                }
            });

            window.editor.onDidChangeModelDecorations(() => {
                if (window.flutter_inappwebview) {
                    const markers = monaco.editor.getModelMarkers({});
                    window.flutter_inappwebview.callHandler('onMarkersChanged', markers.length);
                }
            });

            while(window.pendingQueue.length > 0) {
                window.pendingQueue.shift()();
            }

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

        window.setEditorValue = function(data) {
          if (!window.isEditorReady) {
              window.pendingQueue.push(() => window.setEditorValue(data));
              return;
          }
          if (!window.editor) return;

          let language = data.lang;
          
          const languageMap = {
            'js': 'javascript', 'ts': 'typescript', 'yml': 'yaml', 'yaml': 'yaml',
            'md': 'markdown', 'ps1': 'powershell', 'py': 'python', 'pyw': 'python',
            'rb': 'ruby', 'cs': 'csharp', 'cpp': 'cpp', 'c': 'c', 'h': 'cpp',
            'java': 'java', 'php': 'php', 'html': 'html', 'htm': 'html',
            'css': 'css', 'scss': 'scss', 'less': 'less', 'json': 'json',
            'xml': 'xml', 'sql': 'sql', 'sh': 'shell', 'bash': 'shell',
            'bat': 'bat', 'go': 'go', 'rs': 'rust', 'kt': 'kotlin',
            'ktm': 'kotlin', 'swift': 'swift', 'dart': 'dart'
          };
          
          if (languageMap[language]) {
              language = languageMap[language];
          }

          var newModel = monaco.editor.createModel(data.code, language);
          
          newModel.onDidChangeContent(function(e) {
              if (window.flutter_inappwebview) {
                  window.flutter_inappwebview.callHandler('onContentChanged');
              }
          });

          var oldModel = window.editor.getModel();
          window.editor.setModel(newModel);
          
          if (oldModel) oldModel.dispose();
        };

        window.defineCustomTheme = function(themeName, themeJson) {
            if (typeof monaco !== 'undefined') {
                monaco.editor.defineTheme(themeName, themeJson);
                monaco.editor.setTheme(themeName);
            } else {
                console.warn("Monaco isn't ready yet, still waiting...");
                setTimeout(() => window.defineCustomTheme(themeName, themeJson), 500);
            }
        };

        window.setEditorOptions = function(options) {
            if (window.editor) {
                window.editor.updateOptions(options);
            } else {
                setTimeout(() => window.setEditorOptions(options), 200);
            }
        };
    </script>
</body>
</html>
  ''';
}
