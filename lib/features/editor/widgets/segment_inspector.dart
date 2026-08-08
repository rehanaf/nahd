import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/models/figure.dart';
import '../../../core/models/segment.dart';
import '../controllers/editor_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/color_picker_sheet.dart';

/// Right-drawer properties panel for the selected segment.
class SegmentInspector extends StatefulWidget {
  final EditorController controller;

  const SegmentInspector({super.key, required this.controller});

  @override
  State<SegmentInspector> createState() => _SegmentInspectorState();
}

class _Accordion extends StatefulWidget {
  final String title;
  final Widget child;

  const _Accordion({
    required this.title,
    required this.child,
  });

  @override
  State<_Accordion> createState() => _AccordionState();
}

class _AccordionState extends State<_Accordion> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: palette.backgroundSelected,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.border)),
              ),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _SegmentInspectorState extends State<SegmentInspector> {
  late final TextEditingController _widthController;
  late final TextEditingController _layerController;
  late final TextEditingController _lengthController;
  late final TextEditingController _angleController;
  late final TextEditingController _scaleAllController;
  final FocusNode _lengthFocus = FocusNode();
  final FocusNode _angleFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final seg = widget.controller.figure.getSegment(widget.controller.selectedSegmentId ?? '');
    _widthController = TextEditingController(text: '${seg?.width.round() ?? 3}');
    _layerController = TextEditingController(text: '${seg?.layer ?? 0}');
    _lengthController =
        TextEditingController(text: _fmtLen(_segLen(widget.controller.figure, seg)));
    _angleController =
        TextEditingController(text: _fmtAng(_segAng(widget.controller.figure, seg)));
    _scaleAllController = TextEditingController(text: '100');
  }

  @override
  void didUpdateWidget(covariant SegmentInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seg = widget.controller.figure.getSegment(widget.controller.selectedSegmentId ?? '');
    if (seg != null) {
      _widthController.text = '${seg.width.round()}';
      _layerController.text = '${seg.layer}';
      if (!_lengthFocus.hasFocus) {
        _lengthController.text = _fmtLen(_segLen(widget.controller.figure, seg));
      }
      if (!_angleFocus.hasFocus) {
        _angleController.text = _fmtAng(_segAng(widget.controller.figure, seg));
      }
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _layerController.dispose();
    _lengthController.dispose();
    _angleController.dispose();
    _scaleAllController.dispose();
    _lengthFocus.dispose();
    _angleFocus.dispose();
    super.dispose();
  }

  void _applyScaleAll() {
    final n = double.tryParse(_scaleAllController.text);
    if (n == null) return;
    widget.controller.scaleAll(n);
  }

  double _segLen(Figure fig, Segment? seg) {
    if (seg == null ||
        seg.point1Index >= fig.points.length ||
        seg.point2Index >= fig.points.length) {
      return 0;
    }
    final p1 = fig.points[seg.point1Index];
    final p2 = fig.points[seg.point2Index];
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _segAng(Figure fig, Segment? seg) {
    if (seg == null ||
        seg.point1Index >= fig.points.length ||
        seg.point2Index >= fig.points.length) {
      return 0;
    }
    final p1 = fig.points[seg.point1Index];
    final p2 = fig.points[seg.point2Index];
    return math.atan2(p2.y - p1.y, p2.x - p1.x) * 180 / math.pi;
  }

  String _fmtLen(double v) => v.toStringAsFixed(1);
  String _fmtAng(double v) => v.toStringAsFixed(1);

  void _setSegmentLength(Segment seg, double newLen) {
    final figure = widget.controller.figure;
    if (seg.point1Index >= figure.points.length ||
        seg.point2Index >= figure.points.length) {
      return;
    }
    final p1 = figure.points[seg.point1Index];
    final p2 = figure.points[seg.point2Index];
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final cur = math.sqrt(dx * dx + dy * dy);
    if (cur < 1e-4) return;
    final k = newLen / cur;
    final newX = p1.x + dx * k;
    final newY = p1.y + dy * k;
    final ox = newX - p2.x;
    final oy = newY - p2.y;
    p2.x = newX;
    p2.y = newY;
    for (final i in figure.childPoints(seg.point2Index)) {
      figure.points[i].x += ox;
      figure.points[i].y += oy;
    }
    setState(() {});
    widget.controller.forceUpdate();
    widget.controller.pushHistory();
  }

  void _setSegmentAngle(Segment seg, double angleDeg) {
    final figure = widget.controller.figure;
    if (seg.point1Index >= figure.points.length ||
        seg.point2Index >= figure.points.length) {
      return;
    }
    final p1 = figure.points[seg.point1Index];
    final p2 = figure.points[seg.point2Index];
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final cur = math.sqrt(dx * dx + dy * dy);
    if (cur < 1e-4) return;
    final rad = angleDeg * math.pi / 180;
    final newX = p1.x + math.cos(rad) * cur;
    final newY = p1.y + math.sin(rad) * cur;
    final ox = newX - p2.x;
    final oy = newY - p2.y;
    p2.x = newX;
    p2.y = newY;
    for (final i in figure.childPoints(seg.point2Index)) {
      figure.points[i].x += ox;
      figure.points[i].y += oy;
    }
    setState(() {});
    widget.controller.forceUpdate();
    widget.controller.pushHistory();
  }

  void _change(Segment seg, String field, Object? value) {
    switch (field) {
      case 'width':
        seg.width = (value as num).toDouble();
        break;
      case 'layer':
        seg.layer = (value as num).toInt();
        break;
      case 'curvature':
        seg.curvature = (value as num).toDouble();
        break;
      default:
        _setField(seg, field, value);
        return;
    }
    setState(() {});
    widget.controller.forceUpdate();
    widget.controller.pushHistory();
  }

  void _setField(Segment seg, String field, Object? value) {
    switch (field) {
      case 'type':
        seg.type = value as String;
        break;
      case 'color':
        seg.color = value as String;
        break;
      case 'fillColor':
        seg.fillColor = value as String;
        break;
      case 'lineCap':
        seg.lineCap = value as String;
        break;
      case 'curved':
        seg.curved = value as bool;
        break;
      case 'hidden':
        seg.hidden = value as bool;
        break;
      case 'filled':
        seg.filled = value as bool;
        break;
      case 'imageOffsetX':
        seg.imageOffsetX = (value as num).toDouble();
        break;
      case 'imageOffsetY':
        seg.imageOffsetY = (value as num).toDouble();
        break;
      case 'imageRotate':
        seg.imageRotate = (value as num).toDouble();
        break;
    }
    setState(() {});
    widget.controller.forceUpdate();
    widget.controller.pushHistory();
  }

  Future<void> _pickImage(Segment seg) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final ext = _extFor(result.files.first.extension);
      widget.controller.addSegmentImage(
          seg.id, 'data:image/$ext;base64,${base64Encode(bytes)}');
      setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memilih gambar')),
        );
      }
    }
  }

  String _extFor(String? ext) {
    switch ((ext ?? '').toLowerCase().replaceAll('.', '')) {
      case 'png':
        return 'png';
      case 'jpg':
      case 'jpeg':
        return 'jpeg';
      case 'gif':
        return 'gif';
      case 'webp':
        return 'webp';
      default:
        return 'png';
    }
  }

  int _rootOfPoint(Figure fig, int pointIdx) {
    final roots = fig.getFigureRoots();
    for (final r in roots) {
      if (r == pointIdx) return r;
      final visited = <int>{r};
      final queue = <int>[r];
      while (queue.isNotEmpty) {
        final idx = queue.removeAt(0);
        if (idx == pointIdx) return r;
        for (final s in fig.segments) {
          final other = s.point1Index == idx
              ? s.point2Index
              : s.point2Index == idx
                  ? s.point1Index
                  : -1;
          if (other >= 0 && !visited.contains(other)) {
            visited.add(other);
            queue.add(other);
          }
        }
      }
    }
    return roots.isEmpty ? 0 : roots.first;
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final c = widget.controller;
    final figure = c.figure;
    final segId = c.selectedSegmentId;
    if (segId == null) {
      return _empty('Tap segment di canvas untuk melihat properti');
    }
    final seg = figure.getSegment(segId);
    if (seg == null) {
      return _empty('Segment tidak ditemukan');
    }
    final isAnimating = c.isAnimateMode;

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            text,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        );

    Widget typePicker(List<String> types) => Row(          children: types
              .map((t) => Expanded(
                    child: InkWell(
                      onTap: isAnimating
                          ? null
                          : () => _change(seg, 'type', t),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: seg.type == t
                              ? const Color(0x4D3B82F6)
                              : palette.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          t,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: seg.type == t
                                ? const Color(0xFF60A5FA)
                                : palette.textSecondary,
                            fontWeight:
                                seg.type == t ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        );

    final roots = figure.getFigureRoots();
    final figRoot = _rootOfPoint(figure, seg.point1Index);
    final figIndex = roots.indexOf(figRoot);
    final figVisibleNow = figure.getFigureVisibility(figRoot, c.currentTime);
    final figKfCount = figure.getFigureVisibilityKeyframes(figRoot).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  '${seg.type} Segment',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  seg.hidden ? Icons.visibility_off : Icons.visibility,
                  size: 16,
                  color: seg.hidden ? const Color(0xFFFB923C) : palette.textSecondary,
                ),
                onPressed: () => _change(seg, 'hidden', !seg.hidden),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 16, color: Color(0xFFF87171)),
                onPressed: () {
                  figure.removeSegment(seg.id);
                  c.setSelectedSegment(null);
                  c.setSelectedPoint(null);
                  c.forceUpdate();
                  c.pushHistory();
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),

          if (isAnimating) ...[
            _Accordion(
              title: 'Figure ${figIndex + 1}',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            figure.setFigureVisibility(
                                figRoot, c.currentTime, !figVisibleNow);
                            c.forceUpdate();
                            c.pushHistory();
                          },
                          child: Row(
                            children: [
                              Icon(
                                figVisibleNow
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 16,
                                color: figVisibleNow
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFF6B7280),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                figVisibleNow ? 'Visible' : 'Invisible',
                                style: TextStyle(
                                  color: figVisibleNow
                                      ? palette.text
                                      : palette.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Text('$figKfCount kf',
                          style: TextStyle(
                              fontSize: 10, color: palette.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => c.removeFigureAt(figRoot),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x1AEF4444),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.delete, size: 14, color: Color(0xFFF87171)),
                          const SizedBox(width: 8),
                          Text('Hapus Figure dari Scene',
                              style: TextStyle(
                                  color: Color(0xFFF87171),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          _Accordion(
            title: 'Segment Type',
            child: typePicker(['line', 'circle', 'image', 'none']),
          ),

          _Accordion(
            title: 'Transform',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label('Panjang (Length)'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lengthController,
                        focusNode: _lengthFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        enabled: !isAnimating,
                        style: TextStyle(color: palette.text, fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: palette.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: palette.border),
                          ),
                          suffixText: 'px',
                          suffixStyle: TextStyle(
                              color: palette.textSecondary, fontSize: 11),
                        ),
                        onSubmitted: (v) {
                          final n = double.tryParse(v);
                          if (n != null) _setSegmentLength(seg, n);
                          _lengthFocus.unfocus();
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: isAnimating
                          ? null
                          : () {
                              final n = double.tryParse(
                                  _lengthController.text);
                              if (n != null) _setSegmentLength(seg, n);
                              _lengthFocus.unfocus();
                            },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0x4D3B82F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.check,
                            size: 14, color: Color(0xFF60A5FA)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                label('Sudut (Angle)'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _angleController,
                        focusNode: _angleFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        enabled: !isAnimating,
                        style: TextStyle(color: palette.text, fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: palette.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: palette.border),
                          ),
                          suffixText: 'Â°',
                          suffixStyle: TextStyle(
                              color: palette.textSecondary, fontSize: 11),
                        ),
                        onSubmitted: (v) {
                          final n = double.tryParse(v);
                          if (n != null) _setSegmentAngle(seg, n);
                          _angleFocus.unfocus();
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: isAnimating
                          ? null
                          : () {
                              final n =
                                  double.tryParse(_angleController.text);
                              if (n != null) _setSegmentAngle(seg, n);
                              _angleFocus.unfocus();
                            },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0x4D3B82F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.check,
                            size: 14, color: Color(0xFF60A5FA)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (seg.isNone) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x263B82F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.visibility_off,
                            size: 14, color: Color(0xFF60A5FA)),
                        const SizedBox(width: 8),
                        Text('Invisible Connector',
                            style: TextStyle(
                                color: palette.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Type "none" links two points without drawing a line or '
                      'using an asset. It affects structure, parenting and '
                      'animation, but is never rendered.',
                      style: TextStyle(
                          color: palette.textSecondary, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (seg.type != 'none')
            _Accordion(
            title: 'Appearance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label('Color'),
                ColorField(
                  palette: palette,
                  selected: parseHexColor(seg.color),
                  onChanged: (c2) => _change(seg, 'color', colorToHex(c2)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('Curved',
                          style: TextStyle(
                              color: palette.textSecondary, fontSize: 13)),
                    ),
                    Switch(
                      value: seg.curved,
                      onChanged: isAnimating ? null : (v) => _change(seg, 'curved', v),
                      activeTrackColor: const Color(0xFF3B82F6),
                    ),
                  ],
                ),
                if (seg.curved) ...[
                  const SizedBox(height: 8),
                  label('Curvature'),
                  TextField(
                    controller: TextEditingController(
                      text: seg.curvature.toStringAsFixed(2),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !isAnimating,
                    style: TextStyle(color: palette.text, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: palette.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null) _change(seg, 'curvature', n);
                    },
                  ),
                ],
                if (seg.type == 'line') ...[
                  const SizedBox(height: 12),
                  label('Line Width'),
                  TextField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    enabled: !isAnimating,
                    style: TextStyle(color: palette.text, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: palette.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null && n > 0) _change(seg, 'width', n);
                    },
                  ),
                  const SizedBox(height: 12),
                  label('Line Cap'),
                  typePicker(['round', 'square', 'butt']),
                ],
                if (seg.type == 'circle') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Filled',
                            style: TextStyle(
                                color: palette.textSecondary, fontSize: 13)),
                      ),
                      Switch(
                        value: seg.filled != false,
                        onChanged: isAnimating
                            ? null
                            : (v) => _change(seg, 'filled', v),
                        activeTrackColor: const Color(0xFF3B82F6),
                      ),
                    ],
                  ),
                  if (seg.filled != false) ...[
                    const SizedBox(height: 12),
                    label('Fill Color'),
                    ColorField(
                      palette: palette,
                      selected: parseHexColor(seg.fillColor),
                      onChanged: (c2) =>
                          _change(seg, 'fillColor', colorToHex(c2)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  label('Line Width'),
                  TextField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    enabled: !isAnimating,
                    style: TextStyle(color: palette.text, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: palette.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null && n > 0) _change(seg, 'width', n);
                    },
                  ),
                ],
              ],
            ),
          ),

          if (seg.type == 'image') _imageSection(seg, palette, isAnimating),

          _Accordion(
            title: 'Layer',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label('Group'),
                DropdownButtonFormField<String>(
                  value: figure.groupOf(seg.id),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: palette.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                  style: TextStyle(color: palette.text, fontSize: 13),
                  dropdownColor: palette.backgroundElement,
                  items: figure.orderedGroups().map((g) {
                    return DropdownMenuItem(
                      value: g.id,
                      child: Text(g.name,
                          style: TextStyle(color: palette.text, fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: isAnimating
                      ? null
                      : (v) {
                          if (v != null) {
                            c.moveSegmentToGroup(seg.id, v);
                            setState(() {});
                          }
                        },
                ),
                const SizedBox(height: 12),
                label('Z-Index (Layer)'),
                TextField(
                  controller: _layerController,
                  keyboardType: TextInputType.number,
                  enabled: !isAnimating,
                  style: TextStyle(color: palette.text, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: palette.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null) _change(seg, 'layer', n);
                  },
                ),
              ],
            ),
          ),

          _Accordion(
            title: 'Transform Whole',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label('Scale All (%)'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('scale-all-field'),
                        controller: _scaleAllController,
                        keyboardType: TextInputType.number,
                        enabled: !isAnimating,
                        style: TextStyle(color: palette.text, fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: palette.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: palette.border),
                          ),
                          suffixText: '%',
                          suffixStyle: TextStyle(
                              color: palette.textSecondary, fontSize: 11),
                        ),
                        onSubmitted: (v) => _applyScaleAll(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: isAnimating ? null : _applyScaleAll,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0x4D3B82F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.check,
                            size: 14, color: Color(0xFF60A5FA)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (figure.cycleFills.isNotEmpty)
            _Accordion(
              title: 'Cycle Fill',
              child: Column(
                children: figure.cycleFills.entries.map((e) {
                  final key = e.key;
                  final entry = e.value;
                  final pts = key
                      .split(',')
                      .map((p) => int.tryParse(p) ?? -1)
                      .toList();
                  if (!pts.contains(seg.point1Index) ||
                      !pts.contains(seg.point2Index)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Cycle (${pts.join(', ')})',
                                  style: TextStyle(
                                      color: palette.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_upward,
                                  size: 10, color: Color(0xFF60646C)),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                for (final ss in figure.segments) {
                                  if (pts.contains(ss.point1Index) &&
                                      pts.contains(ss.point2Index)) {
                                    ss.layer++;
                                  }
                                }
                                setState(() {});
                                c.forceUpdate();
                                c.pushHistory();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward,
                                  size: 10, color: Color(0xFF60646C)),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                for (final ss in figure.segments) {
                                  if (pts.contains(ss.point1Index) &&
                                      pts.contains(ss.point2Index)) {
                                    ss.layer =
                                        ss.layer > 0 ? ss.layer - 1 : 0;
                                  }
                                }
                                setState(() {});
                                c.forceUpdate();
                                c.pushHistory();
                              },
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(entry.filled ? 'Filled' : 'Empty',
                                  style: TextStyle(
                                      color: palette.textSecondary,
                                      fontSize: 13)),
                            ),
                            Switch(
                              value: entry.filled != false,
                              onChanged: (v) {
                                entry.filled = v;
                                setState(() {});
                                c.forceUpdate();
                                c.pushHistory();
                              },
                              activeTrackColor: const Color(0xFF3B82F6),
                            ),
                          ],
                        ),
                        if (entry.filled != false) ...[
                          const SizedBox(height: 8),
                          ColorField(
                            palette: palette,
                            selected: parseHexColor(entry.fillColor),
                            onChanged: (c2) {
                              entry.fillColor = colorToHex(c2);
                              setState(() {});
                              c.forceUpdate();
                              c.pushHistory();
                            },
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          _Accordion(
            title: 'Points',
            child: Column(
              children: [
                _pointRow('Point 1', figure.points, seg.point1Index, palette),
                _pointRow('Point 2', figure.points, seg.point2Index, palette),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _imageSection(Segment seg, AppPalette palette, bool isAnimating) {
    final c = widget.controller;
    Widget autoDimField(
      String axis,
      dynamic value,
      ValueChanged<dynamic> onChange,
    ) {
      final isAuto = value == 'auto';
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(
                  text: isAuto ? '' : value.toString()),
              enabled: !isAnimating && !isAuto,
              keyboardType: TextInputType.number,
              style: TextStyle(color: palette.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: isAuto ? 'auto' : '',
                hintStyle: TextStyle(color: palette.textSecondary),
                isDense: true,
                filled: true,
                fillColor: palette.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: palette.border),
                ),
              ),
              onChanged: (v) {
                final n = double.tryParse(v);
                onChange(n ?? 1);
              },
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: isAnimating
                ? null
                : () => onChange(isAuto ? 100 : 'auto'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isAuto ? const Color(0x4D3B82F6) : palette.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isAuto ? const Color(0xFF3B82F6) : palette.border,
                ),
              ),
              child: Text(
                'Auto',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isAuto ? const Color(0xFF60A5FA) : palette.textSecondary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget numericField(
      String label,
      double value,
      ValueChanged<double> onChange,
      String suffix,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: value.toString()),
                  enabled: !isAnimating,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: palette.text, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: palette.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (n != null) onChange(n);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Text(suffix,
                  style: TextStyle(color: palette.textSecondary, fontSize: 13)),
            ],
          ),
        ],
      );
    }

    void setImageDim(String axis, dynamic v) {
      if (axis == 'imageWidth') {
        seg.imageWidth = v;
      } else {
        seg.imageHeight = v;
      }
      if (seg.imageWidth == 'auto' && seg.imageHeight == 'auto') {
        seg.imageWidth = 100;
        seg.imageHeight = 'auto';
      }
      setState(() {});
      c.forceUpdate();
      c.pushHistory();
    }

    return _Accordion(
      title: 'Image',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sprite (${seg.imageDataList.length})',
              style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          if (seg.imageDataList.isEmpty) ...[
            InkWell(
              onTap: isAnimating ? null : () => _pickImage(seg),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: palette.border,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image, size: 16, color: palette.textSecondary),
                    const SizedBox(width: 8),
                    Text('Pilih Gambar',
                        style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ] else ...[
            _spriteStrip(seg, palette, isAnimating),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!isAnimating) ...[
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickImage(seg),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10),
                        decoration: BoxDecoration(
                          color: palette.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: palette.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                size: 14, color: palette.textSecondary),
                            const SizedBox(width: 6),
                            Text('Tambah Gambar',
                                style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: Text(
                      'Aktif frame ${_activeImageIndex(seg) + 1} dari '
                      '${seg.imageDataList.length}',
                      style: TextStyle(
                          color: palette.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text('Width',
              style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          autoDimField('imageWidth', seg.imageWidth, (v) => setImageDim('imageWidth', v)),
          const SizedBox(height: 12),
          Text('Height',
              style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          autoDimField('imageHeight', seg.imageHeight, (v) => setImageDim('imageHeight', v)),
          const SizedBox(height: 12),
          numericField('Offset X', seg.imageOffsetX, (v) {
            seg.imageOffsetX = v;
            setState(() {});
            c.forceUpdate();
            c.pushHistory();
          }, 'X'),
          const SizedBox(height: 8),
          numericField('Offset Y', seg.imageOffsetY, (v) {
            seg.imageOffsetY = v;
            setState(() {});
            c.forceUpdate();
            c.pushHistory();
          }, 'Y'),
          const SizedBox(height: 8),
          numericField('Rotate', seg.imageRotate, (v) {
            seg.imageRotate = v;
            setState(() {});
            c.forceUpdate();
            c.pushHistory();
          }, 'Â°'),
        ],
      ),
    );
  }

  /// Horizontal strip of sprite thumbnails. Tapping an image selects it: in
  /// figure mode it becomes [Segment.activeImageIndex]; in preset/animate mode
  /// it is recorded as a per-frame keyframe via [EditorController.selectSegmentImage].
  Widget _spriteStrip(Segment seg, AppPalette palette, bool isAnimating) {
    final c = widget.controller;
    final activeIdx = _activeImageIndex(seg);
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: seg.imageDataList.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isActive = i == activeIdx;
          return GestureDetector(
            onTap: () {
              c.selectSegmentImage(seg.id, i);
              setState(() {});
            },
            child: Stack(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFF3B82F6)
                          : palette.border,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: seg.imageDataList[i].isEmpty
                      ? const Icon(Icons.broken_image)
                      : Image.memory(
                          _decodeImageData(seg.imageDataList[i]),
                          fit: BoxFit.contain,
                        ),
                ),
                Positioned(
                  left: 2,
                  top: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9),
                    ),
                  ),
                ),
                if (isActive)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Icon(Icons.check_circle,
                        size: 14, color: const Color(0xFF3B82F6)),
                  ),
                if (!isAnimating)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: GestureDetector(
                      onTap: () {
                        c.removeSegmentImage(seg.id, i);
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xCCEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 10, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Active sprite index for the segment: in animate/preset mode the per-frame
  /// keyframe value (falling back to the segment's active index); otherwise the
  /// segment's active index directly.
  int _activeImageIndex(Segment seg) {
    if (widget.controller.isAnimateMode) {
      return widget.controller.figure
              .getSegmentImageIndex(seg.id, widget.controller.currentTime) ??
          seg.activeImageIndex;
    }
    return seg.activeImageIndex;
  }

  Uint8List _decodeImageData(String dataUri) {
    final comma = dataUri.indexOf(',');
    final b64 = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
    try {
      return base64Decode(b64);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Widget _pointRow(String label, List<Point2> points, int index, AppPalette palette) {
    final pt = index >= 0 && index < points.length ? points[index] : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: palette.textSecondary, fontSize: 12)),
          ),
          Text(
            pt == null ? 'â€”' : '(${pt.x.round()}, ${pt.y.round()})',
            style: TextStyle(color: palette.text, fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _empty(String message) {
    final palette = Theme.of(context).appColors;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.textSecondary, fontSize: 14),
      ),
    );
  }
}
