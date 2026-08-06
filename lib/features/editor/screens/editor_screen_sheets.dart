part of 'editor_screen.dart';

// =========================================================================
// Sidebar buttons & modal sheets
// =========================================================================
class _LineCapButton extends StatelessWidget {
  final Segment? selectedSeg;
  final VoidCallback onTap;

  const _LineCapButton({required this.selectedSeg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final disabled = selectedSeg == null;
    String letter = '-';
    if (selectedSeg != null) {
      letter = switch (selectedSeg!.lineCap) {
        'round' => 'R',
        'square' => 'S',
        'butt' => 'B',
        _ => '-',
      };
    }
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: disabled ? palette.border : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({required this.icon, required this.label, required this.onTap});

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

class _AddFigureSheet extends StatelessWidget {
  final List<ProjectMeta> projects;

  const _AddFigureSheet({required this.projects});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Text(
                        'Add Figure',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: palette.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 1),
              if (projects.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No figures yet. Create one in the Figure workspace.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.textSecondary, fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: projects.length,
                    itemBuilder: (context, i) {
                      final p = projects[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(p),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: palette.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: palette.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0x2622C55E),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.add,
                                      size: 14, color: Color(0xFF22C55E)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.text,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        DateTime.fromMillisecondsSinceEpoch(p.updatedAt)
                                            .toLocal()
                                            .toString()
                                            .split(' ')[0],
                                        style: TextStyle(
                                            color: palette.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet asking which segment type to create when the user taps the
/// "New Segment" button. Each choice returns the segment type string.
class _NewSegmentSheet extends StatelessWidget {
  const _NewSegmentSheet();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    const options = [
      ('line', Icons.show_chart, 'Line', 'A straight or curved connector'),
      ('circle', Icons.panorama_fish_eye, 'Circle', 'A round connector'),
      ('image', Icons.image, 'Image', 'A raster image asset'),
      ('none', Icons.link_off, 'None', 'An invisible structural link'),
    ];
    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'New Segment',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: palette.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 1),
              const SizedBox(height: 12),
              for (final (type, icon, title, desc) in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(type),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0x2622C55E),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(icon, size: 18, color: const Color(0xFF22C55E)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  desc,
                                  style: TextStyle(
                                      color: palette.textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: palette.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
