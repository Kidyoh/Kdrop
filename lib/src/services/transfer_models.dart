import 'dart:io';

import '../core/offer.dart';

/// A file the user picked, ready to be streamed to a peer.
class OutgoingFile {
  OutgoingFile({required this.name, required this.size, required this.openRead});

  factory OutgoingFile.fromFile(File file) => OutgoingFile(
        name: file.uri.pathSegments.last,
        size: file.lengthSync(),
        openRead: file.openRead,
      );

  final String name;

  /// Size in bytes, or -1 if unknown.
  final int size;
  final Stream<List<int>> Function() openRead;

  FileMeta get meta => FileMeta(name: name, size: size);
}

/// An offer that arrived from another device and is waiting for the user.
class IncomingOffer {
  IncomingOffer({required this.offer, required this.remoteAddress});

  final Offer offer;
  final String remoteAddress;
}

enum ReceiveStatus { receiving, completed, failed }

/// Progress of an accepted file offer on the receiving side.
class ReceiveSession {
  ReceiveSession({
    required this.token,
    required this.offer,
    required this.directory,
  }) : savedFiles = List<File?>.filled(offer.files.length, null);

  final String token;
  final Offer offer;
  final Directory directory;

  /// Saved file for each offered index, null until it has fully arrived.
  final List<File?> savedFiles;
  int bytesReceived = 0;
  ReceiveStatus status = ReceiveStatus.receiving;
  String? error;

  bool get allReceived => savedFiles.every((f) => f != null);

  /// 0..1, or null if the sender did not know the total size.
  double? get progress {
    final total = offer.totalBytes;
    if (total < 0) return null;
    if (total == 0) return allReceived ? 1 : 0;
    return (bytesReceived / total).clamp(0, 1).toDouble();
  }
}

/// Lets the sender abort an in-flight upload.
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void _add(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void _remove(void Function() listener) => _listeners.remove(listener);
}

extension CancelTokenScope on CancelToken {
  /// Runs [body] with [onCancel] registered for the duration of the call.
  Future<T> guard<T>(void Function() onCancel, Future<T> Function() body) async {
    _add(onCancel);
    try {
      return await body();
    } finally {
      _remove(onCancel);
    }
  }
}

class TransferCancelledException implements Exception {
  const TransferCancelledException();

  @override
  String toString() => 'Transfer cancelled';
}

class TransferException implements Exception {
  const TransferException(this.message);

  final String message;

  @override
  String toString() => message;
}
