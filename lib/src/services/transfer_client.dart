import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/offer.dart';
import '../core/peer.dart';
import 'transfer_models.dart';

class OfferResponse {
  const OfferResponse({required this.accepted, this.token});

  final bool accepted;

  /// Upload token, present only for accepted file offers.
  final String? token;
}

/// Sends offers and files to a peer's [TransferServer].
class TransferClient {
  TransferClient({HttpClient? httpClient})
      : _http = httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  final HttpClient _http;

  /// Sends [offer] and waits for the receiver to accept or decline.
  Future<OfferResponse> sendOffer(
    Peer peer,
    Offer offer, {
    Duration timeout = const Duration(seconds: 75),
    CancelToken? cancel,
  }) async {
    final token = cancel ?? CancelToken();
    HttpClientRequest? request;
    return token.guard(() => request?.abort(const TransferCancelledException()), () async {
      if (token.isCancelled) throw const TransferCancelledException();
      try {
        request = await _http.postUrl(peer.uri('/v1/offer'));
        request!.headers.contentType = ContentType.json;
        request!.write(jsonEncode(offer.toJson()));
        final response = await request!.close().timeout(timeout);
        final body = await _readJson(response);
        if (response.statusCode != HttpStatus.ok) {
          throw TransferException(body['error'] as String? ?? 'HTTP ${response.statusCode}');
        }
        return OfferResponse(
          accepted: body['accepted'] == true,
          token: body['token'] as String?,
        );
      } on TimeoutException {
        request?.abort();
        throw const TransferException('No response from receiver');
      } on TransferCancelledException {
        rethrow;
      } catch (e) {
        if (token.isCancelled) throw const TransferCancelledException();
        if (e is TransferException) rethrow;
        throw TransferException('Could not reach ${peer.name}: $e');
      }
    });
  }

  /// Streams [files] one after another. [onProgress] reports bytes handed to
  /// the network so far and the total (-1 if unknown).
  Future<void> uploadFiles(
    Peer peer,
    String uploadToken,
    List<OutgoingFile> files, {
    void Function(int sent, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final token = cancel ?? CancelToken();
    final total = files.any((f) => f.size < 0)
        ? -1
        : files.fold<int>(0, (sum, f) => sum + f.size);
    var sent = 0;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      HttpClientRequest? request;
      await token.guard(() => request?.abort(const TransferCancelledException()), () async {
        if (token.isCancelled) throw const TransferCancelledException();
        try {
          request = await _http.putUrl(peer.uri('/v1/files/$uploadToken/$i'));
          request!.headers.contentType = ContentType.binary;
          if (file.size >= 0) {
            request!.contentLength = file.size;
          } else {
            request!.bufferOutput = false;
          }
          await request!.addStream(file.openRead().map((chunk) {
            if (token.isCancelled) throw const TransferCancelledException();
            sent += chunk.length;
            onProgress?.call(sent, total);
            return chunk;
          }));
          final response = await request!.close();
          final body = await _readJson(response);
          if (response.statusCode != HttpStatus.ok) {
            throw TransferException(
              body['error'] as String? ?? 'HTTP ${response.statusCode}',
            );
          }
        } catch (e) {
          if (token.isCancelled || e is TransferCancelledException) {
            throw const TransferCancelledException();
          }
          if (e is TransferException) rethrow;
          throw TransferException('Sending ${file.name} failed: $e');
        }
      });
    }
  }

  void close() => _http.close(force: true);

  static Future<Map<String, dynamic>> _readJson(HttpClientResponse response) async {
    final text = await response.transform(utf8.decoder).join();
    if (text.isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}
