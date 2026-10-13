import 'dart:async';
import 'dart:io';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/protocol.dart';
import '../core/proximity_detector.dart';

enum ProximityStatus { off, starting, running, unsupported, bluetoothOff, denied }

/// Detects when another Kdrop phone is held right next to this one.
///
/// Every device advertises a BLE service UUID that carries its device id and
/// continuously scans for the others. The signal strength (RSSI) of each
/// advertisement is fed into a [ProximityDetector], which decides when two
/// phones are close enough to count as "touching".
class ProximityService {
  ProximityService({ProximityDetector? detector})
      : detector = detector ?? ProximityDetector();

  final ProximityDetector detector;
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  final StreamController<String> _touches = StreamController<String>.broadcast();
  final StreamController<Map<String, double>> _signals =
      StreamController<Map<String, double>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  Timer? _pruneTimer;
  String? _deviceId;
  final Map<String, DateTime> _lastSeenStamp = {};

  ProximityStatus _status = ProximityStatus.off;
  final StreamController<ProximityStatus> _statusController =
      StreamController<ProximityStatus>.broadcast();

  /// Device ids of phones that were just brought together with this one.
  Stream<String> get touches => _touches.stream;

  /// Smoothed RSSI per nearby device id, emitted on every scan update.
  Stream<Map<String, double>> get signals => _signals.stream;
  Stream<ProximityStatus> get statusChanges => _statusController.stream;
  ProximityStatus get status => _status;

  Future<ProximityStatus> start(String deviceId) async {
    _deviceId = deviceId;
    _setStatus(ProximityStatus.starting);

    if (!await FlutterBluePlus.isSupported) {
      return _setStatus(ProximityStatus.unsupported);
    }
    if (!await _requestPermissions()) {
      return _setStatus(ProximityStatus.denied);
    }

    _adapterSub ??= FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _startRadio();
      } else if (state == BluetoothAdapterState.off) {
        _stopRadio();
        _setStatus(ProximityStatus.bluetoothOff);
      }
    });

    final state = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
    if (state != BluetoothAdapterState.on) {
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {
          return _setStatus(ProximityStatus.bluetoothOff);
        }
      } else {
        return _setStatus(ProximityStatus.bluetoothOff);
      }
    }
    await _startRadio();
    return _status;
  }

  Future<void> stop() async {
    await _adapterSub?.cancel();
    _adapterSub = null;
    await _stopRadio();
    _setStatus(ProximityStatus.off);
  }

  Future<void> dispose() async {
    await stop();
    await _touches.close();
    await _signals.close();
    await _statusController.close();
  }

  bool _radioRunning = false;

  Future<void> _startRadio() async {
    final id = _deviceId;
    if (id == null || _radioRunning) return;
    _radioRunning = true;
    try {
      await _peripheral.start(
        advertiseData: AdvertiseDataCore(serviceUuid: bleUuidForDevice(id)),
        androidSettings: const AndroidAdvertiseSettings(
          advertiseSettings: AdvertiseSettings(
            advertiseMode: AdvertiseMode.advertiseModeLowLatency,
            txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
            connectable: false,
          ),
        ),
      );

      _scanSub = FlutterBluePlus.onScanResults.listen(_onResults, onError: (_) {});
      // No service filter: iOS can only filter on exact UUIDs, and ours embed
      // the device id. We match the prefix ourselves in _onResults.
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );
      _pruneTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final now = DateTime.now();
        if (detector.prune(now)) {
          _lastSeenStamp.removeWhere((key, _) => !detector.snapshot.containsKey(key));
          _signals.add(detector.snapshot);
        }
      });
      _setStatus(ProximityStatus.running);
    } catch (e) {
      _radioRunning = false;
      await _stopRadio();
      final denied = e.toString().toLowerCase().contains('permission');
      _setStatus(denied ? ProximityStatus.denied : ProximityStatus.unsupported);
    }
  }

  Future<void> _stopRadio() async {
    _radioRunning = false;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await _peripheral.stop();
    } catch (_) {}
    detector.reset();
    _lastSeenStamp.clear();
    if (!_signals.isClosed) _signals.add(const {});
  }

  void _onResults(List<ScanResult> results) {
    var changed = false;
    for (final result in results) {
      String? id;
      for (final uuid in result.advertisementData.serviceUuids) {
        id = deviceIdFromBleUuid(uuid.str128);
        if (id != null) break;
      }
      if (id == null || id == _deviceId) continue;
      // The result list repeats old entries; only feed fresh samples.
      if (_lastSeenStamp[id] == result.timeStamp) continue;
      _lastSeenStamp[id] = result.timeStamp;
      changed = true;
      if (detector.addSample(id, result.rssi, result.timeStamp)) {
        _touches.add(id);
      }
    }
    if (changed) _signals.add(detector.snapshot);
  }

  /// Asks for the advertise permission. Scan permissions (BLUETOOTH_SCAN on
  /// Android 12+, location on older versions) are requested by
  /// flutter_blue_plus itself when the scan starts.
  Future<bool> _requestPermissions() async {
    var state = await _peripheral.hasPermission();
    if (state != PeripheralBluetoothState.granted &&
        state != PeripheralBluetoothState.ready) {
      state = await _peripheral.requestPermission();
    }
    return state == PeripheralBluetoothState.granted ||
        state == PeripheralBluetoothState.ready ||
        state == PeripheralBluetoothState.turnedOff;
  }

  ProximityStatus _setStatus(ProximityStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
    return status;
  }
}
