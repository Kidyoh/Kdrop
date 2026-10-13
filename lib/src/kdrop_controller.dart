import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'core/contact_card.dart';
import 'core/offer.dart';
import 'core/peer.dart';
import 'core/proximity_detector.dart';
import 'services/discovery_service.dart';
import 'services/proximity_service.dart';
import 'services/settings_store.dart';
import 'services/transfer_client.dart';
import 'services/transfer_models.dart';
import 'services/transfer_server.dart';

/// Something the user has picked and is ready to send.
class StagedShare {
  StagedShare.files(this.files)
      : kind = PayloadKind.files,
        text = null,
        contact = null;
  StagedShare.text(String this.text)
      : kind = PayloadKind.text,
        files = const [],
        contact = null;
  StagedShare.contact(ContactCard this.contact)
      : kind = PayloadKind.contact,
        files = const [],
        text = null;

  final PayloadKind kind;
  final List<OutgoingFile> files;
  final String? text;
  final ContactCard? contact;

  String get label {
    switch (kind) {
      case PayloadKind.files:
        return files.length == 1 ? files.first.name : '${files.length} files';
      case PayloadKind.text:
        final t = text!.trim().replaceAll('\n', ' ');
        return t.length > 40 ? '${t.substring(0, 40)}…' : t;
      case PayloadKind.contact:
        return 'Contact: ${contact!.name}';
    }
  }
}

enum OutgoingStatus { waiting, sending, done, declined, failed }

class OutgoingTransfer {
  OutgoingTransfer(this.peer);

  final Peer peer;
  final CancelToken cancel = CancelToken();
  OutgoingStatus status = OutgoingStatus.waiting;

  /// 0..1 while sending files, null when unknown.
  double? progress;
  String? error;

  bool get isActive =>
      status == OutgoingStatus.waiting || status == OutgoingStatus.sending;
}

class ReceivedItem {
  ReceivedItem({
    required this.senderName,
    required this.kind,
    this.files = const [],
    this.contact,
    this.text,
  }) : at = DateTime.now();

  final String senderName;
  final PayloadKind kind;
  final List<File> files;
  final ContactCard? contact;
  final String? text;
  final DateTime at;
}

/// Events the UI reacts to with sheets, animations and snackbars.
sealed class KdropEvent {}

/// Another phone was brought up against this one.
class TouchEvent extends KdropEvent {
  TouchEvent(this.deviceId, this.peer);

  final String deviceId;

  /// Null if the phone is in Bluetooth range but not yet found on Wi-Fi.
  final Peer? peer;
}

/// Someone wants to send something; complete [respond] to answer.
class IncomingOfferEvent extends KdropEvent {
  IncomingOfferEvent(this.offer, this._completer);

  final Offer offer;
  final Completer<bool> _completer;

  bool get isAnswered => _completer.isCompleted;

  void respond(bool accept) {
    if (!_completer.isCompleted) _completer.complete(accept);
  }
}

class ReceivedEvent extends KdropEvent {
  ReceivedEvent(this.item);

  final ReceivedItem item;
}

class MessageEvent extends KdropEvent {
  MessageEvent(this.message, {this.isError = false});

  final String message;
  final bool isError;
}

/// Glue between discovery, proximity, transfers and the UI.
class KdropController extends ChangeNotifier {
  KdropController({
    SettingsStore? store,
    DiscoveryService? discovery,
    ProximityService? proximity,
    TransferClient? client,
  })  : _store = store ?? SettingsStore(),
        _discovery = discovery ?? DiscoveryService(),
        _proximity = proximity ?? ProximityService(),
        _client = client ?? TransferClient();

  final SettingsStore _store;
  final DiscoveryService _discovery;
  final ProximityService _proximity;
  final TransferClient _client;
  late final TransferServer _server = TransferServer(
    decide: _decide,
    receiveDirectory: receiveDirectory,
    onSession: _onReceiveSession,
  );

