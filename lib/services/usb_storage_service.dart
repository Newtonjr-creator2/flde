import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../core/storage/storage_service.dart';
import 'file_service.dart';

class UsbStorageService {
  Future<String?> pickDirectory() {
    return FilePicker.getDirectoryPath(
      dialogTitle: 'Select project on internal storage, SD card, or USB OTG',
    );
  }

  Future<String?> pickProjectZip() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  Future<Directory> importDirectory(String sourcePath) async {
    final layout = await StorageService.initialize();
    final source = Directory(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Selected directory does not exist.', sourcePath);
    }
    final name = p.basename(source.path);
    final destination = Directory(p.join(layout.projects.path, name));
    if (await destination.exists()) {
      throw FileSystemException(
        'A project with this name already exists.',
        destination.path,
      );
    }
    await _copyDirectory(source, destination);
    return destination;
  }

  Future<Directory> importZip(String zipPath) async {
    final layout = await StorageService.initialize();
    final zip = File(zipPath);
    final name = p.basenameWithoutExtension(zip.path);
    final destination = Directory(p.join(layout.projects.path, name));
    await destination.create(recursive: true);
    await FileService.importZip(zip, destination);
    return destination;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final out = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(out));
      } else if (entity is File) {
        await entity.copy(out);
      }
    }
  }
}
