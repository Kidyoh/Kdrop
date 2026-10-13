import 'package:flutter/material.dart';

import '../core/offer.dart';
import '../kdrop_controller.dart';
import 'sheets.dart';
import 'theme.dart';

class ReceivedScreen extends StatelessWidget {
  const ReceivedScreen({super.key, required this.controller});

  final KdropController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Received')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final items = controller.received;
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'Nothing received yet',
                style: TextStyle(color: KColors.textDim),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = items[i];
              final (IconData icon, String title) = switch (item.kind) {
                PayloadKind.files => (
                    item.files.length == 1 ? iconForFile(item.files.first.path) : Icons.folder_copy_outlined,
                    item.files.length == 1
                        ? item.files.first.uri.pathSegments.last
                        : '${item.files.length} files',
                  ),
                PayloadKind.contact => (Icons.contact_page_outlined, item.contact!.name),
                PayloadKind.text => (Icons.notes, item.text!.replaceAll('\n', ' ')),
              };
              return ListTile(
                tileColor: KColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(icon, color: KColors.cyan),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('From ${item.senderName} · ${_time(item.at)}'),
                onTap: () => showReceivedSheet(context, item),
              );
            },
          );
        },
      ),
    );
  }

  static String _time(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
