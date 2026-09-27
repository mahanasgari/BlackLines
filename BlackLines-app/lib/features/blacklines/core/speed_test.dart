import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Latency, download and upload against Cloudflare's speed-test endpoints.
///
/// [proxyPort] routes the test through the engine's local mixed proxy (i.e.
/// through the VPN); null tests the direct connection. The app's own traffic
/// bypasses the tunnel, so the direct test measures the plain network even
/// while connected.
class SpeedTest {
  SpeedTest({this.proxyPort});

  final int? proxyPort;

  static const _host = 'speed.cloudflare.com';
  static const _phaseLimit = Duration(seconds: 7);

  HttpClient? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  HttpClient _newClient() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15);
    final port = proxyPort;
    c.findProxy = (_) => port == null ? 'DIRECT' : 'PROXY 127.0.0.1:$port';
    return _client = c;
  }

  /// Round-trip time of a tiny request on a warm connection, in ms.
  Future<int> ping() async {
    final c = _newClient();
    try {
      final times = <int>[];
      for (var i = 0; i < 4 && !_cancelled; i++) {
        final sw = Stopwatch()..start();
        final req = await c.getUrl(Uri.https(_host, '/__down', {'bytes': '0'}));
        final res = await req.close().timeout(const Duration(seconds: 8));
        await res.drain<void>();
        if (i > 0) times.add(sw.elapsedMilliseconds); // first one pays for TLS
      }
      if (times.isEmpty) throw const SocketException('cancelled');
      times.sort();
      return times.first;
    } finally {
      c.close(force: true);
    }
  }

  /// Download speed in Mbps; [onProgress] gets the running figure.
  ///
  /// Cloudflare refuses downloads over 25 MB, so fast links chain requests
  /// until the time limit.
  Future<double> download(void Function(double mbps) onProgress) async {
    final c = _newClient();
    var bytes = 0;
    var lastReport = 0;
    final sw = Stopwatch()..start();
    try {
      while (!_cancelled && sw.elapsed < _phaseLimit) {
        final req = await c.getUrl(Uri.https(_host, '/__down', {'bytes': '25000000'}));
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
        await for (final data in res) {
          bytes += data.length;
          final ms = sw.elapsedMilliseconds;
          if (ms - lastReport >= 250) {
            lastReport = ms;
            onProgress(_mbps(bytes, ms));
          }
          if (_cancelled || sw.elapsed >= _phaseLimit) break;
        }
      }
      return _mbps(bytes, sw.elapsedMilliseconds);
    } finally {
      c.close(force: true);
    }
  }

  /// Upload speed in Mbps; [onProgress] gets the running figure.
  ///
  /// Sends bodies that start at 256 KB and double while they finish quickly,
  /// counting each only once the server has answered: timing socket writes
  /// would measure the local proxy, not the network. A body that times out
  /// ends the test with what was measured so far.
  Future<double> upload(void Function(double mbps) onProgress) async {
    final c = _newClient();
    var size = 256 * 1024;
    var bytes = 0;
    final sw = Stopwatch()..start();
    try {
      while (!_cancelled && sw.elapsed < _phaseLimit) {
        final started = sw.elapsedMilliseconds;
        try {
          final req = await c.postUrl(Uri.https(_host, '/__up'));
          req.headers.contentType = ContentType.binary;
          req.contentLength = size;
          req.add(Uint8List(size));
          final res = await req.close().timeout(const Duration(seconds: 12));
          await res.drain<void>().timeout(const Duration(seconds: 5));
          if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
        } on TimeoutException {
          if (bytes == 0) rethrow;
          break;
        }
        bytes += size;
        onProgress(_mbps(bytes, sw.elapsedMilliseconds));
        if (sw.elapsedMilliseconds - started < 1500 && size < 8 * 1024 * 1024) size *= 2;
      }
      return _mbps(bytes, sw.elapsedMilliseconds);
    } finally {
      c.close(force: true);
    }
  }

  static double _mbps(int bytes, int ms) => ms <= 0 ? 0 : bytes * 8 / (ms / 1000) / 1e6;
}
