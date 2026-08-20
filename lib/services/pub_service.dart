import '../core/runtime/process_executor.dart';
import '../models/process_result.dart';

class PubService {
  Future<ProcessResultModel> pubGet(String projectPath) {
    return ProcessExecutor.run(
      'flutter',
      ['pub', 'get'],
      workingDirectory: projectPath,
    );
  }

  Future<ProcessResultModel> pubAdd(String projectPath, String packageName) {
    return ProcessExecutor.run(
      'flutter',
      ['pub', 'add', packageName],
      workingDirectory: projectPath,
    );
  }

  Future<ProcessResultModel> dartPubGet(String projectPath) {
    return ProcessExecutor.run(
      'dart',
      ['pub', 'get'],
      workingDirectory: projectPath,
    );
  }
}
