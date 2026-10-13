import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/contact_card.dart';
import '../core/offer.dart';
import '../core/peer.dart';
import '../kdrop_controller.dart';
import 'theme.dart';
import 'widgets/avatar.dart';

// ------------------------------------------------------------ incoming offer

/// Asks the user whether to accept an incoming share. Dismissing declines.
Future<void> showIncomingOfferSheet(BuildContext context, IncomingOfferEvent event) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _IncomingOfferSheet(offer: event.offer),
  );
  event.respond(accepted ?? false);
}

class _IncomingOfferSheet extends StatefulWidget {
  const _IncomingOfferSheet({required this.offer});

  final Offer offer;

  @override
  State<_IncomingOfferSheet> createState() => _IncomingOfferSheetState();
}

class _IncomingOfferSheetState extends State<_IncomingOfferSheet> {
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    // The sender gives up after a minute; don't leave a dead prompt behind.
    _timeout = Timer(const Duration(seconds: 58), () {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                KAvatar(
                  id: offer.senderId,
                  initials: ContactCard(name: offer.senderName).initials,
                  size: 52,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.senderName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'wants to share ${offer.summary}',
                        style: const TextStyle(color: KColors.textDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _OfferPreview(offer: offer),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferPreview extends StatelessWidget {
  const _OfferPreview({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context) {
    switch (offer.kind) {
      case PayloadKind.contact:
        return ContactCardView(card: offer.contact!, id: offer.senderId);
      case PayloadKind.text:
        return _Panel(
          child: Text(
            offer.text!,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
          ),
        );
      case PayloadKind.files:
        final shown = offer.files.take(4).toList();
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final f in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(iconForFile(f.name), size: 20, color: KColors.cyan),
                      const SizedBox(width: 10),
                      Expanded(child: Text(f.name, overflow: TextOverflow.ellipsis)),
                      if (f.size >= 0)
                        Text(formatBytes(f.size),
                            style: const TextStyle(color: KColors.textDim, fontSize: 12)),
                    ],
                  ),
                ),
              if (offer.files.length > shown.length)
                Text('+ ${offer.files.length - shown.length} more',
                    style: const TextStyle(color: KColors.textDim)),
              if (offer.totalBytes >= 0) ...[
                const Divider(height: 18),
                Text('Total ${formatBytes(offer.totalBytes)}',
                    style: const TextStyle(color: KColors.textDim, fontSize: 12)),
              ],
            ],
          ),
        );
    }
  }
}

// ---------------------------------------------------------------- touch card

enum TouchChoice { shareContact, receiveOnly }

