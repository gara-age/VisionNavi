import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/colors.dart';

class ActionPanel extends StatelessWidget {
  const ActionPanel({
    super.key,
    required this.isRunning,
    required this.onStop,
    required this.onSelectSearchDemo,
    required this.onSelectNotepadDemo,
    required this.onSelectWorkspaceDemo,
    required this.onSelectDarkModeDemo,
  });

  final bool isRunning;
  final VoidCallback? onStop;
  final VoidCallback onSelectSearchDemo;
  final VoidCallback onSelectNotepadDemo;
  final VoidCallback onSelectWorkspaceDemo;
  final VoidCallback onSelectDarkModeDemo;

  @override
  Widget build(BuildContext context) {
    final surfaceTheme = Theme.of(context).extension<AppSurfaceTheme>()!;

    return Container(
      color: surfaceTheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: surfaceTheme.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            _CommandButton(
              icon: Icons.search_rounded,
              title: 'Search and Read',
              description: 'Run the Naver search demo flow.',
              shortcut: 'Demo',
              onPressed: onSelectSearchDemo,
            ),
            const SizedBox(height: 6),
            _CommandButton(
              icon: Icons.note_alt_rounded,
              title: 'Open Notepad',
              description: 'Create note text and open it in Notepad.',
              shortcut: 'Demo',
              onPressed: onSelectNotepadDemo,
            ),
            const SizedBox(height: 6),
            _CommandButton(
              icon: Icons.folder_open_rounded,
              title: 'Workspace Files',
              description: 'Open the safe workspace and list its files.',
              shortcut: 'Demo',
              onPressed: onSelectWorkspaceDemo,
            ),
            const SizedBox(height: 6),
            _CommandButton(
              icon: Icons.dark_mode_rounded,
              title: 'Dark Mode',
              description: 'Switch Windows to dark mode without approval.',
              shortcut: 'Demo',
              onPressed: onSelectDarkModeDemo,
            ),
            const SizedBox(height: 12),
            Divider(color: surfaceTheme.border, height: 1),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Session Control',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: surfaceTheme.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const _ModeInfo(
              label: 'Auto-run Policy',
              description: 'Low-risk tasks auto-run. Medium and high-risk actions can trigger an approval gate before execution.',
              selected: true,
            ),
            const SizedBox(height: 6),
            _ModeInfo(
              label: 'Stop Current Session',
              description: isRunning
                  ? 'Interrupt the active session stream and stop execution.'
                  : 'No active session is running right now.',
              selected: isRunning,
              onTap: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.icon,
    required this.title,
    required this.description,
    required this.shortcut,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String shortcut;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final surfaceTheme = Theme.of(context).extension<AppSurfaceTheme>()!;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        backgroundColor: surfaceTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: surfaceTheme.contentBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: surfaceTheme.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: surfaceTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: surfaceTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: surfaceTheme.contentBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: surfaceTheme.border),
            ),
            child: Text(
              shortcut,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: surfaceTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeInfo extends StatelessWidget {
  const _ModeInfo({
    required this.label,
    required this.description,
    required this.selected,
    this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final surfaceTheme = Theme.of(context).extension<AppSurfaceTheme>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : surfaceTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0x662563EB) : surfaceTheme.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : surfaceTheme.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: surfaceTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: surfaceTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
