import 'package:flutter/material.dart';

import '../theme.dart';

/// Round gradient avatar with initials and an optional platform badge.
class KAvatar extends StatelessWidget {
  const KAvatar({
    super.key,
    required this.id,
    required this.initials,
    this.size = 64,
    this.platform,
    this.glow = 0,
  });

  final String id;
  final String initials;
  final double size;
  final String? platform;

  /// 0..1 halo intensity, used when a peer is very close.
  final double glow;

  @override
  Widget build(BuildContext context) {
    final badge = switch (platform) {
      'ios' => Icons.apple,
      'android' => Icons.android,
      _ => null,
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: KColors.avatarGradient(id),
              boxShadow: [
                if (glow > 0)
                  BoxShadow(
                    color: KColors.cyan.withValues(alpha: 0.6 * glow),
                    blurRadius: 24 * glow,
                    spreadRadius: 4 * glow,
                  ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.36,
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: KColors.surfaceHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(badge, size: size * 0.22, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}
