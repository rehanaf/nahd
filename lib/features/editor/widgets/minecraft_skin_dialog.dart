import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/minecraft_skin.dart';
import '../../../core/theme/app_theme.dart';

/// Settings chosen in the Minecraft skin import dialog.
class McSkinSettings {
  final double yawDeg;
  final bool includeOuter;
  const McSkinSettings({
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
  double _yawDeg = 0;
  bool _includeOuter = true;

  void _pop(McSkinSettings? settings) => Navigator.of(context).pop(settings);

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final title = 'Import Minecraft Skin';

    // Bound the dialog height to the available screen (accounting for the
    // dialog insets + our own margins) so the bottom controls (Cancel/Import)
    // are never clipped on small/landscape mobile screens. Content scrolls
    // when it does not fit.
    final media = MediaQuery.of(context);
    final maxH = math.max(
      240.0,
      media.size.height - media.padding.top - media.padding.bottom - 80,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: maxH,
        ),
        decoration: BoxDecoration(
          color: palette.backgroundElement,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.backgroundSelected),
        ),
        child: SingleChildScrollView(
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
                  yawDeg: _yawDeg,
                  includeOuter: _includeOuter,
                ),
              ),
            ),
            const SizedBox(height: 12),
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
      ),
    );
  }
}

/// Draws the full projected character for the live preview, using the same
/// projection math as [buildMinecraftSkinFigure]. Preview renders at the fixed
/// import scale (8 world units per skin pixel).
class McSkinPreviewPainter extends CustomPainter {
  static const double scale = 8;
  final ui.Image skin;
  final double yawDeg;
  final bool includeOuter;

  McSkinPreviewPainter({
    required this.skin,
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
        final flip = mcSideFace(face.side);
        _drawUv(canvas, skin, face.baseUv, dst, paint, flip: flip);
        if (includeOuter && face.outerUv != null) {
          _drawUv(canvas, skin, face.outerUv!, dst, paint, flip: flip);
        }
        x += w;
      }
    }
    canvas.restore();
  }

  void _drawUv(Canvas canvas, ui.Image img, McUv uv, ui.Rect dst, ui.Paint p,
      {bool flip = false}) {
    final src = ui.Rect.fromLTWH(
        uv.x.toDouble(), uv.y.toDouble(), uv.w.toDouble(), uv.h.toDouble());
    if (!flip) {
      canvas.drawImageRect(img, src, dst, p);
      return;
    }
    canvas.save();
    canvas.translate(dst.center.dx, dst.center.dy);
    canvas.scale(-1, 1);
    canvas.translate(-dst.center.dx, -dst.center.dy);
    canvas.drawImageRect(img, src, dst, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(McSkinPreviewPainter oldDelegate) =>
      oldDelegate.skin != skin ||
      oldDelegate.yawDeg != yawDeg ||
      oldDelegate.includeOuter != includeOuter;
}