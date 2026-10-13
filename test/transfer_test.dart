import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdrop/src/core/contact_card.dart';
import 'package:kdrop/src/core/offer.dart';
import 'package:kdrop/src/core/peer.dart';
import 'package:kdrop/src/services/transfer_client.dart';
import 'package:kdrop/src/services/transfer_models.dart';
import 'package:kdrop/src/services/transfer_server.dart';

void main() {
  late Directory tmp;
  late Directory inbox;
  late TransferServer server;
  late TransferClient client;
  late Peer peer;
  late List<IncomingOffer> offers;
  late List<ReceiveSession> updates;
  var accept = true;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('kdrop_test');
    inbox = Directory('${tmp.path}/inbox');
    offers = [];
    updates = [];
    accept = true;
    server = TransferServer(
      decide: (offer) async {
        offers.add(offer);
        return accept;
      },
      receiveDirectory: () async => inbox,
      onSession: updates.add,
    );
    final port = await server.start(address: InternetAddress.loopbackIPv4);
    peer = Peer(id: 'aaaaaaaaaaaa', name: 'Test', platform: 'android', host: '127.0.0.1', port: port);
    client = TransferClient();
  });

  tearDown(() async {
    client.close();
    await server.stop();
    await tmp.delete(recursive: true);
  });

  Offer filesOffer(List<OutgoingFile> files) => Offer(
        senderId: 'bbbbbbbbbbbb',
        senderName: 'Sender',
        kind: PayloadKind.files,
        files: files.map((f) => f.meta).toList(),
      );

  OutgoingFile bytesFile(String name, List<int> data, {int? size}) => OutgoingFile(
        name: name,
        size: size ?? data.length,
        openRead: () => Stream.fromIterable([
          for (var i = 0; i < data.length; i += 1000)
            data.sublist(i, i + 1000 > data.length ? data.length : i + 1000),
        ]),
      );

  test('transfers several files end to end', () async {
    final big = List<int>.generate(250000, (i) => i % 251);
    final files = [
      bytesFile('photo.jpg', big),
      bytesFile('notes.txt', utf8.encode('hello kdrop')),
    ];
    final response = await client.sendOffer(peer, filesOffer(files));
    expect(response.accepted, isTrue);
    expect(response.token, isNotNull);
    expect(offers.single.offer.files.length, 2);

    final progress = <int>[];
    await client.uploadFiles(peer, response.token!, files,
        onProgress: (sent, total) {
      expect(total, big.length + 11);
      progress.add(sent);
    });

    expect(progress.last, big.length + 11);
    final session = updates.last;
    expect(session.status, ReceiveStatus.completed);
    expect(session.progress, 1);
    expect(await File('${inbox.path}/photo.jpg').readAsBytes(), big);
    expect(await File('${inbox.path}/notes.txt').readAsString(), 'hello kdrop');
  });

  test('declined offers return no token and save nothing', () async {
    accept = false;
    final files = [bytesFile('a.bin', [1, 2, 3])];
    final response = await client.sendOffer(peer, filesOffer(files));
    expect(response.accepted, isFalse);
    expect(response.token, isNull);
    expect(updates, isEmpty);
    expect(inbox.existsSync(), isFalse);
  });

  test('contact and text offers travel inline', () async {
    const card = ContactCard(name: 'Grace Hopper', phone: '555');
    final response = await client.sendOffer(
      peer,
      const Offer(senderId: 'bbbbbbbbbbbb', senderName: 'S', kind: PayloadKind.contact, contact: card),
    );
    expect(response.accepted, isTrue);
    expect(response.token, isNull);
    expect(offers.single.offer.contact, card);

    await client.sendOffer(
      peer,
      const Offer(senderId: 'bbbbbbbbbbbb', senderName: 'S', kind: PayloadKind.text, text: 'https://x.y'),
    );
    expect(offers.last.offer.text, 'https://x.y');
  });

  test('duplicate names get unique files, paths are sanitised', () async {
    await inbox.create(recursive: true);
    await File('${inbox.path}/dup.txt').writeAsString('old');
    final files = [
      bytesFile('dup.txt', utf8.encode('new')),
      bytesFile('../../escape.txt', utf8.encode('x')),
    ];
    final response = await client.sendOffer(peer, filesOffer(files));
    await client.uploadFiles(peer, response.token!, files);
    expect(await File('${inbox.path}/dup.txt').readAsString(), 'old');
    expect(await File('${inbox.path}/dup (1).txt').readAsString(), 'new');
    expect(File('${inbox.path}/escape.txt').existsSync(), isTrue);
    expect(File('${tmp.path}/escape.txt').existsSync(), isFalse);
  });

  test('size mismatch fails the session and removes partial files', () async {
    final files = [bytesFile('short.bin', [1, 2, 3], size: 10)];
    final response = await client.sendOffer(peer, filesOffer(files));
    await expectLater(
      client.uploadFiles(peer, response.token!, files),
      throwsA(isA<TransferException>()),
    );
    // The server notices the dropped upload asynchronously.
    for (var i = 0; i < 50 && updates.last.status != ReceiveStatus.failed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(updates.last.status, ReceiveStatus.failed);
    expect(inbox.listSync(), isEmpty);
  });

  test('unknown upload token is rejected', () async {
    await expectLater(
      client.uploadFiles(peer, 'nope', [bytesFile('a', [1])]),
      throwsA(isA<TransferException>()),
    );
  });

  test('cancelling an upload aborts it', () async {
    final controller = StreamController<List<int>>();
    final files = [
      OutgoingFile(name: 'slow.bin', size: 1000, openRead: () => controller.stream),
    ];
    final response = await client.sendOffer(peer, filesOffer(files));
    final cancel = CancelToken();
    final upload = client.uploadFiles(peer, response.token!, files, cancel: cancel);
    controller.add(List.filled(100, 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cancel.cancel();
    await expectLater(upload, throwsA(isA<TransferCancelledException>()));
    await controller.close();
  });

  test('sanitizeFileName', () {
    expect(sanitizeFileName('../../etc/passwd'), 'passwd');
    expect(sanitizeFileName(r'C:\Users\x\pic.png'), 'pic.png');
    expect(sanitizeFileName('.hidden'), 'hidden');
    expect(sanitizeFileName(''), 'file');
    expect(sanitizeFileName('a:b?.txt'), 'a_b_.txt');
    expect(sanitizeFileName('${'x' * 200}.jpeg').length, 120);
  });
}
