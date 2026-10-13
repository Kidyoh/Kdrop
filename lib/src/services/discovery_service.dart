import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../core/peer.dart';
import '../core/protocol.dart';

/// Announces this device on the local network and keeps a live list of other
/// Kdrop devices, using mDNS / Bonjour (Bonsoir wraps NSD on Android and the
/// Network framework on iOS).
class DiscoveryService {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;

  final Map<String, Peer> _peers = {};

  /// mDNS service name -> device id, so "lost" events can be mapped back.
  final Map<String, String> _serviceToId = {};
  final StreamController<List<Peer>> _peersController =
      StreamController<List<Peer>>.broadcast();

  String? _selfId;

  Stream<List<Peer>> get peers => _peersController.stream;
  List<Peer> get currentPeers => List.unmodifiable(_peers.values);

  Future<void> start({
    required String deviceId,
    required String deviceName,
    required int port,
  }) async {
    _selfId = deviceId;
    await _startBroadcast(deviceId: deviceId, deviceName: deviceName, port: port);
    await _startDiscovery();
  }

  /// Re-announces with a new display name.
  Future<void> updateName({
    required String deviceId,
    required String deviceName,
    required int port,
  }) async {
    await _broadcast?.stop();
    _broadcast = null;
    await _startBroadcast(deviceId: deviceId, deviceName: deviceName, port: port);
  }

  /// Restarts discovery, e.g. after the app returns to the foreground or the
  /// Wi-Fi network changes.
  Future<void> refresh() async {
    await _stopDiscovery();
    _peers.clear();
    _serviceToId.clear();
    _emit();
    await _startDiscovery();
  }

  Future<void> stop() async {
    await _stopDiscovery();
    await _broadcast?.stop();
    _broadcast = null;
  }

  Future<void> dispose() async {
    await stop();
    await _peersController.close();
  }

  Future<void> _startBroadcast({
    required String deviceId,
    required String deviceName,
    required int port,
  }) async {
    final service = BonsoirService(
      // Must be unique on the network; the friendly name travels in a TXT record.
      name: 'kdrop-$deviceId',
      type: kServiceType,
      port: port,
      attributes: {
        'id': deviceId,
        'name': _truncate(deviceName, 60),
        'platform': Platform.operatingSystem,
        'v': '$kProtocolVersion',
      },
    );
    final broadcast = BonsoirBroadcast(service: service, printLogs: false);
    _broadcast = broadcast;
    await broadcast.initialize();
    await broadcast.start();
  }

  Future<void> _startDiscovery() async {
    final discovery = BonsoirDiscovery(type: kServiceType, printLogs: false);
    _discovery = discovery;
    await discovery.initialize();
    _subscription = discovery.eventStream?.listen(_onEvent);
    await discovery.start();
  }

  Future<void> _stopDiscovery() async {
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        final discovery = _discovery;
        if (discovery != null) {
          event.service.resolve(discovery.serviceResolver);
        }
      case BonsoirDiscoveryServiceResolvedEvent():
        _addResolved(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        if (event.service.hostAddresses.isNotEmpty) _addResolved(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        final id = _serviceToId.remove(event.service.name);
        if (id != null && _peers.remove(id) != null) _emit();
      default:
        break;
    }
  }

  void _addResolved(BonsoirService service) {
    final attrs = service.attributes;
    final id = attrs['id'];
    if (id == null || !isValidDeviceId(id) || id == _selfId) return;
    final host = _pickAddress(service.hostAddresses);
    if (host == null) return;
    final peer = Peer(
      id: id,
      name: attrs['name']?.trim().isNotEmpty == true ? attrs['name']! : 'Kdrop device',
      platform: attrs['platform'] ?? 'unknown',
      host: host,
      port: service.port,
    );
    _serviceToId[service.name] = id;
    if (_peers[id] != peer) {
      _peers[id] = peer;
      _emit();
    }
  }

  void _emit() {
    if (!_peersController.isClosed) _peersController.add(currentPeers);
  }

  /// The transfer server listens on IPv4, so prefer IPv4 addresses.
  @visibleForTesting
  static String? pickAddressForTest(List<String> addresses) => _pickAddress(addresses);

  static String? _pickAddress(List<String> addresses) {
    final parsed = addresses
        .map(InternetAddress.tryParse)
        .whereType<InternetAddress>()
        .toList();
    final v4 = parsed.where((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback);
    if (v4.isNotEmpty) return v4.first.address;
    return null;
  }

  static String _truncate(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
