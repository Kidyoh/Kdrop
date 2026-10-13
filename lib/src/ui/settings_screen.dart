import 'package:flutter/material.dart';

import '../core/contact_card.dart';
import '../kdrop_controller.dart';
import '../services/settings_store.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final KdropController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final KdropSettings _initial = widget.controller.settings!;
  late final _name = TextEditingController(text: _initial.deviceName);
  late final _contact = ContactFormControllers.from(_initial.contact);
  late double _threshold = _initial.touchThreshold;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await widget.controller.updateSettings(_initial.copyWith(
      deviceName: name,
      contact: _contact.toCard(),
      touchThreshold: _threshold,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _Section('This device'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name others see'),
          ),
          const SizedBox(height: 28),
          const _Section('My contact card'),
          ContactForm(controllers: _contact),
          const SizedBox(height: 28),
          const _Section('Touch sensitivity'),
          const Text(
            'How close the phones must be before they connect. Hold another phone '
            'against this one and watch the live signal to calibrate.',
            style: TextStyle(color: KColors.textDim),
          ),
          Slider(
            value: _threshold,
            min: -65,
            max: -25,
            divisions: 40,
            label: '${_threshold.round()} dBm',
            onChanged: (v) {
              setState(() => _threshold = v);
              widget.controller.updateSettings(
                widget.controller.settings!.copyWith(touchThreshold: v),
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Farther', style: TextStyle(color: KColors.textDim, fontSize: 12)),
              Text('Trigger at ${_threshold.round()} dBm'),
              const Text('Closer', style: TextStyle(color: KColors.textDim, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final s = widget.controller.strongestSignal;
              final hit = s != null && s >= _threshold;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (hit ? KColors.green : KColors.surfaceHigh).withValues(alpha: hit ? 0.2 : 1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sensors, color: hit ? KColors.green : KColors.cyan),
                    const SizedBox(width: 10),
                    Text(
                      s == null
                          ? 'No Kdrop phone in Bluetooth range'
                          : 'Nearest phone: ${s.round()} dBm${hit ? '  ·  touching' : ''}',
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          const _Section('How it works'),
          const Text(
            '• Phones find each other on the same Wi-Fi network and transfer directly '
            'between themselves; nothing goes through the internet.\n'
            '• Bluetooth signal strength tells Kdrop when two phones are held together.\n'
            '• Long-press a device on the radar to preview the touch animation.',
            style: TextStyle(color: KColors.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: KColors.cyan,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class ContactFormControllers {
  ContactFormControllers.from(ContactCard card)
      : name = TextEditingController(text: card.name),
        phone = TextEditingController(text: card.phone),
        email = TextEditingController(text: card.email),
        organization = TextEditingController(text: card.organization);

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController organization;

  ContactCard toCard() => ContactCard(
        name: name.text.trim(),
        phone: phone.text.trim(),
        email: email.text.trim(),
        organization: organization.text.trim(),
      );

  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    organization.dispose();
  }
}

class ContactForm extends StatelessWidget {
  const ContactForm({super.key, required this.controllers});

  final ContactFormControllers controllers;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controllers.name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controllers.phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controllers.email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controllers.organization,
          decoration: const InputDecoration(labelText: 'Company (optional)'),
        ),
      ],
    );
  }
}
