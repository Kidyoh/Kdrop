import 'contact_card.dart';
import 'protocol.dart';

enum PayloadKind { files, contact, text }

/// Metadata for one file announced in an [Offer].
class FileMeta {
  const FileMeta({required this.name, required this.size});

  final String name;

  /// Size in bytes, or -1 when the sender could not determine it.
  final int size;

  Map<String, dynamic> toJson() => {'name': name, 'size': size};

  factory FileMeta.fromJson(Map<String, dynamic> json) => FileMeta(
        name: json['name'] as String,
        size: (json['size'] as num?)?.toInt() ?? -1,
      );
}

/// What a sender proposes to share. Contacts and text travel inline with the
/// offer; files are uploaded separately once the receiver accepts.
class Offer {
  const Offer({
    required this.senderId,
    required this.senderName,
    required this.kind,
    this.files = const [],
    this.contact,
    this.text,
    this.viaTouch = false,
    this.version = kProtocolVersion,
  });

  final String senderId;
  final String senderName;
  final PayloadKind kind;
  final List<FileMeta> files;
  final ContactCard? contact;
  final String? text;

  /// True when the share was triggered by bringing the phones together.
  final bool viaTouch;
  final int version;

  int get totalBytes {
    var total = 0;
    for (final f in files) {
      if (f.size < 0) return -1;
      total += f.size;
    }
    return total;
  }

  /// One-line human summary, e.g. "3 files", "a contact", "a link".
  String get summary {
    switch (kind) {
      case PayloadKind.files:
        return files.length == 1 ? files.first.name : '${files.length} files';
      case PayloadKind.contact:
        return 'a contact card';
      case PayloadKind.text:
        final t = text?.trim() ?? '';
        return Uri.tryParse(t)?.hasScheme == true && !t.contains(' ')
            ? 'a link'
            : 'some text';
    }
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'senderId': senderId,
        'senderName': senderName,
        'kind': kind.name,
        if (files.isNotEmpty) 'files': files.map((f) => f.toJson()).toList(),
        if (contact != null) 'contact': contact!.toJson(),
        if (text != null) 'text': text,
        'viaTouch': viaTouch,
      };

  /// Throws [FormatException] when the payload is malformed.
  factory Offer.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'];
    final kind = PayloadKind.values.where((k) => k.name == kindName).firstOrNull;
    if (kind == null) throw FormatException('unknown kind: $kindName');
    final senderId = json['senderId'];
    final senderName = json['senderName'];
    if (senderId is! String || senderName is! String) {
      throw const FormatException('missing sender');
    }
    final files = (json['files'] as List<dynamic>? ?? const [])
        .map((f) => FileMeta.fromJson(f as Map<String, dynamic>))
        .toList();
    final contactJson = json['contact'] as Map<String, dynamic>?;
    final offer = Offer(
      version: (json['version'] as num?)?.toInt() ?? kProtocolVersion,
      senderId: senderId,
      senderName: senderName,
      kind: kind,
      files: files,
      contact: contactJson == null ? null : ContactCard.fromJson(contactJson),
      text: json['text'] as String?,
      viaTouch: json['viaTouch'] as bool? ?? false,
    );
    switch (kind) {
      case PayloadKind.files:
        if (files.isEmpty) throw const FormatException('no files');
      case PayloadKind.contact:
        if (offer.contact == null) throw const FormatException('no contact');
      case PayloadKind.text:
        if (offer.text == null) throw const FormatException('no text');
    }
    return offer;
  }
}
