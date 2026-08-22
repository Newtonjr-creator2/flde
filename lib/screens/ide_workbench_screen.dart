import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:path/path.dart' as p;

import '../core/runtime/environment_manager.dart';
import '../core/runtime/native_runtime_environment.dart';
import '../core/storage/storage_service.dart';
import '../services/file_service.dart';
import '../services/terminal_service.dart';
import 'toolchains_screen.dart';

/// FLDE's main workbench.
///
/// VS-Code-style mobile workbench containing:
/// - Activity bar
/// - Explorer
/// - Editor tabs
/// - Monaco editor
/// - Integrated terminal
/// - Status bar
class IdeWorkbenchScreen extends StatefulWidget {
  final String rootPath;

  const IdeWorkbenchScreen({
    super.key,
    required this.rootPath,
  });

  @override
  State<IdeWorkbenchScreen> createState() => _IdeWorkbenchScreenState();
}

class _OpenDocument {
  final String path;
  final String text;
  final MonacoLanguage language;

  bool dirty = false;

  _OpenDocument({
    required this.path,
    required this.text,
    required this.language,
  });
}

class _IdeWorkbenchScreenState extends State<IdeWorkbenchScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  final Map<String, _OpenDocument> _documents =
      <String, _OpenDocument>{};

  final List<String> _tabs = <String>[];

  String? _activePath;

  MonacoController? _monaco;

  bool _sidebarVisible = true;
  bool _terminalVisible = false;
  bool _explorerLoading = false;

  List<FileSystemEntity> _entries = <FileSystemEntity>[];

  late String _directory;

  TerminalSession? _terminal;

  final TextEditingController _terminalController =
      TextEditingController();

  final ScrollController _terminalScroll =
      ScrollController();

  StreamSubscription<TerminalHistoryEntry>? _terminalSub;

  @override
  void initState() {
    super.initState();

    _directory = widget.rootPath;

    _refreshExplorer();
    _initTerminal();
  }

  Future<void> _initTerminal() async {
    final storage = await StorageService.instance();

    final environment = EnvironmentManager(storage);

    final runtime = NativeRuntimeEnvironment(
      managedRoot: storage.root,
    );

    final session = TerminalSession(
      environment: environment,
      runtime: runtime,
      workingDirectory: widget.rootPath,
    );

    _terminalSub = session.onEntry.listen((_) {
      if (!mounted) {
        return;
      }

      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_terminalScroll.hasClients) {
          _terminalScroll.jumpTo(
            _terminalScroll.position.maxScrollExtent,
          );
        }
      });
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _terminal = session;
    });
  }

  Future<void> _refreshExplorer() async {
    if (mounted) {
      setState(() {
        _explorerLoading = true;
      });
    }

    final entries = await FileService.listDir(_directory);

    if (!mounted) {
      return;
    }

    entries.sort((a, b) {
      final bool aDirectory = a is Directory;
      final bool bDirectory = b is Directory;

      if (aDirectory != bDirectory) {
        return aDirectory ? -1 : 1;
      }

      return p
          .basename(a.path)
          .toLowerCase()
          .compareTo(
            p.basename(b.path).toLowerCase(),
          );
    });

    setState(() {
      _entries = entries;
      _explorerLoading = false;
    });
  }

  Future<void> _openFile(String path) async {
    if (!_documents.containsKey(path)) {
      final text = await FileService.readFile(path);

      _documents[path] = _OpenDocument(
        path: path,
        text: text,
        language: _languageFor(path),
      );

      _tabs.add(path);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _activePath = path;
    });

    final MonacoController? monaco = _monaco;

    if (monaco != null) {
      final Uri uri = Uri.parse(_fileUri(path));

      // documentByUri returns null for any file that hasn't been opened
      // in Monaco yet (every file except the very first one, which
      // onReady already opens). Open it for real before activating it —
      // passing a null document into activateDocument is both a
      // null-safety error and, more importantly, the actual bug: without
      // this, switching to a second Explorer file would silently do
      // nothing.
      var document = monaco.documentByUri(uri);
      document ??= await monaco.openDocument(
        text: _documents[path]!.text,
        language: _documents[path]!.language,
        uri: uri,
      );

      await monaco.activateDocument(document);
    }
  }

  Future<void> _closeTab(String path) async {
    final _OpenDocument? document = _documents[path];

    if (document?.dirty == true) {
      final bool? discard = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Unsaved changes'),
            content: Text(
              'Discard changes to ${p.basename(path)}?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx, true);
                },
                child: const Text('Discard'),
              ),
            ],
          );
        },
      );

      if (discard != true) {
        return;
      }
    }

    final Uri uri = Uri.parse(_fileUri(path));

    final opened = _monaco?.documentByUri(uri);

    if (opened != null) {
      await opened.close();
    }

    _documents.remove(path);
    _tabs.remove(path);

    if (_activePath == path) {
      _activePath = _tabs.isEmpty ? null : _tabs.last;

      if (_activePath != null) {
        await _openFile(_activePath!);
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveActive() async {
    final String? path = _activePath;
    final MonacoController? monaco = _monaco;

    if (path == null || monaco == null) {
      return;
    }

    final String text = await monaco.document.getText();

    await File(path).writeAsString(text);

    _documents[path]?.dirty = false;

    await monaco.document.markSaved();

    if (!mounted) {
      return;
    }

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved'),
        duration: Duration(milliseconds: 700),
      ),
    );
  }

  Future<void> _runTerminalCommand() async {
    final String command = _terminalController.text.trim();
    final TerminalSession? terminal = _terminal;

    if (command.isEmpty || terminal == null) {
      return;
    }

    _terminalController.clear();

    await terminal.execute(command);

    if (mounted) {
      setState(() {});
    }
  }

  void _toggleTerminal() {
    setState(() {
      _terminalVisible = !_terminalVisible;
    });
  }

  @override
  void dispose() {
    _terminalSub?.cancel();
    _terminal?.dispose();

    _terminalController.dispose();
    _terminalScroll.dispose();

    _monaco?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF181818),
      drawer: Drawer(
        backgroundColor: const Color(0xFF181818),
        child: SafeArea(
          child: _explorerPanel(),
        ),
      ),
      body: SafeArea(
        child: Row(
          children: [
            _activityBar(),
            if (_sidebarVisible && screenWidth >= 700)
              SizedBox(
                width: 235,
                child: _explorerPanel(),
              ),
            Expanded(
              child: _mainArea(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityBar() {
    return Container(
      width: 48,
      color: const Color(0xFF181818),
      child: Column(
        children: [
          const SizedBox(height: 6),
          _activityIcon(
            Icons.folder_open,
            'Explorer',
            () {
              if (MediaQuery.sizeOf(context).width < 700) {
                _scaffoldKey.currentState?.openDrawer();
              } else {
                setState(() {
                  _sidebarVisible = !_sidebarVisible;
                });
              }
            },
          ),
          _activityIcon(
            Icons.extension_outlined,
            'Toolchains',
            () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ToolchainsScreen(),
                ),
              );
            },
          ),
          const Spacer(),
          _activityIcon(
            Icons.terminal,
            'Terminal',
            _toggleTerminal,
          ),
          _activityIcon(
            Icons.settings_outlined,
            'Settings',
            () {},
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _activityIcon(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 23,
          color: const Color(0xFFCCCCCC),
        ),
      ),
    );
  }

  Widget _explorerPanel() {
    return Container(
      color: const Color(0xFF1F1F1F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Text(
              'EXPLORER',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                color: Color(0xFFBBBBBB),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(widget.rootPath),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    size: 17,
                  ),
                  onPressed: _refreshExplorer,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.create_new_folder_outlined,
                    size: 17,
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          Expanded(
            child: _explorerLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: 12,
                    ),
                    itemCount: _entries.length,
                    itemBuilder: (_, index) {
                      final FileSystemEntity entity =
                          _entries[index];

                      final bool isDirectory =
                          entity is Directory;

                      final String name =
                          p.basename(entity.path);

                      return InkWell(
                        onTap: () {
                          if (isDirectory) {
                            setState(() {
                              _directory = entity.path;
                            });

                            _refreshExplorer();
                          } else {
                            _openFile(entity.path);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDirectory
                                    ? Icons.folder
                                    : _fileIcon(entity.path),
                                size: 17,
                                color: _fileColor(
                                  entity.path,
                                  isDirectory,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  name,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                  ),
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
      ),
    );
  }

  Widget _mainArea() {
    return Column(
      children: [
        _topBar(),
        _tabBar(),
        Expanded(
          child: _editorArea(),
        ),
        if (_terminalVisible)
          SizedBox(
            height: 230,
            child: _terminalPanel(),
          ),
        _statusBar(),
      ],
    );
  }

  Widget _topBar() {
    return Container(
      height: 44,
      color: const Color(0xFF252526),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Icon(
            Icons.code,
            size: 18,
            color: Color(0xFF4FC3F7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.basename(widget.rootPath),
              style: const TextStyle(
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.save_outlined,
              size: 19,
            ),
            tooltip: 'Save',
            onPressed: _saveActive,
          ),
          IconButton(
            icon: const Icon(
              Icons.play_arrow,
              size: 20,
            ),
            tooltip: 'Run',
            onPressed: _runFlutter,
          ),
          IconButton(
            icon: const Icon(
              Icons.build_outlined,
              size: 19,
            ),
            tooltip: 'Build APK',
            onPressed: _buildApk,
          ),
          IconButton(
            icon: const Icon(
              Icons.terminal,
              size: 19,
            ),
            tooltip: 'Terminal',
            onPressed: _toggleTerminal,
          ),
          IconButton(
            icon: const Icon(
              Icons.more_vert,
              size: 19,
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    if (_tabs.isEmpty) {
      return Container(
        height: 36,
        color: const Color(0xFF181818),
      );
    }

    return Container(
      height: 36,
      color: const Color(0xFF181818),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (_, index) {
          final String path = _tabs[index];
          final bool active = path == _activePath;

          return InkWell(
            onTap: () => _openFile(path),
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 120,
                maxWidth: 190,
              ),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFF181818),
                border: Border(
                  right: BorderSide(
                    color: Colors.black.withValues(
                      alpha: .4,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _fileIcon(path),
                    size: 15,
                    color: _fileColor(path, false),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      p.basename(path),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (_documents[path]?.dirty == true)
                    const Text(
                      '•',
                      style: TextStyle(
                        fontSize: 16,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 15,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => _closeTab(path),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _editorArea() {
    final String? path = _activePath;

    if (path == null) {
      return Container(
        color: const Color(0xFF1E1E1E),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.code,
              size: 58,
              color: Color(0xFF3A3A3A),
            ),
            const SizedBox(height: 12),
            Text(
              p.basename(widget.rootPath),
              style: const TextStyle(
                fontSize: 20,
                color: Color(0xFFBDBDBD),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Open a file from Explorer',
              style: TextStyle(
                color: Color(0xFF777777),
              ),
            ),
            const SizedBox(height: 18),
            const Wrap(
              spacing: 8,
              children: [
                _KeyHint(
                  'Ctrl+P',
                  'Quick Open',
                ),
                _KeyHint(
                  'Ctrl+Shift+P',
                  'Command Palette',
                ),
                _KeyHint(
                  'Ctrl+`',
                  'Terminal',
                ),
              ],
            ),
          ],
        ),
      );
    }

    final _OpenDocument document = _documents[path]!;

    return MonacoEditor(
      initialText: document.text,
      options: EditorOptions(
        language: document.language,
        fontSize: 14,
        minimap: const MonacoMinimapOptions(
          enabled: false,
        ),
        wordWrap: MonacoWordWrap.on,
        lineNumbers: MonacoLineNumbers.on,
        scrollBeyondLastLine: false,
      ),
      showStatusBar: true,
      onReady: (controller) async {
        _monaco = controller;

        await controller.openDocument(
          text: document.text,
          language: document.language,
          uri: Uri.parse(_fileUri(path)),
        );

        controller.onContentChanged.listen((event) {
          if (!mounted) {
            return;
          }

          final String? active = _activePath;
          final Uri? uri = event.documentUri;

          if (uri == null) {
            return;
          }

          if (active != null &&
              Uri.parse(_fileUri(active)) == uri) {
            setState(() {
              _documents[active]?.dirty = true;
            });

            return;
          }

          for (final MapEntry<String, _OpenDocument> entry
              in _documents.entries) {
            if (Uri.parse(_fileUri(entry.key)) == uri) {
              setState(() {
                entry.value.dirty = true;
              });
              break;
            }
          }
        });
      },
    );
  }

  Widget _terminalPanel() {
    final TerminalSession? session = _terminal;

    return Container(
      color: const Color(0xFF111111),
      child: Column(
        children: [
          Container(
            height: 34,
            color: const Color(0xFF252526),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Text(
                  'TERMINAL',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    size: 17,
                  ),
                  onPressed: () {
                    session?.clear();

                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 17,
                  ),
                  onPressed: _toggleTerminal,
                ),
              ],
            ),
          ),
          Expanded(
            child: session == null
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          controller: _terminalScroll,
                          padding: const EdgeInsets.all(10),
                          itemCount: session.history.length,
                          itemBuilder: (_, i) {
                            final TerminalHistoryEntry history =
                                session.history[i];

                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: 8,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '\$ ${history.commandLine}',
                                    style: const TextStyle(
                                      color:
                                          Color(0xFF4FC3F7),
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  for (final line
                                      in history.output)
                                    Text(
                                      line.text,
                                      style: TextStyle(
                                        color: line.isError
                                            ? const Color(
                                                0xFFF48771,
                                              )
                                            : const Color(
                                                0xFFD4D4D4,
                                              ),
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                  Text(
                                    'exit ${history.exitCode ?? 0}',
                                    style: const TextStyle(
                                      color: Color(0xFF666666),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          10,
                          0,
                          10,
                          8,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '> ',
                              style: TextStyle(
                                color: Color(0xFF4FC3F7),
                                fontFamily: 'monospace',
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller:
                                    _terminalController,
                                onSubmitted: (_) =>
                                    _runTerminalCommand(),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                                decoration:
                                    const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'command',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.send,
                                size: 18,
                              ),
                              onPressed:
                                  _runTerminalCommand,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar() {
    return Container(
      height: 22,
      color: const Color(0xFF007ACC),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.code,
            size: 12,
          ),
          const SizedBox(width: 6),
          const Text(
            'FLDE',
            style: TextStyle(
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Text(
            _activePath == null
                ? 'No file'
                : _languageLabel(
                    _documents[_activePath!]!.language,
                  ),
            style: const TextStyle(
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'UTF-8',
            style: TextStyle(
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runFlutter() async {
    setState(() {
      _terminalVisible = true;
    });

    await _terminal?.execute('flutter run');

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _buildApk() async {
    setState(() {
      _terminalVisible = true;
    });

    await _terminal?.execute(
      'flutter build apk --debug',
    );

    if (mounted) {
      setState(() {});
    }
  }

  String _fileUri(String path) {
    return Uri.file(path).toString();
  }

  MonacoLanguage _languageFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.dart':
        return MonacoLanguage.dart;
      case '.js':
        return MonacoLanguage.javascript;
      case '.ts':
        return MonacoLanguage.typescript;
      case '.json':
        return MonacoLanguage.json;
      case '.yaml':
      case '.yml':
        return MonacoLanguage.yaml;
      case '.md':
        return MonacoLanguage.markdown;
      case '.xml':
        return MonacoLanguage.xml;
      case '.html':
        return MonacoLanguage.html;
      case '.css':
        return MonacoLanguage.css;
      case '.java':
        return MonacoLanguage.java;
      case '.kt':
        return MonacoLanguage.kotlin;
      case '.gradle':
        return const MonacoLanguage('groovy');
      case '.sh':
        return const MonacoLanguage('shell');
      default:
        return MonacoLanguage.plaintext;
    }
  }

  String _languageLabel(MonacoLanguage language) {
    return language.id;
  }

  IconData _fileIcon(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.dart':
        return Icons.code;
      case '.json':
        return Icons.data_object;
      case '.yaml':
      case '.yml':
        return Icons.settings_outlined;
      case '.md':
        return Icons.description_outlined;
      case '.java':
      case '.kt':
        return Icons.coffee;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _fileColor(
    String path,
    bool isDir,
  ) {
    if (isDir) {
      return const Color(0xFFD7BA7D);
    }

    if (p.extension(path).toLowerCase() == '.dart') {
      return const Color(0xFF42A5F5);
    }

    if (p.extension(path).toLowerCase() == '.yaml') {
      return const Color(0xFFCB7DB5);
    }

    return const Color(0xFFBDBDBD);
  }
}

class _KeyHint extends StatelessWidget {
  final String keyText;
  final String label;

  const _KeyHint(
    this.keyText,
    this.label,
  );

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        '$keyText  $label',
        style: const TextStyle(
          fontSize: 10,
        ),
      ),
      backgroundColor: const Color(0xFF252526),
      side: const BorderSide(
  style: BorderStyle.none,
),
    );
  }
}
