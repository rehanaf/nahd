import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/app_version.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/app_controller.dart';
import '../../update/update_dialog.dart';

class ProfileScreen extends StatelessWidget {
  final AppController app;
  final VoidCallback onClearData;

  const ProfileScreen({
    super.key,
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

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.backgroundElement,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
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
                          fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
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
                          height: 34,
                          child: TextField(
                            controller:
                                TextEditingController(text: profileName),
                            style: TextStyle(
                                color: palette.text, fontSize: 17),
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
            const SizedBox(height: 20),
            Text(
              'THEME',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: palette.backgroundElement,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: themeOptions.map((opt) {
                  final active = themeMode == opt.$1;
                  return Expanded(
                    child: InkWell(
                      onTap: () => app.setThemeMode(opt.$1),
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: active
                              ? palette.background
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
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
            const SizedBox(height: 20),
            Text(
              'DATA',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: onClearData,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: palette.backgroundElement,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.database,
                        size: 16, color: Color(0xFFF87171)),
                    SizedBox(width: 10),
                    Text(
                      'Clear All Data',
                      style: TextStyle(
                        color: Color(0xFFF87171),
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
                await showUpdateDialogIfAny(context,
                    showSnackIfUpToDate: true);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: palette.backgroundElement,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.download,
                        size: 16, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 10),
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
            const SizedBox(height: 24),
            Divider(color: palette.border, height: 1),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Version $appVersion ($appBuildNumber)',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
