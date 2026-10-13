/// A minimal contact card, exchanged NameDrop-style and saved as a vCard.
class ContactCard {
  const ContactCard({
    required this.name,
    this.phone = '',
    this.email = '',
    this.organization = '',
  });

  final String name;
  final String phone;
  final String email;
  final String organization;

  bool get isEmpty =>
      name.trim().isEmpty && phone.trim().isEmpty && email.trim().isEmpty;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  ContactCard copyWith({
    String? name,
    String? phone,
    String? email,
    String? organization,
  }) {
    return ContactCard(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      organization: organization ?? this.organization,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'organization': organization,
      };

  factory ContactCard.fromJson(Map<String, dynamic> json) => ContactCard(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        organization: json['organization'] as String? ?? '',
      );

  /// Serialises the card as a vCard 3.0, which both iOS and Android can import
  /// straight into their Contacts apps.
  String toVCard() {
    final trimmed = name.trim();
    final space = trimmed.lastIndexOf(' ');
    final given = space == -1 ? trimmed : trimmed.substring(0, space);
    final family = space == -1 ? '' : trimmed.substring(space + 1);
    final lines = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'N:${_escape(family)};${_escape(given)};;;',
      'FN:${_escape(trimmed)}',
      if (organization.trim().isNotEmpty) 'ORG:${_escape(organization.trim())}',
      if (phone.trim().isNotEmpty) 'TEL;TYPE=CELL:${_escape(phone.trim())}',
      if (email.trim().isNotEmpty) 'EMAIL;TYPE=INTERNET:${_escape(email.trim())}',
      'END:VCARD',
    ];
    return '${lines.join('\r\n')}\r\n';
  }

  /// Parses the first card in a vCard document. Unknown properties are ignored.
  static ContactCard? fromVCard(String source) {
    // Unfold continuation lines (RFC 6350 §3.2).
    final unfolded = source.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    String? fn;
    String? n;
    var phone = '';
    var email = '';
    var org = '';
    var inCard = false;
    for (final raw in unfolded.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();
      if (upper == 'BEGIN:VCARD') {
        inCard = true;
        continue;
      }
      if (upper == 'END:VCARD') {
        if (inCard) break;
        continue;
      }
      if (!inCard) continue;
      final colon = _unescapedColon(line);
      if (colon == -1) continue;
      final key = line.substring(0, colon).split(';').first.toUpperCase();
      final value = line.substring(colon + 1);
      switch (key) {
        case 'FN':
          fn = _unescape(value);
        case 'N':
          n = value;
        case 'TEL':
          if (phone.isEmpty) phone = _unescape(value);
        case 'EMAIL':
          if (email.isEmpty) email = _unescape(value);
        case 'ORG':
          if (org.isEmpty) org = _unescape(_splitUnescaped(value).first);
      }
    }
    if (!inCard) return null;
    var name = fn ?? '';
    if (name.isEmpty && n != null) {
      final parts = _splitUnescaped(n).map(_unescape).toList();
      final family = parts.isNotEmpty ? parts[0] : '';
      final given = parts.length > 1 ? parts[1] : '';
      name = [given, family].where((p) => p.isNotEmpty).join(' ');
    }
    return ContactCard(name: name, phone: phone, email: email, organization: org);
  }

  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');

  static String _unescape(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == r'\' && i + 1 < value.length) {
        final next = value[++i];
        out.write(next == 'n' || next == 'N' ? '\n' : next);
      } else {
        out.write(c);
      }
    }
    return out.toString();
  }

  /// Splits a structured value on `;` while keeping escaped `\;` intact.
  static List<String> _splitUnescaped(String value) {
    final parts = <String>[];
    var start = 0;
    for (var i = 0; i < value.length; i++) {
      if (value[i] == r'\') {
        i++;
      } else if (value[i] == ';') {
        parts.add(value.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(value.substring(start));
    return parts;
  }

  static int _unescapedColon(String line) {
    for (var i = 0; i < line.length; i++) {
      if (line[i] == r'\') {
        i++;
      } else if (line[i] == ':') {
        return i;
      }
    }
    return -1;
  }

  @override
  bool operator ==(Object other) =>
      other is ContactCard &&
      other.name == name &&
      other.phone == phone &&
      other.email == email &&
      other.organization == organization;

  @override
  int get hashCode => Object.hash(name, phone, email, organization);

  @override
  String toString() => 'ContactCard($name, $phone, $email, $organization)';
}
