import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Speed test on Measurement Lab's NDT7 servers (the test behind Google's
/// built-in speed test): the nearest server is chosen by M-Lab's locate API,
/// then download and upload run over WebSockets.
///
/// [proxyPort] routes everything through the engine's local mixed proxy (i.e.
/// through the VPN, so the server nearest the VPN exit is used); null tests
/// the direct connection. The app's own traffic bypasses the tunnel, so the
/// direct test measures the plain network even while connected.
///
/// M-Lab publishes every test, including the client IP, as open data.
class SpeedTest {
  SpeedTest({this.proxyPort});

  final int? proxyPort;

  static const _locateUrl =
      'https://locate.measurementlab.net/v2/nearest/ndt/ndt7?client_name=blacklines-app&client_version=1';
  static const _protocol = 'net.measurementlab.ndt.v7';
  static const _phaseLimit = Duration(seconds: 10);

  bool _cancelled = false;
  final _clients = <HttpClient>[];
  final _sockets = <WebSocket>[];
  List<Map<String, dynamic>> _servers = const [];
  Map<String, dynamic>? _server;

  /// "City, CC" of the server in use, once known.
  String? get serverLabel {
    final loc = _server?['location'];
    if (loc is! Map) return null;
    return [loc['city'], loc['country']].whereType<String>().join(', ');
  }

  void cancel() {
    _cancelled = true;
    for (final c in _clients) {
      c.close(force: true);
    }
    for (final ws in _sockets) {
      ws.close();
    }
  }

  HttpClient _newClient() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15);
    final port = proxyPort;
    c.findProxy = (_) => port == null ? 'DIRECT' : 'PROXY 127.0.0.1:$port';
    _clients.add(c);
    return c;
  }

  /// Finds candidate servers and returns the round-trip time (ms) of small
  /// requests to the locate service on a warm connection.
  Future<int> locate() async {
    final c = _newClient();
    final times = <int>[];
    for (var i = 0; i < 3 && !_cancelled; i++) {
      final sw = Stopwatch()..start();
      final req = await c.getUrl(Uri.parse(_locateUrl));
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      if (i == 0) {
        final results = (jsonDecode(body) as Map)['results'];
        _servers = [
          for (final r in results is List ? results : const [])
            // Israeli servers are unreachable from many Iranian networks.
            if (r is Map<String, dynamic> && (r['location'] as Map?)?['country'] != 'IL') r,
        ];
        if (_servers.isEmpty) throw const SocketException('no M-Lab server');
      } else {
        times.add(sw.elapsedMilliseconds); // the first request pays for TLS
      }
    }
    c.close(force: true);
    if (times.isEmpty) throw const SocketException('cancelled');
    times.sort();
    return times.first;
  }

  Future<WebSocket> _open(Map<String, dynamic> server, String kind) async {
    final url = (server['urls'] as Map?)?['wss:///ndt/v7/$kind'];
    if (url is! String) throw const SocketException('no url');
    final ws = await WebSocket.connect(url, protocols: const [_protocol], customClient: _newClient())
        .timeout(const Duration(seconds: 12));
    _sockets.add(ws);
    // Closing mid-transfer surfaces socket errors here; they don't matter.
    unawaited(ws.done.then((_) {}, onError: (_) {}));
    return ws;
  }

  /// Download speed in Mbps, trying the located servers in order.
  Future<double> download(void Function(double mbps) onProgress) async {
    WebSocket? ws;
    for (final s in _servers) {
      if (_cancelled) break;
      try {
        ws = await _open(s, 'download');
        _server = s;
        break;
      } catch (_) {}
    }
    if (ws == null) throw const SocketException('no reachable M-Lab server');

    var bytes = 0;
    var lastReport = 0;
    final sw = Stopwatch()..start();
    final done = Completer<void>();
    final sub = ws.listen(
      (msg) {
        bytes += msg is String ? msg.length : (msg as List<int>).length;
        final ms = sw.elapsedMilliseconds;
        if (ms - lastReport >= 250) {
          lastReport = ms;
          onProgress(_mbps(bytes, ms));
        }
        if ((_cancelled || sw.elapsed >= _phaseLimit) && !done.isCompleted) done.complete();
      },
      onError: (Object e) => done.isCompleted ? null : done.completeError(e),
      onDone: () => done.isCompleted ? null : done.complete(),
      cancelOnError: true,
    );
    try {
      await done.future.timeout(_phaseLimit + const Duration(seconds: 5));
    } on TimeoutException {
      // Report what arrived.
    }
    final ms = sw.elapsedMilliseconds;
    await sub.cancel();
    unawaited(ws.close().then((_) {}, onError: (_) {}));
    if (bytes == 0) throw const SocketException('no data');
    return _mbps(bytes, ms);
  }

  /// Upload speed in Mbps. Uses the server's own byte counts: timing socket
  /// writes would measure the local proxy, not the network.
  Future<double> upload(void Function(double mbps) onProgress) async {
    final server = _server;
    if (server == null) throw const SocketException('no server');
    final ws = await _open(server, 'upload');

    double? serverMbps;
    final sub = ws.listen(
      (msg) {
        if (msg is! String) return;
        try {
          final tcp = (jsonDecode(msg) as Map)['TCPInfo'];
          final received = tcp is Map ? tcp['BytesReceived'] : null;
          final elapsedUs = tcp is Map ? tcp['ElapsedTime'] : null;
          if (received is num && elapsedUs is num && elapsedUs > 0) {
            serverMbps = received * 8 / elapsedUs; // bits per µs == Mbps
            onProgress(serverMbps!);
          }
        } catch (_) {}
      },
      onError: (_) {},
    );

    var sent = 0;
    final sw = Stopwatch()..start();
    // NDT7 client behaviour: 8 KB messages, doubling (up to 1 MB) while
    // smaller than 1/16 of the bytes sent. addStream applies backpressure.
    Stream<List<int>> body() async* {
      var size = 1 << 13;
      while (!_cancelled && sw.elapsed < _phaseLimit) {
        yield Uint8List(size);
        sent += size;
        if (size < (1 << 20) && size < sent / 16) size *= 2;
      }
    }

    try {
      await ws.addStream(body()).timeout(_phaseLimit + const Duration(seconds: 5));
    } on TimeoutException {
      // Slow link: fall through with the server's last report.
    }
    final ms = sw.elapsedMilliseconds;
    // On a slow link addStream may still be draining: closing would throw
    // "StreamSink is bound to a stream", so close best-effort.
    try {
      await ws.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    await sub.cancel();
    if (serverMbps == null && sent == 0) throw const SocketException('no data');
    return serverMbps ?? _mbps(sent, ms);
  }

  static double _mbps(int bytes, int ms) => ms <= 0 ? 0 : bytes * 8 / (ms / 1000) / 1e6;
}
