part of 'main_menu_screen.dart';

// =========================================================================
// Menu / sort / name / confirm / profile sheets
// =========================================================================
class _MenuOption {
  final String key;
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuOption(this.key, this.icon, this.label, [this.color]);
}

class _MenuSheet extends StatelessWidget {
  final List<_MenuOption> options;
  final ValueChanged<String> onSelected;

  const _MenuSheet({required this.options, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: options.map((item) {
              final color = item.color ?? palette.text;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(item.icon, size: 20, color: color),
                title: Text(
                  item.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => onSelected(item.key),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  final _SortOption current;
  final ValueChanged<String> onSelected;

  const _SortSheet({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final options = [
      ('type', 'Type (Group, Project)'),
      ('name', 'Name'),
      ('modified', 'Last Modified'),
    ];
    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Text(
                  'Sort By',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              ...options.map((opt) {
                final active = current.name == opt.$1;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(
                    active ? LucideIcons.circle_dot : LucideIcons.circle,
                    size: 20,
                    color: active ? const Color(0xFF3B82F6) : palette.textSecondary,
                  ),
                  title: Text(
                    opt.$2,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => onSelected(opt.$1),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameSheet extends StatefulWidget {
  final String title;
  final String placeholder;
  final String buttonLabel;
  final TextEditingController controller;

  const _NameSheet({
    required this.title,
    required this.placeholder,
    required this.buttonLabel,
    required this.controller,
  });

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(LucideIcons.x, size: 18, color: palette.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: widget.controller,
                autofocus: true,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  hintText: widget.placeholder,
                  hintStyle: TextStyle(color: palette.textSecondary),
                  filled: true,
                  fillColor: palette.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: palette.backgroundSelected),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: palette.text)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, widget.controller.text),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(widget.buttonLabel),
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

class _ConfirmSheet extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final bool danger;

  const _ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x, size: 18, color: palette.textSecondary),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(body,
                  style: TextStyle(color: palette.textSecondary, fontSize: 14)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel', style: TextStyle(color: palette.text)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: danger
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(confirmLabel),
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

class _ProfileSheet extends StatelessWidget {
  final AppController app;
  final VoidCallback onClearData;

  const _ProfileSheet({
    required this.app,
    required this.onClearData,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final themeMode = app.themeMode;
    final profileName = app.profileName;
    final initials = ((profileName.trim().isEmpty ? 'G' : profileName.trim())
            .substring(0, 2))
        .toUpperCase();
    final isDark = themeMode == 'dark' ||
        (themeMode == 'device' && Theme.of(context).brightness == Brightness.dark);

    final themeOptions = [
      ('light', LucideIcons.sun, 'Light'),
      ('dark', LucideIcons.moon, 'Dark'),
      ('device', LucideIcons.smartphone, 'Device'),
    ];

    return Material(
      color: palette.backgroundElement,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Menu',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 18, color: palette.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profile',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(
                                height: 30,
                                child: TextField(
                                  controller:
                                      TextEditingController(text: profileName),
                                  style: TextStyle(
                                      color: palette.text, fontSize: 16),
                                  onSubmitted: (v) => app.setProfileName(v),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hintText: 'Name',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Theme',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: themeOptions.map((opt) {
                        final active = themeMode == opt.$1;
                        return Expanded(
                          child: InkWell(
                            onTap: () => app.setThemeMode(opt.$1),
                            borderRadius: BorderRadius.circular(9),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(opt.$2,
                                      size: 16,
                                      color: active
                                          ? palette.text
                                          : palette.textSecondary),
                                  const SizedBox(width: 6),
                                  Text(
                                    opt.$3,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: active
                                          ? palette.text
                                          : palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Data',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: onClearData,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.database,
                              size: 15, color: Color(0xFFF87171)),
                          const SizedBox(width: 8),
                          Text(
                            'Clear All Data',
                            style: TextStyle(
                              color: const Color(0xFFF87171),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                   const SizedBox(height: 8),
                   InkWell(
                     onTap: () async {
                       Navigator.pop(context);
                       await showUpdateDialogIfAny(context,
                           showSnackIfUpToDate: true);
                     },
                     borderRadius: BorderRadius.circular(12),
                     child: Container(
                       padding: const EdgeInsets.symmetric(
                           horizontal: 12, vertical: 12),
                       decoration: BoxDecoration(
                         color: palette.background,
                         borderRadius: BorderRadius.circular(12),
                       ),
                       child: Row(
                         children: [
                           const Icon(LucideIcons.download,
                               size: 16, color: Color(0xFF3B82F6)),
                           const SizedBox(width: 8),
                           Text(
                              'Periksa Pembaruan',
                             style: TextStyle(
                               color: palette.text,
                               fontSize: 14,
                               fontWeight: FontWeight.w600,
                             ),
                           ),
                         ],
                       ),
                     ),
                   ),
                  const SizedBox(height: 20),
                  Divider(color: palette.border, height: 1),
                  const SizedBox(height: 12),
                  _SquircleTestSection(palette: palette),
                  const SizedBox(height: 16),
                  Text(
                    'Version $appVersion ($appBuildNumber)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _SquircleTestSection extends StatefulWidget {
  final AppPalette palette;
  const _SquircleTestSection({required this.palette});

  @override
  State<_SquircleTestSection> createState() => _SquircleTestSectionState();
}

class _SquircleTestSectionState extends State<_SquircleTestSection> {
  double _smoothness = 0.6;
  bool _switchActive = true;
  int _activeTab = 0;

  static const _values = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.backgroundSelected),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.sliders_horizontal,
                  size: 16, color: Color(0xFF3B82F6)),
              const SizedBox(width: 8),
              Text(
                'Squircle Showcase & Test',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: SmoothContainer(
              width: 92,
              height: 92,
              smoothness: _smoothness,
              borderRadius: BorderRadius.circular(30),
              color: const Color(0xFF2563EB),
              child: Center(
                child: Text(
                  _smoothness.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _values.map((v) {
              final selected = (v - _smoothness).abs() < 0.001;
              return GestureDetector(
                onTap: () => setState(() => _smoothness = v),
                child: Column(
                  children: [
                    SmoothContainer(
                      width: 48,
                      height: 48,
                      smoothness: v,
                      borderRadius: BorderRadius.circular(18),
                      color: selected
                          ? const Color(0xFF2563EB)
                          : palette.backgroundElement,
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF60A5FA)
                            : palette.backgroundSelected,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      v.toStringAsFixed(1),
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF60A5FA)
                            : palette.textSecondary,
                        fontSize: 10,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Smoothness: ${_smoothness.toStringAsFixed(1)}',
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
          Slider(
            value: _smoothness,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: _smoothness.toStringAsFixed(1),
            onChanged: (v) => setState(() => _smoothness = v),
          ),
          const SizedBox(height: 8),
          SmoothContainer(
            smoothness: _smoothness,
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF2563EB),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text(
                      'Test Button (Squircle)',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SmoothContainer(
                  smoothness: _smoothness,
                  borderRadius: BorderRadius.circular(22),
                  color: palette.backgroundElement,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.sparkles,
                          size: 14, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 6),
                      Text('Capsule',
                          style: TextStyle(
                              color: palette.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _switchActive = !_switchActive),
                child: SmoothContainer(
                  smoothness: _smoothness,
                  borderRadius: BorderRadius.circular(22),
                  color: _switchActive
                      ? const Color(0xFF2563EB)
                      : palette.backgroundElement,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    _switchActive ? 'Active' : 'Off',
                    style: TextStyle(
                        color: _switchActive
                            ? Colors.white
                            : palette.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SmoothContainer(
            smoothness: _smoothness,
            borderRadius: BorderRadius.circular(16),
            color: palette.backgroundElement,
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (int i = 0; i < 3; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = i),
                      child: SmoothContainer(
                        smoothness: _smoothness,
                        borderRadius: BorderRadius.circular(12),
                        color: _activeTab == i
                            ? const Color(0xFF2563EB)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Text(
                            'Tab ${i + 1}',
                            style: TextStyle(
                              color: _activeTab == i
                                  ? Colors.white
                                  : palette.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
