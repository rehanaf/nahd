import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/models/figure.dart';
import '../../../core/models/segment.dart';
import '../controllers/editor_controller.dart';
import '../../../core/theme/app_theme.dart';

class LayerPanel extends StatefulWidget {
  final EditorController controller;

  const LayerPanel({super.key, required this.controller});

  @override
  State<LayerPanel> createState() => _LayerPanelState();
}

sealed class _Item {
  String get key;
}

class _HeaderItem extends _Item {
  final LayerGroup group;
  _HeaderItem(this.group);
  @override
  String get key => 'g:${group.id}';
}

class _SegItem extends _Item {
  final String segId;
  final Segment seg;
  _SegItem(this.segId, this.seg);
  @override
  String get key => 's:$segId';
}

class _LayerPanelState extends State<LayerPanel> {
  final Set<String> _collapsed = <String>{};
  String? _renamingId;
  final TextEditingController _renameController = TextEditingController();

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  List<_Item> _buildFlat() {
    final fig = widget.controller.figure;
    final ordered = fig.orderedGroups();
    final segMap = <String, Segment>{
      for (final s in fig.segments) s.id: s,
    };
    final items = <_Item>[];
    for (final g in ordered) {
      items.add(_HeaderItem(g));
      if (!_collapsed.contains(g.id)) {
        for (final segId in g.segmentIds) {
          final seg = segMap[segId];
          if (seg != null) items.add(_SegItem(segId, seg));
        }
      }
    }
    return items;
  }

  void _onReorder(int oldIndex, int newIndex) {
    final c = widget.controller;
    final fig = c.figure;

    final items = _buildFlat();
    if (oldIndex < 0 || oldIndex >= items.length) return;
    final moved = items[oldIndex];

    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, items.length - 1);
    items.removeAt(oldIndex);
    items.insert(newIndex, moved);

    if (moved is _HeaderItem) {
      final headerIds = items
          .whereType<_HeaderItem>()
          .map((h) => h.group.id)
          .toList();
      final byId = {for (final g in fig.groups) g.id: g};
      final reordered = <LayerGroup>[];
      for (final id in headerIds) {
        final g = byId[id];
        if (g != null) reordered.add(g);
      }
      fig.groups
        ..clear()
        ..addAll(reordered);
      fig.ensureDefaultGroup();
      c.pushHistory();
      c.forceUpdate();
    } else if (moved is _SegItem) {
      final movedIdx = items.indexOf(moved);
      String? targetGroupId;
      for (var i = movedIdx; i >= 0; i--) {
        if (items[i] is _HeaderItem) {
          targetGroupId = (items[i] as _HeaderItem).group.id;
          break;
        }
      }
      targetGroupId ??= fig.orderedGroups().first.id;

      var posInGroup = 0;
      var inTarget = false;
      for (var i = 0; i < movedIdx; i++) {
        final it = items[i];
        if (it is _HeaderItem) {
          inTarget = it.group.id == targetGroupId;
          continue;
        }
        if (inTarget) posInGroup++;
      }
      c.placeSegmentInGroup(moved.segId, targetGroupId, posInGroup);
    }
  }

  void _startRename(LayerGroup g) {
    _renamingId = g.id;
    _renameController.text = g.name;
    setState(() {});
  }

  void _commitRename(LayerGroup g) {
    widget.controller.renameLayerGroup(g.id, _renameController.text);
    _renamingId = null;
    setState(() {});
  }

  void _toggleCollapsed(String id) {
    setState(() {
      if (!_collapsed.add(id)) _collapsed.remove(id);
    });
  }

  void _onSelectSegment(String segId, Segment seg) {
    widget.controller.setSelectedSegment(segId);
    widget.controller.setSelectedPoint(seg.point1Index);
    widget.controller.forceUpdate();
  }

  void _onToggleSegmentVisible(Segment seg) {
    seg.hidden = !seg.hidden;
    widget.controller.forceUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final c = widget.controller;
    final readOnly = c.isAnimateMode;
    final items = _buildFlat();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Layer Groups',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!readOnly)
                IconButton(
                  icon: const Icon(LucideIcons.plus, size: 18),
                  color: palette.textSecondary,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => c.addLayerGroup(),
                  tooltip: 'New group',
                ),
            ],
          ),
        ),
        Expanded(
          child: Builder(builder: (context) {
            if (readOnly) {
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item is _HeaderItem) {
                    final g = item.group;
                    return _GroupHeaderRow(
                      key: ValueKey(item.key),
                      index: index,
                      palette: palette,
                      group: g,
                      isDefault: g.id == Figure.defaultGroupId,
                      expanded: !_collapsed.contains(g.id),
                      renaming: _renamingId == g.id,
                      renameController: _renameController,
                      readOnly: true,
                      onCollapse: () => _toggleCollapsed(g.id),
                      onVisible: () {},
                      onLock: () {},
                      onRename: () {},
                      onRemove: () {},
                      onCommitRename: () {},
                      onCancelRename: () {},
                    );
                  } else if (item is _SegItem) {
                    return _SegmentDragRow(
                      key: ValueKey(item.key),
                      index: index,
                      seg: item.seg,
                      palette: palette,
                      readOnly: true,
                      selected: c.selectedSegmentId == item.segId,
                      onTap: () => _onSelectSegment(item.segId, item.seg),
                      onToggleVisible: () {},
                    );
                  }
                  return const SizedBox.shrink(key: ValueKey('empty'));
                },
              );
            }
            return ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              buildDefaultDragHandles: false,
              itemCount: items.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                elevation: 4,
                child: child,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is _HeaderItem) {
                  final g = item.group;
                  final isDefault = g.id == Figure.defaultGroupId;
                  return _GroupHeaderRow(
                    key: ValueKey(item.key),
                    index: index,
                    palette: palette,
                    group: g,
                    isDefault: isDefault,
                    expanded: !_collapsed.contains(g.id),
                    renaming: _renamingId == g.id,
                    renameController: _renameController,
                    readOnly: false,
                    onCollapse: () => _toggleCollapsed(g.id),
                    onVisible: () => c.toggleGroupVisible(g.id),
                    onLock: () => c.toggleGroupLocked(g.id),
                    onRename: () => _startRename(g),
                    onRemove: () => c.removeLayerGroup(g.id),
                    onCommitRename: () => _commitRename(g),
                    onCancelRename: () => setState(() => _renamingId = null),
                  );
                } else if (item is _SegItem) {
                  return _SegmentDragRow(
                    key: ValueKey(item.key),
                    index: index,
                    seg: item.seg,
                    palette: palette,
                    selected: c.selectedSegmentId == item.segId,
                    onTap: () => _onSelectSegment(item.segId, item.seg),
                    onToggleVisible: () => _onToggleSegmentVisible(item.seg),
                  );
                }
                return const SizedBox.shrink(key: ValueKey('empty'));
              },
            );
          }),
        ),
      ],
    );
  }
}

