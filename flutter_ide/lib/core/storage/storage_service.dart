import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// FLDE's managed storage layout. The exact absolute Android path is never
/// assumed — it's resolved at runtime via path_provider, per spec section 2.
///
/// FLDE/
///   toolchains/{dart,flutter,java,gradle,android-sdk}/<version>/
///   pub-cache/
///   gradle-cache/
///   projects/
///   downloads/
///   temp/
class StorageService {
  static StorageService? _instance;
  final Directory root;

  StorageService._(this.root);

  static Future<StorageService> instance() async {
    if (_instance != null) return _instance!;
    final appDir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(appDir.path, 'FLDE'));
    for (final sub in [
      'toolchains/dart',
      'toolchains/flutter',
      'toolchains/java',
      'toolchains/gradle',
      'toolchains/android-sdk',
      'pub-cache',
      'gradle-cache',
      'projects',
      'downloads',
      'temp',
    ]) {
      await Directory(p.join(root.path, sub)).create(recursive: true);
    }
    _instance = StorageService._(root);
    return _instance!;
  }

  Directory get toolchainsDir => Directory(p.join(root.path, 'toolchains'));
  Directory toolchainDir(String kindName) => Directory(p.join(root.path, 'toolchains', kindName));
  Directory get pubCacheDir => Directory(p.join(root.path, 'pub-cache'));
  Directory get gradleCacheDir => Directory(p.join(root.path, 'gradle-cache'));
  Directory get projectsDir => Directory(p.join(root.path, 'projects'));
  Directory get downloadsDir => Directory(p.join(root.path, 'downloads'));
  Directory get tempDir => Directory(p.join(root.path, 'temp'));

  /// Real recursive size of a directory, in bytes. This walks the actual
  /// filesystem — nothing here is estimated.
  static Future<int> dirSizeBytes(Directory dir) async {
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // file vanished mid-walk or unreadable — skip rather than guess
        }
      }
    }
    return total;
  }

  /// Real, itemized usage across every managed category. Free/total device
  /// storage is intentionally NOT reported here — Android exposes that only
  /// via a platform channel or a plugin we haven't added yet, and Phase 2's
  /// rule is: don't fake a number we can't actually measure. Callers should
  /// label device-level free space as "not yet implemented" rather than
  /// invent one.
  Future<StorageReport> usageReport() async {
    final toolchains = await dirSizeBytes(toolchainsDir);
    final pubCache = await dirSizeBytes(pubCacheDir);
    final gradleCache = await dirSizeBytes(gradleCacheDir);
    final projects = await dirSizeBytes(projectsDir);
    final downloads = await dirSizeBytes(downloadsDir);
    final temp = await dirSizeBytes(tempDir);
    return StorageReport(
      toolchainsBytes: toolchains,
      pubCacheBytes: pubCache,
      gradleCacheBytes: gradleCache,
      projectsBytes: projects,
      downloadsBytes: downloads,
      tempBytes: temp,
    );
  }

  Future<void> clearTemp() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);
  }
}

class StorageReport {
  final int toolchainsBytes;
  final int pubCacheBytes;
  final int gradleCacheBytes;
  final int projectsBytes;
  final int downloadsBytes;
  final int tempBytes;

  const StorageReport({
    required this.toolchainsBytes,
    required this.pubCacheBytes,
    required this.gradleCacheBytes,
    required this.projectsBytes,
    required this.downloadsBytes,
    required this.tempBytes,
  });

  int get totalManagedBytes =>
      toolchainsBytes + pubCacheBytes + gradleCacheBytes + projectsBytes + downloadsBytes + tempBytes;

  static String humanize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final units = ['KB', 'MB', 'GB'];
    double value = bytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}
