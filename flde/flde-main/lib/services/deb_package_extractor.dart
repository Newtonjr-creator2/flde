import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Minimal Debian .deb reader used by FLDE's Android runtime installer.
/// A .deb is an ar container whose data member is normally a tar.xz archive.
/// We only install the data member and intentionally ignore maintainer scripts:
/// they assume a real dpkg/Termux installation root and are not safe to run
/// inside an application sandbox.
class DebPackageExtractor {
  static const _arMagic = '!<arch>\n';

  Future<void> extract(File deb, Directory destination) async {
    final bytes = await deb.readAsBytes();
    if (bytes.length < 8 || ascii.decode(bytes.sublist(0, 8)) != _arMagic) {
      throw const FormatException('Not a Debian ar archive');
    }

    List<int>? data;
    var offset = 8;
    while (offset + 60 <= bytes.length) {
      final header = bytes.sublist(offset, offset + 60);
      final name = ascii.decode(header.sublist(0, 16)).trim();
      final sizeText = ascii.decode(header.sublist(48, 58)).trim();
      final size = int.tryParse(sizeText);
      if (size == null || size < 0 || offset + 60 + size > bytes.length) {
        throw const FormatException('Malformed Debian ar member');
      }
      final body = bytes.sublist(offset + 60, offset + 60 + size);
      if (name.startsWith('data.tar')) data = body;
      offset += 60 + size;
      if (offset.isOdd) offset++;
    }

    if (data == null) throw const FormatException('Debian archive has no data.tar member');
    final tar = _decodeTar(data);
    await _extractTar(tar, destination);
  }

  List<int> _decodeTar(List<int> bytes) {
    if (_hasSuffix(bytes, [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) {
      return XZDecoder().decodeBytes(bytes);
    }
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      return GZipDecoder().decodeBytes(bytes);
    }
    return bytes;
  }

  Future<void> _extractTar(List<int> tarBytes, Directory destination) async {
    final archive = TarDecoder().decodeBytes(tarBytes);
    final root = p.normalize(destination.absolute.path).replaceAll('\\', '/');
    final prefix = '$root/';
    await destination.create(recursive: true);

    for (final entry in archive) {
      final original = entry.name.replaceAll('\\', '/');
      final relative = _stripTermuxPrefix(original);
      if (relative.isEmpty || relative == '.') continue;
      if (relative.startsWith('/') || relative.split('/').contains('..')) {
        throw const FormatException('Debian archive contains unsafe path');
      }
      final out = p.normalize(p.join(root, relative)).replaceAll('\\', '/');
      if (out != root && !out.startsWith(prefix)) {
        throw const FormatException('Debian archive path escapes install root');
      }

      if (entry.isSymbolicLink) {
        final target = entry.nameOfLinkedFile;
        if (target.contains('..') || target.startsWith('/')) {
          throw const FormatException('Unsafe symlink in Debian package');
        }
        final file = File(out);
        await file.parent.create(recursive: true);
        try { await file.delete(); } catch (_) {}
        await Link(out).create(target, recursive: false);
      } else if (entry.isFile) {
        final file = File(out);
        await file.parent.create(recursive: true);
        var content = entry.content as List<int>;
        // Termux packages frequently contain wrapper scripts with their
        // original /data/data/com.termux/files/usr prefix. Rewrite textual
        // launchers to the actual FLDE install root; never rewrite binary
        // ELF data. ELF dynamic dependencies are handled through
        // LD_LIBRARY_PATH by EnvironmentManager.
        if (_looksLikeText(content)) {
          final text = utf8.decode(content, allowMalformed: true);
          if (text.contains('/data/data/com.termux/files/usr')) {
            final rewritten = text.replaceAll('/data/data/com.termux/files/usr', root);
            content = utf8.encode(rewritten);
          }
        }
        await file.writeAsBytes(content, flush: false);
        if ((entry.mode & 0x49) != 0) {
          try { await Process.run('chmod', ['+x', out]); } catch (_) {}
        }
      } else {
        await Directory(out).create(recursive: true);
      }
    }
  }

  bool _looksLikeText(List<int> bytes) {
    if (bytes.length > 2 * 1024 * 1024) return false;
    final sample = bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes;
    return !sample.contains(0);
  }

  String _stripTermuxPrefix(String name) {
    const prefixes = [
      'data/data/com.termux/files/usr/',
      './data/data/com.termux/files/usr/',
      'usr/',
      './usr/',
    ];
    for (final prefix in prefixes) {
      if (name.startsWith(prefix)) return name.substring(prefix.length);
    }
    return name.replaceFirst(RegExp(r'^\./'), '');
  }

  bool _hasSuffix(List<int> bytes, List<int> signature) {
    return bytes.length >= signature.length &&
        List<int>.generate(signature.length, (i) => bytes[i]).toString() == signature.toString();
  }
}
