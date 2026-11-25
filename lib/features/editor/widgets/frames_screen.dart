import 'package:flutter/material.dart';

import '../../../core/models/figure.dart';
import '../controllers/editor_controller.dart';
import '../../../core/theme/app_theme.dart';
import 'figure_preview.dart';

/// A separate page showing every frame of the animation as a grid of
/// thumbnails. Tap a frame to jump to it; long-press / right-click opens
/// Copy / Paste / Delete.
class FramesScreen extends StatefulWidget {
  final EditorController controller;

  const FramesScreen({super.key, required this.controller});

  @override
  State<FramesScreen> createState() => _FramesScreenState();
}

class _FramesScreenState extends State<FramesScreen> {
  final Map<int, Figure> _cache = {};
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.controller.currentFrame;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // Rebuild thumbnails so they reflect the current pose/overrides.
    _cache.clear();
    setState(() {});
  }

  EditorController get c => widget.controller;

  Figure _thumbFor(int frame) {
    return _cache.putIfAbsent(frame, () {
      final t = frame.toDouble();
      return c.thumbnailFigure(t);
    });
  }

  void _goToFrame(int frame) {
    c.setCurrentTime(frame.toDouble());
    c.applyPose();
    Navigator.of(context).pop();
  }

  Future<void> _showFrameMenu(int frame, double t) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _FrameMenuSheet(
        hasCopied: c.hasCopiedFrame,
        onSelected: (v) => Navigator.of(sheetContext).pop(v),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'copy':
        c.copyFrame(t);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Frame ${frame + 1} copied')));
        break;
      case 'paste':
        if (!c.hasCopiedFrame) return;
        c.pasteFrame(t);
        _cache.clear();
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pasted to frame ${frame + 1}')));
        break;
      case 'delete':
        c.deleteFrame(t);
        _cache.clear();
        setState(() {});
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final total = c.totalFrames;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(
          'Frames',
          style: TextStyle(
            color: palette.text,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: palette.background,
        foregroundColor: palette.text,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cellW = (constraints.maxWidth - 32 - 30) / 4;
          final cellH = cellW * 9 / 16 + 26;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: cellW / cellH,
            ),
            itemCount: total,
            itemBuilder: (context, i) => _cell(palette, i),
          );
        },
      ),
    );
  }

  Widget _cell(AppPalette palette, int frame) {
    final isSelected = frame == _selected;
    final t = frame.toDouble();
    return GestureDetector(
      onTap: () => _goToFrame(frame),
      onLongPress: () => _showFrameMenu(frame, t),
      onSecondaryTap: () => _showFrameMenu(frame, t),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.backgroundElement,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B82F6) : palette.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: FigurePreview(
                figure: _thumbFor(frame),
                time: t,
                enableFrameOverrides: true,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: palette.background,
              child: Text(
                '${frame + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF60A5FA)
                      : palette.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameMenuSheet extends StatelessWidget {
  final bool hasCopied;
  final ValueChanged<String> onSelected;

  const _FrameMenuSheet({required this.hasCopied, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final items = [
      ('copy', Icons.copy_outlined, 'Copy Frame', palette.text, true),
      ('paste', Icons.content_paste, 'Paste Frame', palette.text, hasCopied),
      (
        'delete',
        Icons.delete_outline,
        'Delete Frame',
        const Color(0xFFF87171),
        true,
      ),
    ];
    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items.map((item) {
              final enabled = item.$5;
              final color = enabled ? item.$4 : palette.border;
              return ListTile(
                enabled: enabled,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(item.$2, size: 20, color: color),
                title: Text(
                  item.$3,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => onSelected(item.$1),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
