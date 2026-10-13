import 'package:flutter/material.dart';

import '../core/contact_card.dart';
import '../kdrop_controller.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets/touch_glow.dart';

/// First launch: pick the name nearby phones will see and fill in the contact
/// card that is shared when phones touch.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller});

  final KdropController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _contact = ContactFormControllers.from(const ContactCard(name: ''));
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _contact.name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final card = _contact.toCard();
    if (card.name.isEmpty) return;
    setState(() => _busy = true);
    final first = card.name.split(' ').first;
    await widget.controller.completeOnboarding("$first's phone", card);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            GestureDetector(
              onTap: () => playTouchGlow(context),
              child: Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KColors.accentGradient,
                ),
                child: const Icon(Icons.wifi_tethering, size: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Welcome to Kdrop',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Share photos, files, links and your contact by holding two phones '
              'together, iPhone or Android.',
              style: TextStyle(color: KColors.textDim, fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 32),
            ContactForm(controllers: _contact),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _contact.name.text.trim().isEmpty || _busy ? null : _continue,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Get started'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your card is only sent when you choose to share it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
