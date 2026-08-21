import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage_service.dart';
import 'file_service.dart';

enum ImportKind { directory, zip, singleFile }

class ImportResult {
  final bool success;
  final String? importedPath;
  final String? error;

  const ImportResult({required this.success, this.importedPath, this.error});
}

/// Imports a project/file from external storage (SD card, USB OTG) via
/// Android's Storage Access Framework, per Phase 2 spec section 16. This
/// deliberately reuses FileService/StorageService rather than introducing
/// a second filesystem manager — its only job is picking the source and
/// handing off to the existing copy/extract logic.
class UsbStorageService {
  final StorageService storage;

  UsbStorageService(this.storage);

  Future<ImportResult> pickAndImport() async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: 'Select project folder or ZIP location');
    if (result == null) {
      return const ImportResult(success: false, error: 'No folder selected');
    }
    return _importDirectory(Directory(result));
  }

  Future<ImportResult> pickAndImportZip() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    final path = result?.files.single.path;
    if (path == null) {
      return const ImportResult(success: false, error: 'No ZIP file selected');
    }
    final zipFile = File(path);
    final targetName = p.basenameWithoutExtension(zipFile.path);
    final targetDir = Directory(p.join(storage.projectsDir.path, targetName));
    try {
      await targetDir.create(recursive: true);
      await FileService.importZip(zipFile, targetDir);
      return ImportResult(success: true, importedPath: targetDir.path);
    } catch (e) {
      return ImportResult(success: false, error: '$e');
    }
  }

  Future<ImportResult> _importDirectory(Directory source) async {
    final targetName = p.basename(source.path);
    final targetDir = Directory(p.join(storage.projectsDir.path, targetName));
    try {
      await _copyRecursive(source, targetDir);
      return ImportResult(success: true, importedPath: targetDir.path);
    } catch (e) {
      return ImportResult(success: false, error: '$e');
    }
  }

  Future<void> _copyRecursive(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final newPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}
