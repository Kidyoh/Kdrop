import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/contact_card.dart';
import '../core/protocol.dart';

class KdropSettings {
  const KdropSettings({
    required this.deviceId,
    required this.deviceName,
    required this.contact,
    this.touchThreshold = defaultTouchThreshold,
  });

  static const double defaultTouchThreshold = -40;

  /// Stable random id, used in both the mDNS record and the BLE UUID.
  final String deviceId;

  /// Name other people see, e.g. "Sam's Pixel". Empty until onboarding.
  final String deviceName;
  final ContactCard contact;

  /// Smoothed RSSI (dBm) that counts as touching. Higher = phones must be
  /// closer.
  final double touchThreshold;

  bool get isOnboarded => deviceName.trim().isNotEmpty;

  KdropSettings copyWith({
    String? deviceName,
    ContactCard? contact,
    double? touchThreshold,
  }) {
    return KdropSettings(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      contact: contact ?? this.contact,
      touchThreshold: touchThreshold ?? this.touchThreshold,
    );
  }
}

class SettingsStore {
  static const _kId = 'device_id';
  static const _kName = 'device_name';
  static const _kContact = 'contact_card';
  static const _kThreshold = 'touch_threshold';

  Future<KdropSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kId);
    if (id == null || !isValidDeviceId(id)) {
      id = generateDeviceId();
      await prefs.setString(_kId, id);
    }
    var contact = const ContactCard(name: '');
    final contactJson = prefs.getString(_kContact);
    if (contactJson != null) {
      try {
        contact = ContactCard.fromJson(jsonDecode(contactJson) as Map<String, dynamic>);
      } catch (_) {}
    }
    return KdropSettings(
      deviceId: id,
      deviceName: prefs.getString(_kName) ?? '',
      contact: contact,
      touchThreshold:
          prefs.getDouble(_kThreshold) ?? KdropSettings.defaultTouchThreshold,
    );
  }

  Future<void> save(KdropSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kId, settings.deviceId);
    await prefs.setString(_kName, settings.deviceName);
    await prefs.setString(_kContact, jsonEncode(settings.contact.toJson()));
    await prefs.setDouble(_kThreshold, settings.touchThreshold);
  }
}
