import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FldeStorageLayout {
  final Directory root;
  final Directory toolchains;
  final Directory downloads;
  final Directory temp;
  final Directory projects;
  final Directory pubCache;
  final Directory gradleCache;

  const FldeStorageLayout({
    required this.root,
    required this.toolchains,
    required this.downloads,
    required this.temp,
    required this.projects,
    required this.pubCache,
    required this.gradleCache,
  });
}

class StorageService {
  static FldeStorageLayout? _cached;

  static Future<FldeStorageLayout> initialize() async {
    if (_cached != null) return _cached!;
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'FLDE'));
    final layout = FldeStorageLayout(
      root: root,
      toolchains: Directory(p.join(root.path, 'toolchains')),
      downloads: Directory(p.join(root.path, 'downloads')),
      temp: Directory(p.join(root.path, 'temp')),
      projects: Directory(p.join(root.path, 'projects')),
      pubCache: Directory(p.join(root.path, 'pub-cache')),
      gradleCache: Directory(p.join(root.path, 'gradle-cache')),
    );
    for (final dir in [
      layout.root,
      layout.toolchains,
      layout.downloads,
      layout.temp,
      layout.projects,
      layout.pubCache,
      layout.gradleCache,
    ]) {
      await dir.create(recursive: true);
    }
    _cached = layout;
    return layout;
  }

  static Future<Directory> toolchainDirectory(String name, String version) async {
    final layout = await initialize();
    final dir = Directory(p.join(layout.toolchains.path, name, version));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<int> directoryBytes(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  static Future<StorageStats> stats() async {
    final layout = await initialize();
    final rootBytes = await directoryBytes(layout.root);
    final toolchainBytes = await directoryBytes(layout.toolchains);
    final projectBytes = await directoryBytes(layout.projects);
    final cacheBytes = await directoryBytes(layout.pubCache) +
        await directoryBytes(layout.gradleCache);
    return StorageStats(
      rootPath: layout.root.path,
      totalManagedBytes: rootBytes,
      toolchainBytes: toolchainBytes,
      projectBytes: projectBytes,
      cacheBytes: cacheBytes,
    );
  }
}

class StorageStats {
  final String rootPath;
  final int totalManagedBytes;
  final int toolchainBytes;
  final int projectBytes;
  final int cacheBytes;

  const StorageStats({
    required this.rootPath,
    required this.totalManagedBytes,
    required this.toolchainBytes,
    required this.projectBytes,
    required this.cacheBytes,
  });

  String get managedText => _format(totalManagedBytes);

  static String _format(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
  }
}