class _GroupHeaderRow extends StatelessWidget {
  final int index;
  final AppPalette palette;
  final LayerGroup group;
  final bool isDefault;
  final bool expanded;
  final bool renaming;
  final bool readOnly;
  final TextEditingController renameController;
  final VoidCallback onCollapse;
  final VoidCallback onVisible;
  final VoidCallback onLock;
  final VoidCallback onRename;
  final VoidCallback onRemove;
  final VoidCallback onCommitRename;
  final VoidCallback onCancelRename;

  const _GroupHeaderRow({
    super.key,
    required this.index,
    required this.palette,
    required this.group,
    required this.isDefault,
    required this.expanded,
    required this.renaming,
    this.readOnly = false,
    required this.renameController,
    required this.onCollapse,
    required this.onVisible,
    required this.onLock,
    required this.onRename,
    required this.onRemove,
    required this.onCommitRename,
    required this.onCancelRename,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.backgroundSelected,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (!readOnly)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(LucideIcons.grip_vertical, size: 16),
              ),
            ),
          if (!readOnly) const SizedBox(width: 2),
          InkWell(
            onTap: onCollapse,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                expanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
                size: 16,
                color: palette.textSecondary,
              ),
            ),
          ),
          Icon(LucideIcons.folder,
              size: 16,
              color:
                  isDefault ? palette.textSecondary : const Color(0xFF0D9488)),
          const SizedBox(width: 6),
          Expanded(
            child: renaming
                ? TextField(
                    controller: renameController,
                    autofocus: true,
                    style: TextStyle(color: palette.text, fontSize: 13),
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (_) => onCommitRename(),
                  )
                : GestureDetector(
                    onDoubleTap: isDefault || readOnly ? null : onRename,
                    child: Text(
                      '$name${group.locked ? ' \u{1F512}' : ''}',
                      style: TextStyle(
                        color: group.visible
                            ? palette.text
                            : palette.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
          if (!readOnly) ...[
            _IconBtn(
              icon: group.visible ? LucideIcons.eye : LucideIcons.eye_off,
              active: group.visible,
              onTap: onVisible,
            ),
            _IconBtn(
              icon: group.locked ? LucideIcons.lock : LucideIcons.lock_open,
              active: group.locked,
              color: group.locked ? const Color(0xFF2563EB) : null,
              onTap: onLock,
            ),
            if (!isDefault)
              _IconBtn(
                icon: LucideIcons.pencil,
                color: palette.textSecondary,
                onTap: onRename,
              ),
            if (!isDefault)
              _IconBtn(
                icon: LucideIcons.trash,
                color: palette.textSecondary,
                onTap: onRemove,
              ),
          ],
        ],
      ),
    );
  }

  String get name => group.name;
}

class _SegmentDragRow extends StatelessWidget {
  final int index;
  final Segment seg;
  final AppPalette palette;
  final bool selected;
  final bool readOnly;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;

  const _SegmentDragRow({
    super.key,
    required this.index,
    required this.seg,
    required this.palette,
    this.readOnly = false,
    required this.selected,
    required this.onTap,
    required this.onToggleVisible,
  });

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (seg.type) {
      'circle' => ('Circle', LucideIcons.circle),
      'image' => ('Image', LucideIcons.image),
      'none' => ('Link', LucideIcons.link),
      _ => ('Line', LucideIcons.trending_up),
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 16, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? palette.backgroundElement : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? palette.border : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (!readOnly)
              ReorderableDelayedDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(LucideIcons.grip_vertical,
                      size: 14, color: palette.textSecondary),
                ),
              ),
            if (!readOnly) const SizedBox(width: 4),
            Icon(
              icon,
              size: 14,
              color: parseHexColor(seg.color) ?? palette.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: seg.hidden ? palette.textSecondary : palette.text,
                  fontSize: 12,
                  decoration: seg.hidden ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (!readOnly)
              InkWell(
                onTap: onToggleVisible,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    seg.hidden ? LucideIcons.eye_off : LucideIcons.eye,
                    size: 14,
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color? color;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    this.active = false,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(
          icon,
          size: 15,
          color: color ??
              (active ? const Color(0xFF0D9488) : const Color(0xFF9AA0A6)),
        ),
      ),
    );
  }
}
