import 'dart:io';

class NetworkStatus {
  final bool online;
  final DateTime checkedAt;
  final String? detail;

  const NetworkStatus({
    required this.online,
    required this.checkedAt,
    this.detail,
  });
}

class NetworkService {
  static Future<NetworkStatus> check() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.headUrl(Uri.parse('https://pub.dev'));
      request.followRedirects = true;
      final response = await request.close().timeout(const Duration(seconds: 5));
      client.close(force: true);
      return NetworkStatus(
        online: response.statusCode >= 200 && response.statusCode < 500,
        checkedAt: DateTime.now(),
        detail: 'HTTPS probe: ${response.statusCode}',
      );
    } catch (e) {
      return NetworkStatus(
        online: false,
        checkedAt: DateTime.now(),
        detail: e.toString(),
      );
    }
  }
}
