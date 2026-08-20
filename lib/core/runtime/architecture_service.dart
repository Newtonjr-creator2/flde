import 'dart:ffi';
import 'dart:io';

class ArchitectureService {
  static String get abi {
    if (!Platform.isAndroid) return Platform.operatingSystem;
    final current = Abi.current();
    if (current == Abi.androidArm64) return 'arm64-v8a';
    if (current == Abi.androidArm) return 'armeabi-v7a';
    if (current == Abi.androidX64) return 'x86_64';
    if (current == Abi.androidIA32) return 'x86';
    return current.toString();
  }

  static String get label {
    switch (abi) {
      case 'arm64-v8a':
        return 'ARM64';
      case 'armeabi-v7a':
        return 'ARM32';
      case 'x86_64':
        return 'x86_64';
      case 'x86':
        return 'x86';
      default:
        return abi;
    }
  }

  static bool compatible(String requested) =>
      requested == abi || requested == 'any' || requested == 'all';
}
