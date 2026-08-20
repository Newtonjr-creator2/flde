import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import '../core/runtime/architecture_service.dart';
import '../core/storage/storage_service.dart';
import '../models/toolchain_info.dart';
import '../models/toolchain_manifest.dart';
import 'toolchain_downloader.dart';
import 'toolchain_validator.dart';

class ToolchainManager {
  static final ToolchainManager instance = ToolchainManager._();
  ToolchainManager._();

  final _changes = StreamController<List<ToolchainInfo>>.broadcast();
  List<ToolchainInfo> _installed = const [];

  Stream<List<ToolchainInfo>> get changes => _changes.stream;
  List<ToolchainInfo> get installed => List.unmodifiable(_installed);

  Future<List<ToolchainInfo>> scanInstalled() async {
    final layout = await StorageService.initialize();
    final result = <ToolchainInfo>[];

    for (final kind in ToolchainKind.values) {
      final root = Directory(p.join(layout.toolchains.path, kind.name));
      if (!await root.exists()) continue;
      await for (final versionDir in root.list(followLinks: false)) {
        if (versionDir is! Directory) continue;
        final marker = File(p.join(versionDir.path, '.flde-install.json'));
        if (!await marker.exists()) continue;
        final text = await marker.readAsString();
        final parts = text.split('|');
        final version = parts.isNotEmpty ? parts[0] : p.basename(versionDir.path);
        final arch = parts.length > 1 ? parts[1] : 'unknown';
        result.add(ToolchainInfo(
          kind: kind,
          name: kind.name,
          version: version,
          architecture: arch,
          platform: 'android',
          path: versionDir.path,
          status: ToolchainInstallStatus.installed,
        ));
      }
    }

    _installed = result;
    _changes.add(List.unmodifiable(_installed));
    return installed;
  }

  Future<ToolchainValidationResult> validate(ToolchainInfo info) {
    return ToolchainValidator.validate(info);
  }

  Future<ToolchainInfo> install(
    ToolchainManifest manifest, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('FLDE Phase 2 is Android-only.');
    }
    if (!ArchitectureService.compatible(manifest.architecture)) {
      throw StateError(
        'Toolchain architecture ${manifest.architecture} is incompatible with device ${ArchitectureService.abi}.',
      );
    }

    final downloader = ToolchainDownloader();
    final archiveFile = await downloader.download(
      manifest,
      onProgress: onProgress,
    );
    final target = await StorageService.toolchainDirectory(
      manifest.kind.name,
      manifest.version,
    );

    await _extractArchive(archiveFile, target);
    await File(p.join(target.path, '.flde-install.json'))
        .writeAsString('${manifest.version}|${manifest.architecture}');

    final info = ToolchainInfo(
      kind: manifest.kind,
      name: manifest.name,
      version: manifest.version,
      architecture: manifest.architecture,
      platform: manifest.platform,
      path: target.path,
      status: ToolchainInstallStatus.installed,
      source: manifest.downloadUrl,
      sha256: manifest.sha256,
      sizeBytes: manifest.sizeBytes,
      dependencies: manifest.dependencies,
    );

    final validation = await validate(info);
    if (!validation.valid) {
      await target.delete(recursive: true);
      throw StateError(
        'Installation completed but validation failed: ${validation.message}',
      );
    }

    await scanInstalled();
    return info;
  }

  Future<void> _extractArchive(File archiveFile, Directory target) async {
    final bytes = await archiveFile.readAsBytes();
    final name = archiveFile.path.toLowerCase();
    if (name.endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive) {
        final out = p.join(target.path, entry.name);
        if (entry.isFile) {
          final file = File(out);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(out).create(recursive: true);
        }
      }
      return;
    }
    throw UnsupportedError(
      'This Phase 2 build extracts ZIP archives only. Add a tar/gzip extractor before enabling other formats.',
    );
  }
}
