import 'dart:async';

import 'package:flutter/material.dart';

import '../core/contact_card.dart';
import '../core/peer.dart';
import '../kdrop_controller.dart';
import '../services/proximity_service.dart';
import 'received_screen.dart';
import 'settings_screen.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets/radar_view.dart';
import 'widgets/touch_glow.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final KdropController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<KdropEvent>? _events;

  /// UI work (animations, sheets) is serialised so prompts don't pile up.
  Future<void> _uiQueue = Future.value();
  bool _touchInProgress = false;

  /// Device id whose touch card is showing, and a signal that closes it.
  String? _touchCardFor;
  final ValueNotifier<int> _closeTouchCard = ValueNotifier(0);

  KdropController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _events = c.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _events?.cancel();
    _closeTouchCard.dispose();
    super.dispose();
  }

  void _enqueue(Future<void> Function() job) {
    _uiQueue = _uiQueue.then((_) => mounted ? job() : null).catchError((Object _) {});
  }

  void _onEvent(KdropEvent event) {
    switch (event) {
      case TouchEvent():
        _onTouch(event);
      case IncomingOfferEvent():
        // The phone we just touched sent something itself: its offer replaces
        // the "share your contact?" card.
        if (event.offer.senderId == _touchCardFor) _closeTouchCard.value++;
        _enqueue(() async {
          if (!event.isAnswered) await showIncomingOfferSheet(context, event);
        });
      case ReceivedEvent():
        _enqueue(() => showReceivedSheet(context, event.item));
      case MessageEvent():
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(event.message),
          backgroundColor: event.isError ? KColors.pink.withValues(alpha: 0.9) : null,
        ));
    }
  }

  /// Phones were brought together: play the glow right away, then either send
  /// the staged share or offer to swap contact cards.
  Future<void> _onTouch(TouchEvent event) async {
    if (_touchInProgress) return;
    _touchInProgress = true;
    try {
      await playTouchGlow(context);
      if (!mounted) return;
      final peer = event.peer;
      if (peer != null && c.staged != null) {
        unawaited(c.sendTo(peer, viaTouch: true));
        return;
      }
      _touchCardFor = event.deviceId;
      final TouchChoice? choice;
      try {
        choice = await showTouchCard(
          context,
          deviceId: event.deviceId,
          peer: peer,
          dismiss: _closeTouchCard,
        );
      } finally {
        _touchCardFor = null;
      }
      if (choice == TouchChoice.shareContact && peer != null) {
        unawaited(c.sendTo(peer, share: StagedShare.contact(c.myContactCard), viaTouch: true));
      }
    } finally {
      _touchInProgress = false;
    }
  }

  void _onTapPeer(Peer peer) {
    final transfer = c.outgoingFor(peer.id);
    if (transfer != null && transfer.isActive) {
      _confirmCancel(peer);
      return;
    }
    if (c.staged == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pick something to share first, or bring your phones together.'),
      ));
      return;
    }
    c.sendTo(peer);
  }

  Future<void> _confirmCancel(Peer peer) async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop sending to ${peer.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop')),
        ],
      ),
    );
    if (cancel == true) c.cancelSend(peer.id);
  }

  Future<void> _pickText() async {
    final text = await showComposeTextSheet(context);
    if (text != null) c.stageText(text);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final settings = c.settings!;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _Header(
                  name: settings.deviceName,
                  receivedCount: c.received.length,
                  onSettings: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(controller: c),
                  )),
                  onReceived: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ReceivedScreen(controller: c),
                  )),
                ),
                _StatusPill(controller: c),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: c.refresh,
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: RadarView(
                              selfId: settings.deviceId,
                              selfInitials: ContactCard(name: settings.deviceName).initials,
                              peers: c.peers,
                              closenessOf: c.closenessFor,
                              transferOf: c.outgoingFor,
                              onTapPeer: _onTapPeer,
                              // Long-press plays the touch flow without Bluetooth,
                              // useful on emulators and for demos.
                              onLongPressPeer: c.simulateTouch,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (c.incomingTransfers.isNotEmpty) _IncomingProgress(controller: c),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: c.staged == null
                      ? const SizedBox.shrink()
                      : _StagedBar(staged: c.staged!, onClear: c.clearStaged),
                ),
                _ShareTray(
                  onMedia: () => c.pickFiles(media: true),
                  onFiles: () => c.pickFiles(),
                  onContact: c.stageMyContact,
                  onText: _pickText,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.receivedCount,
    required this.onSettings,
    required this.onReceived,
  });

  final String name;
  final int receivedCount;
  final VoidCallback onSettings;
  final VoidCallback onReceived;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: KColors.accentGradient.createShader,
                  child: const Text(
                    'Kdrop',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                Text(
                  'Visible as “$name”',
                  style: const TextStyle(color: KColors.textDim),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Received',
            onPressed: onReceived,
            icon: Badge(
              isLabelVisible: receivedCount > 0,
              label: Text('$receivedCount'),
              child: const Icon(Icons.inbox_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettings,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.controller});

  final KdropController controller;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color color) = controller.networkError != null
        ? (Icons.wifi_off, 'Wi-Fi sharing unavailable', KColors.pink)
        : switch (controller.proximityStatus) {
            ProximityStatus.running => (
                Icons.sensors,
                'Bring phones together to share',
                KColors.cyan,
              ),
            ProximityStatus.starting || ProximityStatus.off => (
                Icons.bluetooth_searching,
                'Starting Bluetooth…',
                KColors.textDim,
              ),
            ProximityStatus.bluetoothOff => (
                Icons.bluetooth_disabled,
                'Turn on Bluetooth for touch-to-share',
                KColors.pink,
              ),
            ProximityStatus.denied => (
                Icons.bluetooth_disabled,
                'Allow Bluetooth for touch-to-share',
                KColors.pink,
              ),
            ProximityStatus.unsupported => (
                Icons.bluetooth_disabled,
                'Touch-to-share unavailable on this device',
                KColors.textDim,
              ),
          };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: color, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _IncomingProgress extends StatelessWidget {
  const _IncomingProgress({required this.controller});

  final KdropController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final session in controller.incomingTransfers)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receiving ${session.offer.summary} from ${session.offer.senderName}',
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: session.progress, minHeight: 6),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StagedBar extends StatelessWidget {
  const _StagedBar({required this.staged, required this.onClear});

  final StagedShare staged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          KColors.cyan.withValues(alpha: 0.18),
          KColors.violet.withValues(alpha: 0.18),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KColors.cyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.send_rounded, color: KColors.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staged.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Text(
                  'Tap a device, or hold your phones together',
                  style: TextStyle(color: KColors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(onPressed: onClear, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

class _ShareTray extends StatelessWidget {
  const _ShareTray({
    required this.onMedia,
    required this.onFiles,
    required this.onContact,
    required this.onText,
  });

  final VoidCallback onMedia;
  final VoidCallback onFiles;
  final VoidCallback onContact;
  final VoidCallback onText;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: KColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _TrayButton(icon: Icons.photo_library_outlined, label: 'Photos', onTap: onMedia),
          _TrayButton(icon: Icons.folder_outlined, label: 'Files', onTap: onFiles),
          _TrayButton(icon: Icons.contact_page_outlined, label: 'Contact', onTap: onContact),
          _TrayButton(icon: Icons.link, label: 'Text / Link', onTap: onText),
        ],
      ),
    );
  }
}

class _TrayButton extends StatelessWidget {
  const _TrayButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: KColors.surfaceHigh,
              ),
              child: Icon(icon, color: KColors.cyan),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
