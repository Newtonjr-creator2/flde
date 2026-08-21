import 'dart:io';

enum ConnectivityState { online, offline, unknown }

/// Detects real Internet reachability via an actual DNS lookup — not a
/// plugin-reported "connected to WiFi" flag, which can be true while
/// there's no real Internet access. This performs a genuine network
/// operation each time it's called.
class ConnectivityService {
  static Future<ConnectivityState> check({
    String probeHost = 'pub.dev',
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final result = await InternetAddress.lookup(probeHost).timeout(timeout);
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return ConnectivityState.online;
      }
      return ConnectivityState.offline;
    } on SocketException {
      return ConnectivityState.offline;
    } catch (_) {
      return ConnectivityState.unknown;
    }
  }
}
