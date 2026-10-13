import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/peer.dart';
import '../../core/proximity_detector.dart';
import '../../kdrop_controller.dart';
import '../theme.dart';
import 'avatar.dart';

/// AirDrop-style radar: this phone in the middle, pulsing rings, and nearby
/// phones orbiting around it. Phones with a stronger Bluetooth signal sit
/// closer to the centre.
class RadarView extends StatefulWidget {
  const RadarView({
    super.key,
    required this.selfId,
    required this.selfInitials,
    required this.peers,
    required this.closenessOf,
    required this.transferOf,
    required this.onTapPeer,
    this.onLongPressPeer,
  });

  final String selfId;
  final String selfInitials;
  final List<Peer> peers;
  final Closeness? Function(String id) closenessOf;
  final OutgoingTransfer? Function(String id) transferOf;
  final void Function(Peer peer) onTapPeer;
  final void Function(Peer peer)? onLongPressPeer;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static double _orbitFor(Closeness? c) => switch (c) {
        Closeness.touching => 0.34,
        Closeness.near => 0.5,
        Closeness.inRange => 0.66,
        Closeness.far || null => 0.8,
      };

  @override
  Widget build(BuildContext context) {
    final peers = [...widget.peers]..sort((a, b) => a.id.compareTo(b.id));
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final center = size.center(Offset.zero);
      final maxR = math.min(size.width, size.height) / 2 - 8;
      const bubble = 64.0;
      const labelWidth = 96.0;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) =>
                  CustomPaint(painter: _RadarPainter(_pulse.value, maxR)),
            ),
          ),
          Positioned(
            left: center.dx - 40,
            top: center.dy - 40,
            child: KAvatar(id: widget.selfId, initials: widget.selfInitials, size: 80, glow: 0.6),
          ),
          for (var i = 0; i < peers.length; i++)
            _positioned(
              peers[i],
              index: i,
              count: peers.length,
              center: center,
              maxR: maxR,
              bubble: bubble,
              labelWidth: labelWidth,
            ),
          if (peers.isEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: center.dy + maxR * 0.42,
              child: const Text(
                'Looking for nearby devices…\nOpen Kdrop on another phone on the same Wi-Fi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: KColors.textDim, height: 1.4),
              ),
            ),
        ],
      );
    });
  }

  Widget _positioned(
    Peer peer, {
    required int index,
    required int count,
    required Offset center,
    required double maxR,
    required double bubble,
    required double labelWidth,
  }) {
    final closeness = widget.closenessOf(peer.id);
    final angle = -math.pi / 2 + 0.6 + index * 2 * math.pi / math.max(count, 1);
    final r = maxR * _orbitFor(closeness);
    final pos = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
    return AnimatedPositioned(
      key: ValueKey(peer.id),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      left: pos.dx - labelWidth / 2,
      top: pos.dy - bubble / 2,
      width: labelWidth,
      child: PeerBubble(
        peer: peer,
        size: bubble,
        closeness: closeness,
        transfer: widget.transferOf(peer.id),
        onTap: () => widget.onTapPeer(peer),
        onLongPress: widget.onLongPressPeer == null
            ? null
            : () => widget.onLongPressPeer!(peer),
      ),
    );
  }
}

class PeerBubble extends StatelessWidget {
  const PeerBubble({
    super.key,
    required this.peer,
    required this.size,
    required this.closeness,
    required this.transfer,
    required this.onTap,
    this.onLongPress,
  });

  final Peer peer;
  final double size;
  final Closeness? closeness;
  final OutgoingTransfer? transfer;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    final (String? status, Color statusColor) = switch (t?.status) {
      OutgoingStatus.waiting => ('Waiting…', KColors.textDim),
      OutgoingStatus.sending => (
          t!.progress == null ? 'Sending…' : 'Sending ${(t.progress! * 100).round()}%',
          KColors.cyan,
        ),
      OutgoingStatus.done => ('Sent', KColors.green),
      OutgoingStatus.declined => ('Declined', KColors.pink),
      OutgoingStatus.failed => ('Failed', KColors.pink),
      null => (
          closeness == Closeness.touching ? 'Right here' : null,
          KColors.cyan,
        ),
    };

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size + 10,
            height: size + 10,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (t != null && t.isActive)
                  SizedBox(
                    width: size + 10,
                    height: size + 10,
                    child: CircularProgressIndicator(
                      value: t.status == OutgoingStatus.sending ? t.progress : null,
                      strokeWidth: 3,
                      color: KColors.cyan,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                if (t?.status == OutgoingStatus.done)
                  Container(
                    width: size + 10,
                    height: size + 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: KColors.green, width: 3),
                    ),
                  ),
                KAvatar(
                  id: peer.id,
                  initials: peer.initials,
                  size: size,
                  platform: peer.platform,
                  glow: switch (closeness) {
                    Closeness.touching => 1,
                    Closeness.near => 0.4,
                    _ => 0,
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            peer.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          if (status != null)
            Text(status, style: TextStyle(fontSize: 11, color: statusColor)),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.maxR);

  final double t;
  final double maxR;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.05);
    for (final f in const [0.34, 0.5, 0.66, 0.8]) {
      canvas.drawCircle(center, maxR * f, guide);
    }

    // Three staggered pulses expanding outwards.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      final radius = 40 + phase * (maxR - 40);
      final alpha = (1 - phase) * 0.35;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color.lerp(KColors.cyan, KColors.violet, phase)!.withValues(alpha: alpha),
      );
    }

    // Soft glow behind this device.
    final glowRect = Rect.fromCircle(center: center, radius: maxR * 0.5);
    canvas.drawCircle(
      center,
      maxR * 0.5,
      Paint()
        ..shader = RadialGradient(colors: [
          KColors.violet.withValues(alpha: 0.18),
          Colors.transparent,
        ]).createShader(glowRect),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t || old.maxR != maxR;
}
