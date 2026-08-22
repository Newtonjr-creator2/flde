import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_buzzing_identifier/models/toolchain_info.dart';
import 'package:real_buzzing_identifier/models/toolchain_manifest.dart';

void main() {
  group('ToolchainManifestEntry', () {
    test('round-trips through JSON without inventing fields', () {
      const entry = ToolchainManifestEntry(
        kind: ToolchainKind.dart,
        version: '3.5.0',
        architecture: 'arm64-v8a',
        platform: 'android',
        downloadUrl: 'https://example.com/dart.zip',
        sha256: 'abc123',
        sizeBytes: 12345,
        archiveType: 'zip',
        runtimeRequirements: RuntimeRequirements(
          requiresDirectExecFromPrivateStorage: true,
          supportedAbis: ['arm64-v8a'],
        ),
      );

      final json = entry.toJson();
      final restored = ToolchainManifestEntry.fromJson(json);

      expect(restored.kind, ToolchainKind.dart);
      expect(restored.version, '3.5.0');
      expect(restored.downloadUrl, 'https://example.com/dart.zip');
      expect(restored.hasSource, isTrue);
      expect(restored.runtimeRequirements?.requiresDirectExecFromPrivateStorage, isTrue);
      expect(restored.runtimeRequirements?.supportedAbis, ['arm64-v8a']);
    });

    test('hasSource is false when downloadUrl is absent — no install offered without a real source', () {
      const entry = ToolchainManifestEntry(
        kind: ToolchainKind.flutter,
        version: '3.24.0',
        architecture: 'arm64-v8a',
        platform: 'android',
      );
      expect(entry.hasSource, isFalse);
    });
  });

  group('ToolchainManifestLoader', () {
    test('ensureDefaultManifestExists creates a real file that loads as an empty list', () async {
      final tempDir = await Directory.systemTemp.createTemp('flde_manifest_test_');
      final loader = ToolchainManifestLoader('${tempDir.path}/manifest.json');

      await loader.ensureDefaultManifestExists();
      final entries = await loader.load();

      expect(entries, isEmpty);
      final file = File('${tempDir.path}/manifest.json');
      expect(await file.exists(), isTrue);
      await tempDir.delete(recursive: true);
    });

    test('a corrupt manifest file fails closed to an empty list, never guesses', () async {
      final tempDir = await Directory.systemTemp.createTemp('flde_manifest_corrupt_test_');
      final file = File('${tempDir.path}/manifest.json');
      await file.writeAsString('{ not valid json ]');
      final loader = ToolchainManifestLoader(file.path);

      final entries = await loader.load();
      expect(entries, isEmpty);
      await tempDir.delete(recursive: true);
    });
  });
}
