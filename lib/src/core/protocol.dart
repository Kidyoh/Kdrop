import 'dart:math';

/// mDNS / Bonjour service type every Kdrop device broadcasts on the LAN.
const String kServiceType = '_kdrop._tcp';

/// Bumped whenever the HTTP transfer protocol changes incompatibly.
const int kProtocolVersion = 1;

/// Every Kdrop BLE advertisement uses a 128-bit service UUID that starts with
/// this prefix ("KDROP" in ASCII) and ends with the 12 hex char device id.
///
/// iOS only lets apps advertise service UUIDs and a short local name, so the
/// device id is packed into the UUID itself. That way a single scan result is
/// enough to know *which* Kdrop device is next to us.
const String kBleUuidPrefix = '4b44524f-5000-4000-8000-';

final RegExp _deviceIdPattern = RegExp(r'^[0-9a-f]{12}$');

/// Generates a random 12 hex char device id.
String generateDeviceId([Random? random]) {
  final rng = random ?? Random.secure();
  return List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
}

bool isValidDeviceId(String id) => _deviceIdPattern.hasMatch(id);

/// The BLE service UUID advertised by the device with [deviceId].
String bleUuidForDevice(String deviceId) {
  assert(isValidDeviceId(deviceId), 'invalid device id: $deviceId');
  return '$kBleUuidPrefix$deviceId';
}

/// Extracts the device id from an advertised service UUID, or null if the UUID
/// does not belong to Kdrop.
String? deviceIdFromBleUuid(String uuid) {
  final lower = uuid.toLowerCase();
  if (!lower.startsWith(kBleUuidPrefix)) return null;
  final id = lower.substring(kBleUuidPrefix.length);
  return isValidDeviceId(id) ? id : null;
}
