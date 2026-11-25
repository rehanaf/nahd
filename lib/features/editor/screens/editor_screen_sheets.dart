part of 'editor_screen.dart';

// =========================================================================
// Sidebar buttons & modal sheets
// =========================================================================

class _ExportOption {
  final String key;
  final String label;
  const _ExportOption.fps() : key = 'fps', label = 'Frames per second (1–60)';
  const _ExportOption.scale() : key = 'scale', label = 'Scale (1–8)';
}

class _ExportOptions {
  final double fps;
  final double scale;
  final bool loop;
  const _ExportOptions({
    required this.fps,
    required this.scale,
    this.loop = false,
  });
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: palette.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: palette.text, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for the pose / template library: save the current figure as a
/// named pose, apply a saved pose to the rig, rename and delete entries.
class PoseLibrarySheet extends StatefulWidget {
  final EditorController controller;
  const PoseLibrarySheet({super.key, required this.controller});

  @override
  State<PoseLibrarySheet> createState() => _PoseLibrarySheetState();
}

class _PoseLibrarySheetState extends State<PoseLibrarySheet> {
  List<PoseTemplate> _poses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final poses = await PoseLibrary.load();
    if (!mounted) return;
    setState(() => _poses = poses);
  }

  Future<void> _promptName({
    required String initial,
    required Future<void> Function(String) onOk,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17191E),
        title: const Text('Pose name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.lightBlueAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (result == true && name.isNotEmpty) {
      await onOk(name);
    }
  }

  Future<void> _saveCurrent() async {
    final fig = widget.controller.figure;
    await _promptName(
      initial: 'Pose ${_poses.length + 1}',
      onOk: (name) async {
        _poses = await PoseLibrary.savePose(fig);
        if (_poses.isNotEmpty) _poses.last.name = name;
        await PoseLibrary.rename(_poses.last.id, name);
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _apply(PoseTemplate pose) async {
    final fig = pose.figure();
    widget.controller.setFigure(fig);
    widget.controller.forceUpdate();
    widget.controller.pushHistory();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete(PoseTemplate pose) async {
    _poses = await PoseLibrary.delete(pose.id);
    if (mounted) setState(() {});
  }

  Future<void> _rename(PoseTemplate pose) async {
    await _promptName(
      initial: pose.name,
      onOk: (name) async {
        _poses = await PoseLibrary.rename(pose.id, name);
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.backgroundElement,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.backgroundSelected),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pose Library',
            style: TextStyle(
              color: palette.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Guides for posing your rig. Save a snapshot of the figure layout '
            'and re-apply it with one tap.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _saveCurrent,
            icon: const Icon(LucideIcons.save, size: 16),
            label: const Text('Save current pose'),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _poses.isEmpty
                ? Center(
                    child: Text(
                      'No poses yet',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  )
                : ListView.separated(
                    itemCount: _poses.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final pose = _poses[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(LucideIcons.accessibility),
                        title: Text(
                          pose.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${pose.figure().points.length} points',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.pencil, size: 16),
                              onPressed: () => _rename(pose),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.trash, size: 16),
                              onPressed: () => _delete(pose),
                            ),
                          ],
                        ),
                        onTap: () => _apply(pose),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
