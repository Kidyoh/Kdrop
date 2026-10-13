/// Another Kdrop device found on the local network.
class Peer {
  const Peer({
    required this.id,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
  });

  final String id;
  final String name;

  /// "ios" or "android".
  final String platform;
  final String host;
  final int port;

  Uri uri(String path) => Uri(scheme: 'http', host: host, port: port, path: path);

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  bool operator ==(Object other) =>
      other is Peer &&
      other.id == id &&
      other.name == name &&
      other.platform == platform &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(id, name, platform, host, port);

  @override
  String toString() => 'Peer($name, $id @ $host:$port)';
}
