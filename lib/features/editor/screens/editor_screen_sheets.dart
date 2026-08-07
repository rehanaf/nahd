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