  final StreamController<KdropEvent> _events = StreamController.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];

  KdropSettings? _settings;
  List<Peer> _peers = const [];
  Map<String, double> _signals = const {};
  StagedShare? _staged;
  final Map<String, OutgoingTransfer> _outgoing = {};
  final Map<String, ReceiveSession> _incoming = {};
  final List<ReceivedItem> _received = [];
  bool _started = false;
  String? _networkError;

  Stream<KdropEvent> get events => _events.stream;
  KdropSettings? get settings => _settings;
  bool get isReady => _settings != null;
  bool get isOnboarded => _settings?.isOnboarded ?? false;
  List<Peer> get peers => _peers;
  StagedShare? get staged => _staged;
  ProximityStatus get proximityStatus => _proximity.status;
  String? get networkError => _networkError;
  List<ReceivedItem> get received => List.unmodifiable(_received.reversed);
  Iterable<ReceiveSession> get incomingTransfers => _incoming.values;

  OutgoingTransfer? outgoingFor(String peerId) => _outgoing[peerId];
  double? signalFor(String peerId) => _signals[peerId];
  Closeness? closenessFor(String peerId) => _proximity.detector.closeness(peerId);

  /// Strongest nearby Kdrop signal, for the sensitivity calibration UI.
  double? get strongestSignal =>
      _signals.values.isEmpty ? null : _signals.values.reduce((a, b) => a > b ? a : b);

  Future<void> load() async {
    _settings = await _store.load();
    _proximity.detector.touchThreshold = _settings!.touchThreshold;
    _proximity.detector.releaseThreshold = _settings!.touchThreshold - 15;
    notifyListeners();
    if (isOnboarded) await start();
  }

  /// Starts the receiver, the LAN discovery and the Bluetooth proximity radio.
  Future<void> start() async {
    if (_started || _settings == null) return;
    _started = true;
    final s = _settings!;

    _subs.add(_discovery.peers.listen((peers) {
      _peers = peers;
      notifyListeners();
    }));
    _subs.add(_proximity.signals.listen((signals) {
      _signals = signals;
      notifyListeners();
    }));
    _subs.add(_proximity.statusChanges.listen((_) => notifyListeners()));
    _subs.add(_proximity.touches.listen(_onTouch));
    _watchLifecycle();

    try {
      final port = await _server.start();
      await _discovery.start(deviceId: s.deviceId, deviceName: s.deviceName, port: port);
      _networkError = null;
    } catch (e) {
      _networkError = 'Could not start Wi-Fi sharing: $e';
    }
    notifyListeners();
    await _proximity.start(s.deviceId);
    notifyListeners();
  }

  Future<void> completeOnboarding(String deviceName, ContactCard contact) async {
    await updateSettings(_settings!.copyWith(deviceName: deviceName, contact: contact));
    await start();
  }

  Future<void> updateSettings(KdropSettings next) async {
    final previous = _settings;
    _settings = next;
    _proximity.detector.touchThreshold = next.touchThreshold;
    _proximity.detector.releaseThreshold = next.touchThreshold - 15;
    notifyListeners();
    await _store.save(next);
    final port = _server.port;
    if (_started && port != null && previous?.deviceName != next.deviceName) {
      await _discovery.updateName(
        deviceId: next.deviceId,
        deviceName: next.deviceName,
        port: port,
      );
    }
  }

  AppLifecycleListener? _lifecycle;

  void _watchLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        _discovery.refresh();
        _proximity.start(_settings!.deviceId).then((_) => notifyListeners());
      },
      // iOS stops BLE advertising in the background anyway; save battery.
      onPause: () => _proximity.stop(),
    );
  }

  Future<void> refresh() async {
    await _discovery.refresh();
    if (_proximity.status != ProximityStatus.running && _settings != null) {
      await _proximity.start(_settings!.deviceId);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- staging

  Future<bool> pickFiles({bool media = false}) async {
    final picked = await FilePicker.pickFiles(type: media ? FileType.media : FileType.any);
    if (picked.isEmpty) return false;
    final files = <OutgoingFile>[];
    for (final pf in picked) {
      final size = pf.lengthSync() ?? await pf.length() ?? -1;
      files.add(OutgoingFile(name: pf.name, size: size, openRead: pf.readAsByteStream));
    }
    stage(StagedShare.files(files));
    return true;
  }

  void stageText(String text) {
    if (text.trim().isEmpty) return;
    stage(StagedShare.text(text.trim()));
  }

  void stageMyContact() => stage(StagedShare.contact(myContactCard));

  /// The user's card, falling back to just the device name if they left it
  /// empty.
  ContactCard get myContactCard {
    final s = _settings!;
    return s.contact.isEmpty ? ContactCard(name: s.deviceName) : s.contact;
  }

  void stage(StagedShare share) {
    _staged = share;
    notifyListeners();
  }

  void clearStaged() {
    _staged = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- sending

  /// Sends [share] (or the staged share) to [peer].
  Future<void> sendTo(Peer peer, {StagedShare? share, bool viaTouch = false}) async {
    final payload = share ?? _staged;
    final s = _settings;
    if (payload == null || s == null) return;
    if (_outgoing[peer.id]?.isActive ?? false) return;

    final transfer = OutgoingTransfer(peer);
    _outgoing[peer.id] = transfer;
    notifyListeners();

    final offer = Offer(
      senderId: s.deviceId,
      senderName: s.deviceName,
      kind: payload.kind,
      files: payload.files.map((f) => f.meta).toList(),
      contact: payload.contact,
      text: payload.text,
      viaTouch: viaTouch,
    );

    try {
      final response = await _client.sendOffer(peer, offer, cancel: transfer.cancel);
      if (!response.accepted) {
        transfer.status = OutgoingStatus.declined;
      } else if (payload.kind == PayloadKind.files) {
        transfer.status = OutgoingStatus.sending;
        transfer.progress = 0;
        notifyListeners();
        var lastNotify = DateTime.now();
        await _client.uploadFiles(
          peer,
          response.token!,
          payload.files,
          cancel: transfer.cancel,
          onProgress: (sent, total) {
            transfer.progress = total > 0 ? sent / total : null;
            final now = DateTime.now();
            if (now.difference(lastNotify).inMilliseconds > 80) {
              lastNotify = now;
              notifyListeners();
            }
          },
        );
        transfer.progress = 1;
        transfer.status = OutgoingStatus.done;
      } else {
        transfer.status = OutgoingStatus.done;
      }
    } on TransferCancelledException {
      if (_outgoing[peer.id] == transfer) _outgoing.remove(peer.id);
      notifyListeners();
      return;
    } catch (e) {
      transfer.status = OutgoingStatus.failed;
      transfer.error = e.toString();
      _events.add(MessageEvent('Sending to ${peer.name} failed: $e', isError: true));
    }
    notifyListeners();

    // Let the "Sent" / "Declined" badge linger, then clear it.
    Timer(const Duration(seconds: 4), () {
      if (_outgoing[peer.id] == transfer && !transfer.isActive) {
        _outgoing.remove(peer.id);
        notifyListeners();
      }
    });
  }

  void cancelSend(String peerId) => _outgoing[peerId]?.cancel.cancel();

  // -------------------------------------------------------------- receiving

  Future<bool> _decide(IncomingOffer incoming) {
    final completer = Completer<bool>();
    _events.add(IncomingOfferEvent(incoming.offer, completer));
    return completer.future.then((accepted) {
      final offer = incoming.offer;
      if (accepted && offer.kind != PayloadKind.files) {
        _addReceived(ReceivedItem(
          senderName: offer.senderName,
          kind: offer.kind,
          contact: offer.contact,
          text: offer.text,
        ));
      }
      return accepted;
    });
  }

  void _onReceiveSession(ReceiveSession session) {
    switch (session.status) {
      case ReceiveStatus.receiving:
        _incoming[session.token] = session;
      case ReceiveStatus.completed:
        _incoming.remove(session.token);
        _addReceived(ReceivedItem(
          senderName: session.offer.senderName,
          kind: PayloadKind.files,
          files: session.savedFiles.whereType<File>().toList(),
        ));
      case ReceiveStatus.failed:
        _incoming.remove(session.token);
        _events.add(MessageEvent(
          'Transfer from ${session.offer.senderName} failed',
          isError: true,
        ));
    }
    notifyListeners();
  }

  void _addReceived(ReceivedItem item) {
    _received.add(item);
    _events.add(ReceivedEvent(item));
    notifyListeners();
  }

  /// Where received files are saved. On iOS this is visible in the Files app
  /// under "On My iPhone › Kdrop".
  static Future<Directory> receiveDirectory() async {
    Directory base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/Kdrop');
    await dir.create(recursive: true);
    return dir;
  }

  // ------------------------------------------------------------------ touch

  void _onTouch(String deviceId) {
    Peer? peer;
    for (final p in _peers) {
      if (p.id == deviceId) peer = p;
    }
    _events.add(TouchEvent(deviceId, peer));
  }

  /// Fakes a touch with the nearest peer. Handy for demos and emulators that
  /// have no Bluetooth.
  void simulateTouch(Peer peer) => _events.add(TouchEvent(peer.id, peer));

  @override
  void dispose() {
    _lifecycle?.dispose();
    for (final sub in _subs) {
      sub.cancel();
    }
    _server.stop();
    _discovery.dispose();
    _proximity.dispose();
    _client.close();
    _events.close();
    super.dispose();
  }
}
