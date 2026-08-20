import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../core/storage/storage_service.dart';
import '../models/toolchain_manifest.dart';

class DownloadProgress {
  final int received;
  final int total;
  final double bytesPerSecond;

  const DownloadProgress({
    required this.received,
    required this.total,
    required this.bytesPerSecond,
  });

  double? get fraction => total > 0 ? received / total : null;
}

class ToolchainDownloader {
  Future<File> download(
    ToolchainManifest manifest, {
    void Function(DownloadProgress progress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    if (manifest.downloadUrl.isEmpty || manifest.downloadUrl.startsWith('REPLACE_')) {
      throw StateError('No real download URL is configured for ${manifest.name}.');
    }

    final layout = await StorageService.initialize();
    final filename = _safeFilename(manifest);
    final destination = File(p.join(layout.downloads.path, filename));
    final temp = File('${destination.path}.part');

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(manifest.downloadUrl));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode} while downloading ${manifest.downloadUrl}',
        );
      }

      final total = response.contentLength > 0
          ? response.contentLength
          : manifest.sizeBytes;
      final sink = temp.openWrite();
      var received = 0;
      final started = DateTime.now();

      await for (final chunk in response) {
        if (await isCancelled?.call() ?? false) {
          await sink.close();
          await temp.delete().catchError((_) => temp);
          throw StateError('Download cancelled.');
        }
        sink.add(chunk);
        received += chunk.length;
        final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
        onProgress?.call(
          DownloadProgress(
            received: received,
            total: total,
            bytesPerSecond: seconds <= 0 ? 0 : received / seconds,
          ),
        );
      }
      await sink.close();

      final digest = await _sha256(temp);
      if (manifest.sha256.isNotEmpty &&
          manifest.sha256.toLowerCase() != digest.toLowerCase()) {
        await temp.delete().catchError((_) => temp);
        throw StateError(
          'Checksum mismatch. Expected ${manifest.sha256}, got $digest.',
        );
      }

      if (await destination.exists()) await destination.delete();
      await temp.rename(destination.path);
      return destination;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _safeFilename(ToolchainManifest manifest) {
    final extension = manifest.downloadUrl.toLowerCase().endsWith('.zip')
        ? '.zip'
        : manifest.downloadUrl.toLowerCase().endsWith('.tar.gz')
            ? '.tar.gz'
            : '.archive';
    return '${manifest.kind.name}-${manifest.version}-${manifest.architecture}$extension';
  }
}
