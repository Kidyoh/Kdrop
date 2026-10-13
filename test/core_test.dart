import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdrop/src/core/contact_card.dart';
import 'package:kdrop/src/core/offer.dart';
import 'package:kdrop/src/core/protocol.dart';
import 'package:kdrop/src/core/proximity_detector.dart';

void main() {
  group('device ids', () {
    test('round-trip through BLE service UUID', () {
      final id = generateDeviceId(Random(1));
      expect(isValidDeviceId(id), isTrue);
      final uuid = bleUuidForDevice(id);
      expect(uuid.length, 36);
      expect(deviceIdFromBleUuid(uuid), id);
      expect(deviceIdFromBleUuid(uuid.toUpperCase()), id);
    });

    test('ignores unrelated UUIDs', () {
      expect(deviceIdFromBleUuid('0000180d-0000-1000-8000-00805f9b34fb'), isNull);
      expect(deviceIdFromBleUuid('${kBleUuidPrefix}zzzzzzzzzzzz'), isNull);
    });
  });

  group('ContactCard vCard', () {
    test('round-trips with escaping', () {
      const card = ContactCard(
        name: 'Ada Lovelace',
        phone: '+44 20 7946 0000',
        email: 'ada@example.com',
        organization: 'Analytical Engines, Ltd; R&D',
      );
      final vcard = card.toVCard();
      expect(vcard, contains('N:Lovelace;Ada;;;'));
      expect(vcard, contains(r'ORG:Analytical Engines\, Ltd\; R&D'));
      expect(ContactCard.fromVCard(vcard), card);
    });

    test('parses folded lines and falls back to N', () {
      const source = 'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Hopper;Grace;;;\r\n'
          'TEL;TYPE=CELL:555\r\n 1234\r\nEND:VCARD\r\n';
      final card = ContactCard.fromVCard(source)!;
      expect(card.name, 'Grace Hopper');
      expect(card.phone, '5551234');
    });

    test('returns null for non-vCard input', () {
      expect(ContactCard.fromVCard('hello'), isNull);
    });
  });

  group('Offer', () {
    test('json round-trip', () {
      const offer = Offer(
        senderId: 'abcdefabcdef',
        senderName: 'Pixel',
        kind: PayloadKind.files,
        files: [FileMeta(name: 'a.jpg', size: 10), FileMeta(name: 'b.mov', size: 5)],
        viaTouch: true,
      );
      final back = Offer.fromJson(offer.toJson());
      expect(back.kind, PayloadKind.files);
      expect(back.files.map((f) => f.name), ['a.jpg', 'b.mov']);
      expect(back.totalBytes, 15);
      expect(back.viaTouch, isTrue);
      expect(back.summary, '2 files');
    });

    test('rejects malformed offers', () {
      expect(
        () => Offer.fromJson({'kind': 'files', 'senderId': 'x', 'senderName': 'y'}),
        throwsFormatException,
      );
      expect(() => Offer.fromJson({'kind': 'nope'}), throwsFormatException);
    });

    test('summary detects links', () {
      Offer text(String t) =>
          Offer(senderId: 'a', senderName: 'b', kind: PayloadKind.text, text: t);
      expect(text('https://flutter.dev').summary, 'a link');
      expect(text('hello there').summary, 'some text');
    });
  });

  group('ProximityDetector', () {
    final t0 = DateTime(2026);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('needs consecutive strong samples to fire', () {
      final d = ProximityDetector(requiredSamples: 3);
      expect(d.addSample('a', -30, at(0)), isFalse);
      expect(d.addSample('a', -30, at(100)), isFalse);
      expect(d.addSample('a', -30, at(200)), isTrue);
      expect(d.closeness('a'), Closeness.touching);
    });

    test('a single spike is smoothed away', () {
      final d = ProximityDetector(requiredSamples: 2);
      d.addSample('a', -70, at(0));
      expect(d.addSample('a', -20, at(100)), isFalse); // EMA -> -45
      expect(d.addSample('a', -70, at(200)), isFalse);
    });

    test('does not refire while held, re-arms after moving apart', () {
      final d = ProximityDetector(requiredSamples: 1, smoothing: 1, cooldown: Duration.zero);
      expect(d.addSample('a', -30, at(0)), isTrue);
      expect(d.addSample('a', -30, at(100)), isFalse);
      expect(d.addSample('a', -45, at(200)), isFalse); // between thresholds
      expect(d.addSample('a', -30, at(300)), isFalse); // still engaged
      d.addSample('a', -70, at(400)); // released
      expect(d.addSample('a', -30, at(500)), isTrue);
    });

    test('cooldown blocks rapid re-triggers', () {
      final d = ProximityDetector(
        requiredSamples: 1,
        smoothing: 1,
        cooldown: const Duration(seconds: 4),
      );
      expect(d.addSample('a', -30, at(0)), isTrue);
      d.addSample('a', -70, at(500));
      expect(d.addSample('a', -30, at(1000)), isFalse);
      d.addSample('a', -70, at(1500));
      expect(d.addSample('a', -30, at(4100)), isTrue);
    });

    test('tracks devices independently and prunes stale ones', () {
      final d = ProximityDetector(requiredSamples: 1, smoothing: 1);
      expect(d.addSample('a', -30, at(0)), isTrue);
      expect(d.addSample('b', -80, at(0)), isFalse);
      expect(d.closeness('b'), Closeness.far);
      d.addSample('b', -80, at(10000));
      expect(d.prune(at(10000)), isTrue);
      expect(d.snapshot.keys, ['b']);
    });
  });
}
