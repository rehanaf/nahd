part of '../figure_canvas.dart';

extension _DrawTool on _FigureCanvasState {
  void handleDrawStart(Offset w, EditorTool tool, Figure fig) {
    if (tool == EditorTool.line ||
        tool == EditorTool.circle ||
        tool == EditorTool.image ||
        tool == EditorTool.none ||
        tool == EditorTool.text) {
      final ptHit = _hitTestPoint(w);
      if (tool == EditorTool.text) {
        final p1 = fig.addPoint(w.dx, w.dy);
        final p2 = fig.addPoint(w.dx + 1, w.dy);
        final seg = fig.createSegment('text', p1, p2);
        _lastPt = p2;
        seg.text = 'Text';
        widget.controller.markSegmentBornAtCurrentFrame(seg);
        widget.controller.recordPointsAtCurrentFrame([p1, p2]);
        widget.controller.setSelectedSegment(seg.id);
        widget.controller.setSelectedPoint(p1);
        widget.controller.forceUpdate();
        widget.controller.pushHistory();
        _promptTextSegment(seg);
        return;
      }
      if (ptHit < 0) {
        if (fig.points.isEmpty) {
          final idx = fig.addPoint(w.dx, w.dy);
          _lastPt = idx;
          widget.controller.forceUpdate();
        }
        return;
      }
      final last = _lastPt;
      final alreadyConnected = last != null &&
          fig.segments.any((s) =>
              (s.point1Index == last && s.point2Index == ptHit) ||
              (s.point1Index == ptHit && s.point2Index == last));
      if (last != null && last != ptHit && !alreadyConnected) {
        final seg = fig.createSegment(tool.name, last, ptHit);
        widget.controller.markSegmentBornAtCurrentFrame(seg);
        widget.controller.recordPointsAtCurrentFrame([last, ptHit]);
        widget.controller.setSelectedSegment(seg.id);
        widget.controller.setSelectedPoint(ptHit);
        _lastPt = ptHit;
        widget.controller.forceUpdate();
        widget.controller.pushHistory();
        return;
      }
      final p2 = fig.addPoint(w.dx, w.dy);
      final seg = fig.createSegment(tool.name, ptHit, p2);
      widget.controller.markSegmentBornAtCurrentFrame(seg);
      widget.controller.recordPointsAtCurrentFrame([ptHit, p2]);
      _lastPt = p2;
      widget.controller.setSelectedSegment(seg.id);
      widget.controller.setSelectedPoint(p2);
      _drag
        ..reset()
        ..active = true
        ..isPoint = true
        ..ptIdx = p2
        ..creating = true
        ..startX = w.dx
        ..startY = w.dy
        ..startPtX = w.dx
        ..startPtY = w.dy
        ..anchorX = fig.points[ptHit].x
        ..anchorY = fig.points[ptHit].y;
      widget.controller.forceUpdate();
      return;
    }
  }

  Future<void> _promptTextSegment(Segment seg) async {
    final controller = TextEditingController(text: seg.text ?? '');
    final sizeController =
        TextEditingController(text: seg.textSize.toStringAsFixed(0));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17191E),
        title: const Text('Text', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Type something…',
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.lightBlueAccent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sizeController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Size',
                  labelStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.lightBlueAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('ok'),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == 'ok') {
      final text = controller.text.trim();
      final newText = text.isEmpty ? 'Text' : text;
      final size = double.tryParse(sizeController.text);
      final newSize = (size == null || size <= 0) ? 32.0 : size;
      widget.controller.recordSegmentValue(seg, 'text', seg.text, newText);
      widget.controller.recordSegmentValue(
          seg, 'textSize', seg.textSize, newSize);
      seg.text = newText;
      seg.textSize = newSize;

      // Keep the two text points so the label renders even before the next
      // layout, and push a single undoable change.
      seg.point1Index = seg.point1Index;
      widget.controller.forceUpdate();
      widget.controller.pushHistory();
    }
    controller.dispose();
    sizeController.dispose();
  }
}
