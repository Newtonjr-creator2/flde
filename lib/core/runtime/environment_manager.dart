import 'dart:io';
import 'package:path/path.dart' as p;
import '../storage/storage_service.dart';

class EnvironmentManager {
  static Future<Map<String, String>> buildEnvironment() async {
    final layout = await StorageService.initialize();
    final env = Map<String, String>.from(Platform.environment);

    Future<String?> latest(String kind) async {
      final root = Directory(p.join(layout.toolchains.path, kind));
      if (!await root.exists()) return null;
      final dirs = <Directory>[];
      await for (final e in root.list(followLinks: false)) {
        if (e is Directory) dirs.add(e);
      }
      if (dirs.isEmpty) return null;
      dirs.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      return dirs.first.path;
    }

    final flutter = await latest('flutter');
    final dart = await latest('dart');
    final git = await latest('git');
    final java = await latest('java');
    final gradle = await latest('gradle');
    final android = await latest('androidSdk');

    final pathParts = <String>[
      if (flutter != null) p.join(flutter, 'bin'),
      if (dart != null) p.join(dart, 'bin'),
      if (git != null) p.join(git, 'bin'),
      if (java != null) p.join(java, 'bin'),
      if (gradle != null) p.join(gradle, 'bin'),
      if (android != null) p.join(android, 'platform-tools'),
      if (android != null) p.join(android, 'cmdline-tools', 'latest', 'bin'),
      if (Platform.isAndroid) '/system/bin',
    ];
    final existingPath = env['PATH'];
    if (existingPath != null && existingPath.isNotEmpty) pathParts.add(existingPath);

    env['PATH'] = pathParts.join(Platform.pathSeparator);
    env['FLDE_HOME'] = layout.root.path;
    env['PUB_CACHE'] = layout.pubCache.path;
    env['GRADLE_USER_HOME'] = layout.gradleCache.path;
    env['FLDE_TOOLCHAINS'] = layout.toolchains.path;
    if (android != null) {
      env['ANDROID_HOME'] = android;
      env['ANDROID_SDK_ROOT'] = android;
    }
    return env;
  }

  static Future<String?> resolve(String executable) async {
    final env = await buildEnvironment();
    final path = env['PATH'] ?? '';
    for (final dir in path.split(Platform.pathSeparator)) {
      if (dir.isEmpty) continue;
      final candidate = File(p.join(dir, executable));
      if (await candidate.exists()) return candidate.path;
    }
    return null;
  }
}
