import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage_service.dart';

/// Real filesystem operations against the device's storage.
/// Every method here performs an actual dart:io call — nothing is simulated.
class FileService {
  /// The IDE's own sandboxed workspace, used for projects created inside
  /// the app (spec section 24 — Full Project Sandbox).
  ///
  /// Delegates to StorageService (Phase 2's single managed-storage owner —
  /// FLDE/projects/) rather than defining a second, separate projects
  /// directory. Kept as a method here so existing callers (home_screen.dart)
  /// don't need to change.
  static Future<Directory> workspaceProjectsDir() async {
    final storage = await StorageService.instance();
    return storage.projectsDir;
  }

  static Future<List<FileSystemEntity>> listDir(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final entries = await dir.list(followLinks: false).toList();
    entries.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });
    return entries;
  }

  static Future<String> readFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    return file.readAsString();
  }

  static Future<void> writeFile(String filePath, String contents) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  static Future<File> createFile(String dirPath, String name) async {
    final file = File(p.join(dirPath, name));
    if (await file.exists()) {
      throw FileSystemException('File already exists', file.path);
    }
    await file.create(recursive: true);
    return file;
  }

  static Future<Directory> createFolder(String dirPath, String name) async {
    final dir = Directory(p.join(dirPath, name));
    if (await dir.exists()) {
      throw FileSystemException('Folder already exists', dir.path);
    }
    return dir.create(recursive: true);
  }

  static Future<void> rename(FileSystemEntity entity, String newName) async {
    final newPath = p.join(p.dirname(entity.path), newName);
    await entity.rename(newPath);
  }

  static Future<void> delete(FileSystemEntity entity) async {
    if (entity is Directory) {
      await entity.delete(recursive: true);
    } else {
      await entity.delete();
    }
  }

  static Future<void> duplicate(FileSystemEntity entity) async {
    final dir = p.dirname(entity.path);
    final ext = p.extension(entity.path);
    final base = p.basenameWithoutExtension(entity.path);
    var candidate = p.join(dir, '$base copy$ext');
    var i = 2;
    while (await File(candidate).exists() || await Directory(candidate).exists()) {
      candidate = p.join(dir, '$base copy $i$ext');
      i++;
    }
    if (entity is File) {
      await entity.copy(candidate);
    } else if (entity is Directory) {
      await _copyDirRecursive(entity, Directory(candidate));
    }
  }

  static Future<void> _copyDirRecursive(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final newPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  /// Real ZIP extraction (spec section 78 — Import/Export) using the
  /// `archive` package to decode actual bytes, not a placeholder.
  static Future<Directory> importZip(File zipFile, Directory destination) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final outPath = p.join(destination.path, entry.name);
      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
    return destination;
  }

  /// Recursive text search across a project (spec section 52 — real, not
  /// index-simulated; reads actual file bytes on disk).
  static Future<List<SearchHit>> searchInProject(
    String rootPath,
    String query, {
    bool caseSensitive = false,
  }) async {
    final results = <SearchHit>[];
    final root = Directory(rootPath);
    if (!await root.exists()) return results;

    const skipDirs = {'.git', 'build', '.dart_tool', 'node_modules'};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (skipDirs.any((d) => entity.path.contains('${p.separator}$d${p.separator}'))) {
        continue;
      }
      String content;
      try {
        content = await entity.readAsString();
      } catch (_) {
        continue; // binary or unreadable file — skip
      }
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final haystack = caseSensitive ? lines[i] : lines[i].toLowerCase();
        final needle = caseSensitive ? query : query.toLowerCase();
        if (haystack.contains(needle)) {
          results.add(SearchHit(filePath: entity.path, lineNumber: i + 1, lineText: lines[i]));
        }
      }
    }
    return results;
  }
}

class SearchHit {
  final String filePath;
  final int lineNumber;
  final String lineText;

  SearchHit({required this.filePath, required this.lineNumber, required this.lineText});
}
