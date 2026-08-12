import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/minecraft_skin.dart';
import '../../../core/theme/app_theme.dart';

/// Settings chosen in the Minecraft skin import dialog.
class McSkinSettings {
  final double scale;
  final double yawDeg;
  final bool includeOuter;
  const McSkinSettings({
    required this.scale,
    required this.yawDeg,
    required this.includeOuter,
  });
}

/// Settings dialog shown before importing a Minecraft skin. Lets the user pick
/// the scale (world units per skin pixel), the horizontal angle (yaw) and
/// whether the outer clothing layer is included, with a live preview.
class MinecraftSkinDialog extends StatefulWidget {
  final ui.Image skin;
  const MinecraftSkinDialog({super.key, required this.skin});

  @override
  State<MinecraftSkinDialog> createState() => _MinecraftSkinDialogState();
}

class _MinecraftSkinDialogState extends State<MinecraftSkinDialog> {
  double _scale = 8;
  double _yawDeg = 0;
  bool _includeOuter = true;

  void _pop(McSkinSettings? settings) => Navigator.of(context).pop(settings);

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final title = 'Import Minecraft Skin';

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: palette.backgroundElement,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.backgroundSelected),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            // Live preview.
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                painter: McSkinPreviewPainter(
                  skin: widget.skin,
                  scale: _scale,
                  yawDeg: _yawDeg,
                  includeOuter: _includeOuter,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Scale: ${_scale.round()}',
                style: TextStyle(color: palette.text, fontSize: 12)),
            Slider(
              value: _scale,
              min: 2,
              max: 20,
              divisions: 18,
              activeColor: const Color(0xFF10B981),
              inactiveColor: palette.backgroundSelected,
              onChanged: (v) => setState(() => _scale = v),
            ),
            Text('Yaw (side): ${_yawDeg.round()}°',
                style: TextStyle(color: palette.text, fontSize: 12)),
            Slider(
              value: _yawDeg,
              min: -90,
              max: 90,
              divisions: 12,
              activeColor: const Color(0xFF10B981),
              inactiveColor: palette.backgroundSelected,
              onChanged: (v) => setState(() => _yawDeg = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Include clothing (outer) layer',
                  style: TextStyle(color: palette.text, fontSize: 13)),
              value: _includeOuter,
              activeTrackColor: const Color(0xFF10B981),
              onChanged: (v) => setState(() => _includeOuter = v),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _pop(null),
                  style: TextButton.styleFrom(foregroundColor: palette.text),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _pop(McSkinSettings(
                    scale: _scale,
                    yawDeg: _yawDeg,
                    includeOuter: _includeOuter,
                  )),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF0B1220),
                  ),
                  child: const Text('Import'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the full projected character for the live preview, using the same
/// projection math as [buildMinecraftSkinFigure].
class McSkinPreviewPainter extends CustomPainter {
  final ui.Image skin;
  final double scale;
  final double yawDeg;
  final bool includeOuter;

  McSkinPreviewPainter({
    required this.skin,
    required this.scale,
    required this.yawDeg,
    required this.includeOuter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = mcSkinBounds(yawDeg, scale);
    if (bounds.isEmpty || bounds.width <= 0 || bounds.height <= 0) return;

    const pad = 16.0;
    final fitW = (size.width - pad * 2) / bounds.width;
    final fitH = (size.height - pad * 2) / bounds.height;
    final fit = math.min(fitW, fitH).clamp(0.01, 10000.0);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(fit);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.none
      ..isAntiAlias = false;

    for (final part in kMcParts) {
      final faces = projectPartFaces(part, yawDeg);
      if (faces.isEmpty) continue;
      final layout = mcPartLayout(part);
      final cx = layout.cx * scale;
      final topY = layout.topY * scale;
      final h = part.height * scale;
      var x = cx - (mcProjectedWidth(part, yawDeg) * scale) / 2;
      for (final face in faces) {
        final w = face.screenW * scale;
        if (w < 0.5) continue;
        final dst = ui.Rect.fromLTWH(x, topY, w, h);
        _drawUv(canvas, skin, face.baseUv, dst, paint);
        if (includeOuter && face.outerUv != null) {
          _drawUv(canvas, skin, face.outerUv!, dst, paint);
        }
        x += w;
      }
    }
    canvas.restore();
  }

  void _drawUv(Canvas canvas, ui.Image img, McUv uv, ui.Rect dst, ui.Paint p) {
    final src = ui.Rect.fromLTWH(
        uv.x.toDouble(), uv.y.toDouble(), uv.w.toDouble(), uv.h.toDouble());
    canvas.drawImageRect(img, src, dst, p);
  }

  @override
  bool shouldRepaint(McSkinPreviewPainter oldDelegate) =>
      oldDelegate.skin != skin ||
      oldDelegate.scale != scale ||
      oldDelegate.yawDeg != yawDeg ||
      oldDelegate.includeOuter != includeOuter;
}