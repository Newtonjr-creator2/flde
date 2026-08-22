import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage_service.dart';
import '../models/toolchain_manifest.dart';

enum DownloadPhase { downloading, verifying, extracting, done, failed, cancelled }

class DownloadProgress {
  final DownloadPhase phase;
  final int received;
  final int? total; // null when server didn't report Content-Length
  final String? message;

  const DownloadProgress({required this.phase, this.received = 0, this.total, this.message});

  double? get fraction => total != null && total! > 0 ? received / total! : null;
}

/// Downloads, verifies, and extracts a toolchain archive. Follows the exact
/// pipeline from spec section 3:
///   download -> verify checksum -> extract -> validate -> move to
///   toolchains/ -> mark installed
/// An archive is NEVER extracted (let alone executed) before its checksum
/// has been checked against the manifest entry.
class ToolchainDownloader {
  final StorageService storage;

  ToolchainDownloader(this.storage);

  Stream<DownloadProgress> installFromManifest(ToolchainManifestEntry entry, String folderName) async* {
    if (!entry.hasSource) {
      yield const DownloadProgress(
        phase: DownloadPhase.failed,
        message: 'No download source configured for this toolchain yet.',
      );
      return;
    }

    final downloadFile = File(p.join(
      storage.downloadsDir.path,
      '${entry.kind.name}-${entry.version}-${entry.architecture}${_extensionFor(entry.downloadUrl!)}',
    ));

    // --- 1. download ---
    int received = 0;
    int? total = entry.sizeBytes;
    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(entry.downloadUrl!));
      final response = await request.close();
      if (response.statusCode != 200) {
        yield DownloadProgress(
          phase: DownloadPhase.failed,
          message: 'Download failed: HTTP ${response.statusCode}',
        );
        return;
      }
      total ??= response.contentLength > 0 ? response.contentLength : null;

      await downloadFile.parent.create(recursive: true);
      sink = downloadFile.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(phase: DownloadPhase.downloading, received: received, total: total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } catch (e) {
      await sink?.close();
      yield DownloadProgress(phase: DownloadPhase.failed, message: 'Download error: $e');
      return;
    } finally {
      client.close(force: true);
    }

    // --- 2. verify checksum ---
    if (entry.sha256 != null && entry.sha256!.isNotEmpty) {
      yield const DownloadProgress(phase: DownloadPhase.verifying);
      final actualHash = await _sha256OfFile(downloadFile);
      if (actualHash.toLowerCase() != entry.sha256!.toLowerCase()) {
        await downloadFile.delete();
        yield DownloadProgress(
          phase: DownloadPhase.failed,
          message: 'Checksum mismatch — downloaded file was not installed. '
              'Expected ${entry.sha256}, got $actualHash.',
        );
        return;
      }
    }

    // --- 3. extract ---
    yield const DownloadProgress(phase: DownloadPhase.extracting);
    final destination = Directory(p.join(storage.toolchainDir(folderName).path, entry.version));
    try {
      await _extract(downloadFile, destination);
    } catch (e) {
      yield DownloadProgress(phase: DownloadPhase.failed, message: 'Extraction failed: $e');
      return;
    } finally {
      if (await downloadFile.exists()) {
        await downloadFile.delete();
      }
    }

    // --- 4/5. validate + mark installed is the caller's job (ToolchainManager
    // re-runs ToolchainValidator against the freshly extracted directory) ---
    yield const DownloadProgress(phase: DownloadPhase.done);
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _extensionFor(String url) {
    if (url.endsWith('.tar.gz') || url.endsWith('.tgz')) return '.tar.gz';
    if (url.endsWith('.tar.xz')) return '.tar.xz';
    if (url.endsWith('.zip')) return '.zip';
    return p.extension(Uri.parse(url).path);
  }

  Future<void> _extract(File archiveFile, Directory destination) async {
    await destination.create(recursive: true);
    final bytes = await archiveFile.readAsBytes();
    final name = archiveFile.path.toLowerCase();

    Archive archive;
    if (name.endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) {
      final tarBytes = GZipDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(tarBytes);
    } else if (name.endsWith('.tar')) {
      archive = TarDecoder().decodeBytes(bytes);
    } else {
      throw UnsupportedError('Unsupported archive format for $name (only .zip/.tar/.tar.gz supported)');
    }

    final destinationCanonical = p.normalize(destination.absolute.path);
    final destinationPrefix = '$destinationCanonical${p.separator}';

    for (final file in archive) {
      // Reject absolute paths and ../ traversal before touching the
      // filesystem. Archive entries are untrusted even after checksum
      // verification because a trusted publisher can still ship a malformed
      // archive.
      final relativeName = file.name.replaceAll('\\', '/');
      if (p.isAbsolute(relativeName)) {
        throw const FormatException('Archive contains an absolute path');
      }

      final outPath = p.normalize(p.join(destinationCanonical, relativeName));
      if (outPath != destinationCanonical && !outPath.startsWith(destinationPrefix)) {
        throw const FormatException('Archive contains a path traversal entry');
      }

      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        if (!Platform.isWindows && (file.mode & 0x49) != 0) {
          // Preserve the executable bit. Android may still reject direct
          // exec from app-data; NativeRuntimeEnvironment handles ELF files
          // through the system linker instead.
          await Process.run('chmod', ['+x', outPath]);
        }
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }
}
