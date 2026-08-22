import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `flutter test` runs without real platform channels, so path_provider
/// (used by StorageService to find the app's documents directory) would
/// throw MissingPluginException. This isn't faking path_provider's
/// behavior — it's pointing it at a real temporary directory on the test
/// runner's actual filesystem, so StorageService's directory-creation
/// code performs genuine `dart:io` operations during the test, the same
/// way it would on a device, just rooted somewhere temporary.
Future<Directory> mockPathProvider() async {
  final tempDir = await Directory.systemTemp.createTemp('flde_test_');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    },
  );
  return tempDir;
}