/// The card that drops in from the top after two phones touch, NameDrop style.
/// It closes itself (returning null) when [dismiss] fires, e.g. because the
/// other phone already sent something.
Future<TouchChoice?> showTouchCard(
  BuildContext context, {
  required String deviceId,
  required Peer? peer,
  Listenable? dismiss,
}) {
  return showGeneralDialog<TouchChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (context, _, _) =>
        _TouchCard(deviceId: deviceId, peer: peer, dismiss: dismiss),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return SlideTransition(
        position: Tween(begin: const Offset(0, -1), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

class _TouchCard extends StatefulWidget {
  const _TouchCard({required this.deviceId, required this.peer, this.dismiss});

  final String deviceId;
  final Peer? peer;
  final Listenable? dismiss;

  @override
  State<_TouchCard> createState() => _TouchCardState();
}

class _TouchCardState extends State<_TouchCard> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.dismiss?.addListener(_close);
  }

  @override
  void dispose() {
    widget.dismiss?.removeListener(_close);
    super.dispose();
  }

  void _close() => _pop(null);

  void _pop(TouchChoice? choice) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.peer;
    final deviceId = widget.deviceId;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Material(
            color: KColors.surface,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: KColors.cyan.withValues(alpha: 0.35)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [KColors.violet.withValues(alpha: 0.25), KColors.surface],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KAvatar(
                    id: deviceId,
                    initials: p?.initials ?? '?',
                    size: 76,
                    platform: p?.platform,
                    glow: 1,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p?.name ?? 'Nearby phone',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p == null
                        ? 'Found over Bluetooth. Make sure you are both on the same Wi-Fi.'
                        : 'Share your contact card?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: KColors.textDim),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pop(TouchChoice.receiveOnly),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Receive Only'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: p == null
                              ? null
                              : () => _pop(TouchChoice.shareContact),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ received items

Future<void> showReceivedSheet(BuildContext context, ReceivedItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: ReceivedItemView(item: item),
      ),
    ),
  );
}

class ReceivedItemView extends StatelessWidget {
  const ReceivedItemView({super.key, required this.item});

  final ReceivedItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'From ${item.senderName}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        ...switch (item.kind) {
          PayloadKind.contact => [
              ContactCardView(card: item.contact!, id: item.senderName),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => saveContact(context, item.contact!),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Save to Contacts'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
          PayloadKind.text => [
              _Panel(child: SelectableText(item.text!)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: item.text!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                  if (_asLink(item.text!) case final uri?) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          PayloadKind.files => [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final file in item.files)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(iconForFile(file.path), color: KColors.cyan),
                        title: Text(
                          file.uri.pathSegments.last,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(formatBytes(file.lengthSync())),
                        trailing: const Icon(Icons.open_in_new, size: 20),
                        onTap: () => OpenFilex.open(file.path),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                Platform.isIOS
                    ? 'Saved in Files › On My iPhone › Kdrop'
                    : 'Saved in Android › data › com.kidyoh.kdrop › files › Kdrop',
                style: const TextStyle(color: KColors.textDim, fontSize: 12),
              ),
            ],
        },
      ],
    );
  }
}

Uri? _asLink(String text) {
  final t = text.trim();
  if (t.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(t);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return null;
  return uri;
}

/// Writes the card to a .vcf and hands it to the system, which offers to add
/// it to Contacts on both iOS and Android.
Future<void> saveContact(BuildContext context, ContactCard card) async {
  final dir = await getTemporaryDirectory();
  final safe = card.name.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
  final file = File('${dir.path}/${safe.isEmpty ? 'contact' : safe}.vcf');
  await file.writeAsString(card.toVCard());
  final result = await OpenFilex.open(file.path, type: 'text/x-vcard', uti: 'public.vcard');
  if (result.type != ResultType.done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open Contacts: ${result.message}')),
    );
  }
}

// ---------------------------------------------------------------- compose

Future<String?> showComposeTextSheet(BuildContext context) async {
  final clip = await Clipboard.getData(Clipboard.kTextPlain);
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ComposeText(initial: clip?.text ?? ''),
  );
}

class _ComposeText extends StatefulWidget {
  const _ComposeText({required this.initial});

  final String initial;

  @override
  State<_ComposeText> createState() => _ComposeTextState();
}

class _ComposeTextState extends State<_ComposeText> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Share text or a link',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Paste a link or type a message'),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder(
            valueListenable: _text,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(value.text),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: const Text('Ready to share'),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ shared

class ContactCardView extends StatelessWidget {
  const ContactCardView({super.key, required this.card, required this.id});

  final ContactCard card;
  final String id;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          KAvatar(id: id, initials: card.initials, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.name.isEmpty ? 'No name' : card.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                if (card.organization.isNotEmpty)
                  Text(card.organization, style: const TextStyle(color: KColors.textDim)),
                if (card.phone.isNotEmpty) _line(Icons.phone, card.phone),
                if (card.email.isNotEmpty) _line(Icons.mail_outline, card.email),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(icon, size: 15, color: KColors.cyan),
            const SizedBox(width: 6),
            Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

IconData iconForFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'heic' || 'webp' => Icons.image_outlined,
    'mp4' || 'mov' || 'mkv' || 'webm' || 'avi' => Icons.movie_outlined,
    'mp3' || 'm4a' || 'wav' || 'aac' || 'flac' => Icons.music_note_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'zip' || 'rar' || '7z' => Icons.folder_zip_outlined,
    'vcf' => Icons.contact_page_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

String formatBytes(int bytes) {
  if (bytes < 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}
