import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kdrop/src/core/contact_card.dart';
import 'package:kdrop/src/core/offer.dart';
import 'package:kdrop/src/core/peer.dart';
import 'package:kdrop/src/core/proximity_detector.dart';
import 'package:kdrop/src/kdrop_controller.dart';
import 'package:kdrop/src/ui/sheets.dart';
import 'package:kdrop/src/ui/theme.dart';
import 'package:kdrop/src/ui/widgets/radar_view.dart';
import 'package:kdrop/src/ui/widgets/touch_glow.dart';

Widget _app(Widget child) => MaterialApp(theme: buildTheme(), home: Scaffold(body: child));

const _peerA = Peer(id: 'aaaaaaaaaaaa', name: 'Sam Pixel', platform: 'android', host: '1.2.3.4', port: 1);
const _peerB = Peer(id: 'bbbbbbbbbbbb', name: 'Ana iPhone', platform: 'ios', host: '1.2.3.5', port: 1);

void main() {
  testWidgets('radar shows peers, status and handles taps', (tester) async {
    final tapped = <Peer>[];
    final sending = OutgoingTransfer(_peerA)
      ..status = OutgoingStatus.sending
      ..progress = 0.42;
    await tester.pumpWidget(_app(RadarView(
      selfId: 'cccccccccccc',
      selfInitials: 'ME',
      peers: const [_peerA, _peerB],
      closenessOf: (id) => id == _peerB.id ? Closeness.touching : null,
      transferOf: (id) => id == _peerA.id ? sending : null,
      onTapPeer: tapped.add,
    )));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Sam Pixel'), findsOneWidget);
    expect(find.text('Ana iPhone'), findsOneWidget);
    expect(find.text('Sending 42%'), findsOneWidget);
    expect(find.text('Right here'), findsOneWidget);
    expect(find.byIcon(Icons.apple), findsOneWidget);

    await tester.tap(find.text('Ana iPhone'));
    expect(tapped, [_peerB]);
  });

  testWidgets('radar shows a hint when nobody is around', (tester) async {
    await tester.pumpWidget(_app(RadarView(
      selfId: 'cccccccccccc',
      selfInitials: 'ME',
      peers: const [],
      closenessOf: (_) => null,
      transferOf: (_) => null,
      onTapPeer: (_) {},
    )));
    expect(find.textContaining('Looking for nearby devices'), findsOneWidget);
  });

  testWidgets('touch glow plays and completes', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      ctx = context;
      return const SizedBox.expand();
    })));
    var done = false;
    unawaited(playTouchGlow(ctx).then((_) => done = true));
    await tester.pump();
    expect(find.byType(TouchGlow), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump();
    expect(done, isTrue);
    expect(find.byType(TouchGlow), findsNothing);
  });

  test('glow painter repaints only when progress changes', () {
    expect(TouchGlowPainter(0.2).shouldRepaint(TouchGlowPainter(0.2)), isFalse);
    expect(TouchGlowPainter(0.2).shouldRepaint(TouchGlowPainter(0.3)), isTrue);
  });

  testWidgets('incoming offer sheet accepts and declines', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      ctx = context;
      return const SizedBox.expand();
    })));

    Future<bool> run(String button) async {
      final completer = Completer<bool>();
      final event = IncomingOfferEvent(
        const Offer(
          senderId: 'aaaaaaaaaaaa',
          senderName: 'Sam',
          kind: PayloadKind.contact,
          contact: ContactCard(name: 'Sam Lee', phone: '555-0100'),
        ),
        completer,
      );
      unawaited(showIncomingOfferSheet(ctx, event));
      await tester.pumpAndSettle();
      expect(find.text('wants to share a contact card'), findsOneWidget);
      expect(find.text('555-0100'), findsOneWidget);
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      return completer.future;
    }

    expect(await run('Accept'), isTrue);
    expect(await run('Decline'), isFalse);
  });

  testWidgets('touch card returns the choice or closes when dismissed', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      ctx = context;
      return const SizedBox.expand();
    })));

    final share = showTouchCard(ctx, deviceId: _peerA.id, peer: _peerA);
    await tester.pumpAndSettle();
    expect(find.text('Sam Pixel'), findsOneWidget);
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(await share, TouchChoice.shareContact);

    final dismiss = ValueNotifier(0);
    final closed = showTouchCard(ctx, deviceId: _peerA.id, peer: _peerA, dismiss: dismiss);
    await tester.pumpAndSettle();
    dismiss.value++;
    await tester.pumpAndSettle();
    expect(await closed, isNull);
    expect(find.text('Sam Pixel'), findsNothing);
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(50 * 1024 * 1024), '50 MB');
  });
}
