import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../application/blocs/vault_bloc.dart';
import '../../application/blocs/auth_bloc.dart';

class VaultStatusScreen extends StatelessWidget {
  const VaultStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Vault Status'),
        titleWidth: 200,
        leading: MacosTooltip(
          message: 'Toggle Sidebar',
          child: MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.sidebar_left),
            onPressed: () {
              MacosWindowScope.of(context).toggleSidebar();
            },
          ),
        ),
        actions: [
          ToolBarIconButton(
            tooltipMessage: 'Reset All Data',
            icon: const MacosIcon(
              CupertinoIcons.trash,
              color: MacosColors.systemRedColor,
            ),
            onPressed: () => _showResetConfirmation(context),
            label: 'Reset All',
            showLabel: false,
          ),
          ToolBarIconButton(
            tooltipMessage: 'Lock Vault (⌘L)',
            icon: const MacosIcon(CupertinoIcons.lock),
            onPressed: () => context.read<AuthBloc>().add(LockRequested()),
            label: 'Lock Vault (⌘L)',
            showLabel: false,
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return BlocBuilder<VaultBloc, VaultState>(
              builder: (context, state) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security Overview',
                        style: MacosTheme.of(context).typography.largeTitle,
                      ),
                      const SizedBox(height: 24),
                      _buildStatusCard(context, state),
                      const SizedBox(height: 32),
                      Text(
                        'Recent Activity',
                        style: MacosTheme.of(context).typography.title2,
                      ),
                      const SizedBox(height: 16),
                      _buildActivityList(context),
                      const SizedBox(height: 32),
                      _buildSecurityFeatures(context),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context, VaultState state) {
    int fileCount = 0;
    int totalSize = 0;

    if (state is VaultLoaded) {
      fileCount = state.files.length;
      totalSize = state.totalSize;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MacosTheme.of(context).brightness.isDark
            ? MacosColors.systemGrayColor.withOpacity(0.1)
            : MacosColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MacosColors.systemGrayColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildStat(
                context,
                'Vault Status',
                'Unlocked',
                CupertinoIcons.lock_open_fill,
                MacosColors.systemGreenColor,
              ),
              const Spacer(),
              _buildStat(
                context,
                'Total Files',
                fileCount.toString(),
                CupertinoIcons.doc_fill,
                MacosColors.systemBlueColor,
              ),
              const Spacer(),
              _buildStat(
                context,
                'Vault Size',
                _formatFileSize(totalSize),
                CupertinoIcons.chart_pie_fill,
                MacosColors.systemOrangeColor,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          Row(
            children: [
              const MacosIcon(
                CupertinoIcons.checkmark_shield_fill,
                color: MacosColors.systemGreenColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AES-256-GCM Encryption Active',
                    style: MacosTheme.of(context).typography.headline,
                  ),
                  Text(
                    'Your files are protected by hardware-accelerated encryption.',
                    style: MacosTheme.of(context).typography.caption1,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: MacosIcon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: MacosTheme.of(context).typography.caption1.copyWith(
                      color: MacosColors.secondaryLabelColor,
                    ),
              ),
              Text(
                value,
                style: MacosTheme.of(
                  context,
                ).typography.title3.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityList(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MacosTheme.of(context).brightness.isDark
            ? MacosColors.systemGrayColor.withOpacity(0.05)
            : MacosColors.systemGrayColor.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildActivityItem(
            context,
            'Vault Unlocked',
            'Just now • via PIN',
            CupertinoIcons.lock_open,
          ),
          const Divider(indent: 48),
          _buildActivityItem(
            context,
            'Security Scan',
            '2 hours ago • No threats found',
            CupertinoIcons.checkmark_shield,
          ),
          const Divider(indent: 48),
          _buildActivityItem(
            context,
            'Last Backup',
            'Yesterday • Local Package',
            CupertinoIcons.cloud_upload,
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          MacosIcon(icon, size: 20, color: MacosColors.secondaryLabelColor),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: MacosTheme.of(context).typography.body),
              Text(
                subtitle,
                style: MacosTheme.of(context).typography.caption1.copyWith(
                      color: MacosColors.secondaryLabelColor,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityFeatures(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Security Features',
          style: MacosTheme.of(context).typography.title2,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildFeatureTile(
              context,
              'Auto-Lock',
              'Active',
              CupertinoIcons.timer,
              MacosColors.systemBlueColor,
            ),
            _buildFeatureTile(
              context,
              'Crypto-Shred',
              'Enabled',
              CupertinoIcons.trash,
              MacosColors.systemRedColor,
            ),
            _buildFeatureTile(
              context,
              'Biometrics',
              'Available',
              CupertinoIcons.person_crop_circle_badge_checkmark,
              MacosColors.systemPurpleColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureTile(
    BuildContext context,
    String label,
    String status,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MacosTheme.of(context).brightness.isDark
            ? MacosColors.systemGrayColor.withOpacity(0.1)
            : MacosColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MacosColors.systemGrayColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MacosIcon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(label, style: MacosTheme.of(context).typography.headline),
          const SizedBox(height: 4),
          Text(
            status,
            style: MacosTheme.of(context).typography.caption1.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showResetConfirmation(BuildContext context) {
    showMacosAlertDialog(
      context: context,
      builder: (context) => MacosAlertDialog(
        appIcon: const MacosIcon(
          CupertinoIcons.trash_fill,
          color: MacosColors.systemRedColor,
          size: 56,
        ),
        title: const Text('Reset All Data?'),
        message: const Text(
          'This will permanently delete all files in the vault, clear your master password, recovery key, and reset all settings.\n\nThis action CANNOT be undone.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          color: MacosColors.systemRedColor,
          onPressed: () {
            Navigator.pop(context);
            _showFinalConfirmation(context);
          },
          child: const Text('Reset Everything'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showFinalConfirmation(BuildContext context) {
    showMacosAlertDialog(
      context: context,
      builder: (context) => MacosAlertDialog(
        appIcon: const MacosIcon(
          CupertinoIcons.exclamationmark_shield_fill,
          color: MacosColors.systemRedColor,
          size: 56,
        ),
        title: const Text('Final Confirmation'),
        message: const Text(
          'Are you absolutely sure? Everything will be lost forever.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          color: MacosColors.systemRedColor,
          onPressed: () {
            Navigator.pop(context);
            context.read<AuthBloc>().add(ResetAllRequested());
          },
          child: const Text('I am sure, Reset Now'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}
