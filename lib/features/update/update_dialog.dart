import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_model.dart';
import 'update_service.dart';

/// Menampilkan dialog update jika versi baru tersedia.
/// Panggil setelah app siap (mis. di MainMenuScreen).
Future<void> showUpdateDialogIfAny(BuildContext context, {bool showSnackIfUpToDate = false}) async {
  final update = await UpdateService().checkUpdate();
  if (!context.mounted) return;
  if (update == null) {
    if (showSnackIfUpToDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aplikasi sudah menggunakan versi terbaru.')),
      );
    }
    return;
  }
  showDialog(
    context: context,
    builder: (_) => UpdateDialog(update: update),
  );
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.update});

  final AppUpdate update;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  String? _error;

  Future<void> _updateNow() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(widget.update.apkUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Update Tersedia'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Versi ${widget.update.latestVersion} tersedia.'),
          if (_error != null)
            Text(
              'Update gagal: $_error',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: const Text('Nanti Saja'),
        ),
        FilledButton(
          onPressed: _downloading ? null : _updateNow,
          child: _downloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update Sekarang'),
        ),
      ],
    );
  }
}
