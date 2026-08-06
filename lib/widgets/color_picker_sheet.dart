import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart'
    hide colorToHex;

import '../core/models/segment.dart';
import '../theme/app_theme.dart';

/// Quick-select palette used across the editor.
const List<String> colorPalette = [
  '#d1d5db', '#ef4444', '#f97316', '#eab308', '#22c55e', '#06b6d4',
  '#3b82f6', '#a855f7', '#ec4899', '#000000', '#ffffff', '#4b5563',
];

/// Opens a bottom sheet with a full HSV color picker; returns the picked
/// color or null when dismissed.
Future<Color?> showColorPickerSheet(BuildContext context, Color initial) {
  return showModalBottomSheet<Color>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _ColorPickerSheet(initialColor: initial),
  );
}

/// Swatch + hex + "Custom" picker + quick palette grid. A drop-in
/// replacement for the old static palette grid.
class ColorField extends StatelessWidget {
  final AppPalette palette;
  final Color? selected;
  final ValueChanged<Color> onChanged;

  const ColorField({
    super.key,
    required this.palette,
    required this.selected,
    required this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final result = await showColorPickerSheet(
      context,
      selected ?? const Color(0xFF000000),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 28,
              decoration: BoxDecoration(
                color: selected ?? Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.border),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected != null ? colorToHex(selected!) : 'None',
                style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace'),
              ),
            ),
            InkWell(
              onTap: () => _openPicker(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined,
                        size: 14, color: palette.text),
                    const SizedBox(width: 4),
                    Text(
                      'Custom',
                      style: TextStyle(
                          color: palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: colorPalette.map((hex) {
            final color = parseHexColor(hex);
            final isSelected = selected != null && color != null
                ? colorToHex(selected!) == colorToHex(color)
                : false;
            return GestureDetector(
              onTap: () {
                if (color != null) onChanged(color);
              },
              child: Container(
                width: 36,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF60A5FA)
                        : palette.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ColorPickerSheet extends StatefulWidget {
  final Color initialColor;

  const _ColorPickerSheet({required this.initialColor});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late Color _color = widget.initialColor;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Pick Color',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 18, color: palette.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: ColorPicker(
                  pickerColor: _color,
                  onColorChanged: (c) => setState(() => _color = c),
                  colorPickerWidth: 210,
                  pickerAreaHeightPercent: 0.55,
                  enableAlpha: true,
                  displayThumbColor: true,
                  hexInputBar: true,
                  labelTypes: const [],
                  paletteType: PaletteType.hsv,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: palette.border),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      colorToHex(_color),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_color),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Apply'),
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
