import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/models/segment.dart';
import '../controllers/editor_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/color_picker_sheet.dart';

/// Settings drawer: FPS, canvas size, onion skin, auto easing.
class AnimationSettingsPanel extends StatefulWidget {
  final EditorController controller;

  const AnimationSettingsPanel({super.key, required this.controller});

  @override
  State<AnimationSettingsPanel> createState() => _AnimationSettingsPanelState();
}

class _AnimationSettingsPanelState extends State<AnimationSettingsPanel> {
  late TextEditingController _fpsController;
  late TextEditingController _widthController;
  late TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    _fpsController = TextEditingController(text: '${widget.controller.fps.round()}');
    _widthController =
        TextEditingController(text: '${widget.controller.figure.canvasWidth.round()}');
    _heightController =
        TextEditingController(text: '${widget.controller.figure.canvasHeight.round()}');
  }

  @override
  void dispose() {
    _fpsController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _changeFps(int next) {
    if (next < 1 || next > 60) return;
    setState(() => _fpsController.text = '$next');
    widget.controller.setFps(next.toDouble());
    widget.controller.pushHistory();
  }

  void _setCanvasSize(double w, double h) {
    widget.controller.setCanvasSize(w, h);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final c = widget.controller;

    Widget sectionLabel(String label) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        );

    Widget rowBox(Widget child) => Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: child,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionLabel('FPS'),
          rowBox(Row(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.minus, size: 14),
                color: palette.textSecondary,
                onPressed: () => _changeFps(c.fps.round() - 1),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: TextField(
                  controller: _fpsController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (v) {
                    final n = int.tryParse(v) ?? 0;
                    if (n >= 1 && n <= 60) {
                      c.setFps(n.toDouble());
                      c.pushHistory();
                    }
                  },
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.plus, size: 14),
                color: palette.textSecondary,
                onPressed: () => _changeFps(c.fps.round() + 1),
                visualDensity: VisualDensity.compact,
              ),
            ],
          )),

          sectionLabel('Canvas Size'),
          rowBox(Row(
            children: [
              Text('W', style: TextStyle(color: palette.textSecondary, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _widthController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.text, fontSize: 14),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) {
                      _setCanvasSize(
                        n.toDouble(),
                        c.figure.canvasHeight,
                      );
                    }
                  },
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('H', style: TextStyle(color: palette.textSecondary, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _heightController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.text, fontSize: 14),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) {
                      _setCanvasSize(
                        c.figure.canvasWidth,
                        n.toDouble(),
                      );
                    }
                  },
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          )),

          sectionLabel('Canvas Color'),
          rowBox(ColorField(
            palette: palette,
            selected: parseHexColor(c.figure.canvasColor),
            onChanged: (color) => c.setCanvasColor(colorToHex(color)),
          )),

          sectionLabel('Onion Skin'),
          _switchRow('Prev Onion', palette, c.onionPrev, c.setOnionPrev),
          _switchRow('Next Onion', palette, c.onionNext, c.setOnionNext),

          sectionLabel('Motion'),
          _switchRow(
            'Auto Easing',
            palette,
            c.autoEasing,
            c.setAutoEasing,
            hint: 'Smoothly interpolate between keyframes',
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, AppPalette palette, bool value, ValueChanged<bool> onChange,
      {String? hint}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: palette.text, fontSize: 14, fontWeight: FontWeight.w600)),
                if (hint != null)
                  Text(hint, style: TextStyle(color: palette.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChange,
            activeTrackColor: const Color(0xFF3B82F6),
          ),
        ],
      ),
    );
  }
}
