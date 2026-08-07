import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A circular toolbar button (used in the top capsule and sidebars).
class EditorIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color? color;
  final bool disabled;
  final VoidCallback? onTap;
  final double size;

  const EditorIconButton({
    super.key,
    required this.icon,
    this.active = false,
    this.color,
    this.disabled = false,
    this.onTap,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final Color bg = active ? (color ?? const Color(0xFF2563EB)) : Colors.transparent;
    final Color iconColor = active
        ? Colors.white
        : disabled
            ? palette.border
            : palette.textSecondary;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, size: size, color: iconColor),
      ),
    );
  }
}

/// A transparent overlay capsule (used for top bar / sidebars).
class OverlayCapsule extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  const OverlayCapsule({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(4),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.85),
        borderRadius: borderRadius,
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

/// Where the sub-tool capsule appears relative to the main capsule.
enum ToolGroupPlacement { right, bottom }

/// One selectable sub-tool of a [ToolGroupButton].
class ToolGroupSub {
  final IconData icon;
  final Color? color;
  final String key;

  const ToolGroupSub({
    required this.icon,
    required this.key,
    this.color,
  });
}

/// A tool button that is part of the tool mode: the main button is a plain
/// [EditorIconButton] like the rest of the capsule, and tapping it activates
/// the tool (switching the active mode). Tapping it again while active opens a
/// floating dropdown sub-tool capsule over the overlay, so the parent capsule's
/// style/layout stays unchanged. [placement] decides where the dropdown opens:
/// `bottom` (centred below the main button, top bar) or `right` (beside it,
/// aligned top-to-bottom, sidebar).
class ToolGroupButton extends StatefulWidget {
  final List<ToolGroupSub> subTools;
  final String selectedKey;
  final ValueChanged<String> onSelect;
  final ToolGroupPlacement placement;

  /// Whether the group's tool is currently the active tool/mode.
  final bool active;

  /// Called when the main button is tapped while the tool is not active.
  final VoidCallback onActivate;

  const ToolGroupButton({
    super.key,
    required this.subTools,
    required this.selectedKey,
    required this.onSelect,
    required this.active,
    required this.onActivate,
    this.placement = ToolGroupPlacement.bottom,
  });

  @override
  State<ToolGroupButton> createState() => _ToolGroupButtonState();
}

class _ToolGroupButtonState extends State<ToolGroupButton> {
  OverlayEntry? _entry;

  ToolGroupSub get _selected => widget.subTools.firstWhere(
        (s) => s.key == widget.selectedKey,
        orElse: () => widget.subTools.first,
      );

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  void _close() {
    if (_entry != null) _remove();
  }

  void _handleMainTap() {
    if (!widget.active) {
      widget.onActivate();
    }
    if (_entry != null) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final overlayState = Overlay.of(context);
    final overlayBox =
        overlayState.context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    if (box.hasSize == false) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    _entry = OverlayEntry(builder: (ctx) {
      return Stack(
        children: [
          // Barrier to catch taps outside and close the dropdown.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_entry != null) _close();
              },
            ),
          ),
          Positioned(
            left: widget.placement == ToolGroupPlacement.bottom
                ? topLeft.dx + box.size.width / 2
                : topLeft.dx + box.size.width + 6,
            top: widget.placement == ToolGroupPlacement.bottom
                ? topLeft.dy + box.size.height + 6
                : topLeft.dy,
            child: Material(
              type: MaterialType.transparency,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // Blocks taps from reaching the background barrier
                child: widget.placement == ToolGroupPlacement.bottom
                    ? FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: _subBar(),
                      )
                    : _subBar(),
              ),
            ),
          ),
        ],
      );
    });
    overlayState.insert(_entry!);
  }

  Widget _subBar() {
    final subs = [
      for (final s in widget.subTools)
        EditorIconButton(
          icon: s.icon,
          active: s.key == widget.selectedKey,
          color: s.color,
          onTap: () {
            widget.onSelect(s.key);
            _close();
          },
        ),
    ];
    return OverlayCapsule(
      padding: const EdgeInsets.all(4),
      child: widget.placement == ToolGroupPlacement.bottom
          ? Row(mainAxisSize: MainAxisSize.min, children: subs)
          : Column(mainAxisSize: MainAxisSize.min, children: subs),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep state in sync: if the tool becomes inactive while the dropdown is
    // open, close it.
    if (!widget.active && _entry != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.active) _close();
      });
    }
    final palette = Theme.of(context).appColors;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        EditorIconButton(
          icon: _selected.icon,
          active: widget.active,
          color: _selected.color,
          onTap: _handleMainTap,
        ),
        // Sub-tool indicator dot, top-right: grey when inactive, white when
        // the tool is active.
        Positioned(
          top: -1,
          right: -1,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.active
                  ? Colors.white
                  : palette.textSecondary,
              shape: BoxShape.circle,
              border: Border.all(
                color: palette.background,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rounded panel container used by drawers and modals.
class EditorPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const EditorPanel({super.key, required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.backgroundElement,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}
