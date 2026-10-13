import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/offer.dart';
import 'transfer_models.dart';

typedef OfferDecider = Future<bool> Function(IncomingOffer offer);

/// Receives offers and files from other Kdrop devices over plain HTTP.
///
/// Protocol:
///  * `POST /v1/offer` with an [Offer] as JSON. The request is held open until
///    the user accepts or declines, then answered with
///    `{"accepted": bool, "token": String?}`.
///  * `PUT /v1/files/<token>/<index>` streams the raw bytes of file `index`
///    of an accepted file offer.
class TransferServer {
  TransferServer({
    required this.decide,
    required this.receiveDirectory,
    this.onSession,
    this.decisionTimeout = const Duration(seconds: 60),
    this.progressInterval = const Duration(milliseconds: 100),
  });

  final OfferDecider decide;
  final Future<Directory> Function() receiveDirectory;

  /// Called whenever a receive session starts, progresses, finishes or fails.
  final void Function(ReceiveSession session)? onSession;
  final Duration decisionTimeout;
  final Duration progressInterval;

  static const int _maxOfferBytes = 256 * 1024;

  HttpServer? _server;
  final Map<String, ReceiveSession> _sessions = {};
  final Random _random = Random.secure();

  int? get port => _server?.port;

  /// Starts listening on all IPv4 interfaces. Returns the bound port.
  Future<int> start({int port = 0, InternetAddress? address}) async {
    if (_server != null) return _server!.port;
    final server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((request) {
      _handle(request).catchError((Object _) {});
    });
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    for (final session in _sessions.values) {
      session.status = ReceiveStatus.failed;
      session.error = 'Receiver stopped';
      onSession?.call(session);
    }
    _sessions.clear();
  }

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    try {
      if (request.method == 'POST' &&
          segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'offer') {
        await _handleOffer(request);
      } else if (request.method == 'PUT' &&
          segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'files') {
        await _handleUpload(request, segments[2], segments[3]);
      } else if (request.method == 'GET' &&
          segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'ping') {
        await _json(request.response, HttpStatus.ok, {'ok': true});
      } else {
        await _json(request.response, HttpStatus.notFound, {'error': 'not found'});
      }
    } catch (e) {
      try {
        await _json(request.response, HttpStatus.internalServerError, {
          'error': e.toString(),
        });
      } catch (_) {
        // Response already started or socket gone.
      }
    }
  }

  Future<void> _handleOffer(HttpRequest request) async {
    final Offer offer;
    try {
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > _maxOfferBytes) {
          throw const FormatException('offer too large');
        }
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('offer must be an object');
      }
      offer = Offer.fromJson(decoded);
    } on FormatException catch (e) {
      await _json(request.response, HttpStatus.badRequest, {'error': e.message});
      return;
    }

    final incoming = IncomingOffer(
      offer: offer,
      remoteAddress: request.connectionInfo?.remoteAddress.address ?? '',
    );
    final accepted = await decide(incoming)
        .timeout(decisionTimeout, onTimeout: () => false)
        .catchError((Object _) => false);

    if (!accepted) {
      await _json(request.response, HttpStatus.ok, {'accepted': false});
      return;
    }

    String? token;
    if (offer.kind == PayloadKind.files) {
      token = _newToken();
      final session = ReceiveSession(
        token: token,
        offer: offer,
        directory: await receiveDirectory(),
      );
      _sessions[token] = session;
      onSession?.call(session);
    }
    await _json(request.response, HttpStatus.ok, {
      'accepted': true,
      'token': ?token,
    });
  }

  Future<void> _handleUpload(
    HttpRequest request,
    String token,
    String indexText,
  ) async {
    final session = _sessions[token];
    final index = int.tryParse(indexText);
    if (session == null) {
      await _drainAndRespond(request, HttpStatus.notFound, 'unknown transfer');
      return;
    }
    if (index == null || index < 0 || index >= session.offer.files.length) {
      await _drainAndRespond(request, HttpStatus.badRequest, 'bad file index');
      return;
    }
    if (session.savedFiles[index] != null) {
      await _drainAndRespond(request, HttpStatus.conflict, 'file already received');
      return;
    }

    final meta = session.offer.files[index];
    final file = await _uniqueFile(session.directory, sanitizeFileName(meta.name));
    final sink = file.openWrite();
    var received = 0;
    var lastNotify = DateTime.now();
    try {
      await sink.addStream(request.map((chunk) {
        received += chunk.length;
        session.bytesReceived += chunk.length;
        if (meta.size >= 0 && received > meta.size) {
          throw const TransferException('more data than announced');
        }
        final now = DateTime.now();
        if (now.difference(lastNotify) >= progressInterval) {
          lastNotify = now;
          onSession?.call(session);
        }
        return chunk;
      }));
      await sink.close();
      if (meta.size >= 0 && received != meta.size) {
        throw TransferException('expected ${meta.size} bytes, got $received');
      }
    } catch (e) {
      await sink.close().catchError((Object _) {});
      await file.delete().catchError((Object _) => file);
      _fail(session, e.toString());
      try {
        await _json(request.response, HttpStatus.badRequest, {'error': e.toString()});
      } catch (_) {}
      return;
    }

    session.savedFiles[index] = file;
    if (session.allReceived) {
      session.status = ReceiveStatus.completed;
      _sessions.remove(token);
    }
    onSession?.call(session);
    await _json(request.response, HttpStatus.ok, {'ok': true});
  }

  void _fail(ReceiveSession session, String error) {
    session.status = ReceiveStatus.failed;
    session.error = error;
    _sessions.remove(session.token);
    for (final saved in session.savedFiles) {
      saved?.delete().catchError((Object _) => saved);
    }
    onSession?.call(session);
  }

  Future<void> _drainAndRespond(HttpRequest request, int status, String error) async {
    await request.drain<void>().catchError((Object _) {});
    await _json(request.response, status, {'error': error});
  }

  String _newToken() =>
      List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();

  static Future<void> _json(HttpResponse response, int status, Object body) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  static Future<File> _uniqueFile(Directory dir, String name) async {
    await dir.create(recursive: true);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = File('${dir.path}/$name');
    var n = 1;
    while (await candidate.exists()) {
      candidate = File('${dir.path}/$stem ($n)$ext');
      n++;
    }
    return candidate;
  }
}

/// Strips anything that could escape the receive folder or upset a filesystem.
String sanitizeFileName(String name) {
  var base = name.split(RegExp(r'[/\\]')).last;
  base = base.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_').trim();
  while (base.startsWith('.')) {
    base = base.substring(1);
  }
  if (base.isEmpty) base = 'file';
  if (base.length > 120) {
    final dot = base.lastIndexOf('.');
    final ext = dot > 0 && base.length - dot <= 10 ? base.substring(dot) : '';
    base = base.substring(0, 120 - ext.length) + ext;
  }
  return base;
}
