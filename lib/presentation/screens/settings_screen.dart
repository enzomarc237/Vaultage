import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../application/blocs/settings_bloc.dart';
import '../../infrastructure/repositories/settings_repository.dart';
import '../../application/services/auto_destruction_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        if (state is SettingsLoading) {
          return const Center(child: ProgressCircle());
        }

        if (state is SettingsLoaded) {
          return MacosSheet(
            child: SizedBox(
              width: 600,
              height: 500,
              child: Column(
                children: [
                  // Tab bar
                  Container(
                    color: MacosColors.controlBackgroundColor,
                    child: Row(
                      children: [
                        _buildTab(0, 'General', CupertinoIcons.gear),
                        _buildTab(1, 'Security', CupertinoIcons.shield),
                        _buildTab(2, 'Destruction', CupertinoIcons.flame),
                        _buildTab(3, 'Backup', CupertinoIcons.archivebox),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  
                  // Content
                  Expanded(
                    child: IndexedStack(
                      index: _selectedTab,
                      children: [
                        _GeneralSettings(settings: state.settings),
                        _SecuritySettings(settings: state.settings),
                        _DestructionSettings(settings: state.settings),
                        _BackupSettings(settings: state.settings),
                      ],
                    ),
                  ),
                  
                  // Footer
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: MacosColors.systemGrayColor.withOpacity(0.2),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        PushButton(
                          controlSize: ControlSize.regular,
                          secondary: true,
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return const Center(child: Text('Failed to load settings'));
      },
    );
  }

  Widget _buildTab(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected
                  ? MacosColors.systemBlueColor
                  : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MacosIcon(
                icon,
                size: 16,
                color: isSelected
                  ? MacosColors.systemBlueColor
                  : MacosColors.secondaryLabelColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                    ? MacosColors.systemBlueColor
                    : MacosColors.labelColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeneralSettings extends StatelessWidget {
  final AppSettings settings;

  const _GeneralSettings({required this.settings, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'General Settings',
            style: MacosTheme.of(context).typography.title2,
          ),
          const SizedBox(height: 24),
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Auto-Lock Timeout: ${settings.autoLockTimeout ~/ 60} minutes'),
              const SizedBox(height: 8),
              MacosSlider(
                value: settings.autoLockTimeout.toDouble(),
                min: 60,
                max: 3600,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(
                    AutoLockTimeoutChanged(timeout: value.round()),
                  );
                },
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              const MacosIcon(CupertinoIcons.square_split_1x2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Show in Menu Bar'),
                    Text(
                      'Display vault status in the system menu bar',
                      style: MacosTheme.of(context).typography.caption1,
                    ),
                  ],
                ),
              ),
              MacosSwitch(
                value: settings.showInMenuBar,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(
                    ShowInMenuBarChanged(enabled: value),
                  );
                },
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          Row(
            children: [
              const MacosIcon(CupertinoIcons.power),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Start at Login'),
                    Text(
                      'Automatically open when you log in',
                      style: MacosTheme.of(context).typography.caption1,
                    ),
                  ],
                ),
              ),
              MacosSwitch(
                value: settings.startAtLogin,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(
                    StartAtLoginChanged(enabled: value),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecuritySettings extends StatelessWidget {
  final AppSettings settings;

  const _SecuritySettings({required this.settings, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security Settings',
            style: MacosTheme.of(context).typography.title2,
          ),
          const SizedBox(height: 24),
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PIN Length: ${settings.pinLength} digits'),
              const SizedBox(height: 8),
              MacosSlider(
                value: settings.pinLength.toDouble(),
                min: 4,
                max: 12,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(
                    PinLengthChanged(length: value.round()),
                  );
                },
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Maximum Login Attempts: ${settings.maxLoginAttempts}'),
              const SizedBox(height: 8),
              MacosSlider(
                value: settings.maxLoginAttempts.toDouble(),
                min: 3,
                max: 20,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(
                    MaxLoginAttemptsChanged(attempts: value.round()),
                  );
                },
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 59, 48, 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color.fromRGBO(255, 59, 48, 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MacosIcon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      color: MacosColors.systemRedColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Danger Zone',
                      style: MacosTheme.of(context).typography.headline.copyWith(
                        color: MacosColors.systemRedColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Wipe After Failed Attempts'),
                          Text(
                            'Irreversibly destroy vault after ${settings.wipeThreshold} failed attempts',
                            style: MacosTheme.of(context).typography.caption1,
                          ),
                        ],
                      ),
                    ),
                    MacosSwitch(
                      value: settings.wipeAfterFailedAttempts,
                      onChanged: (value) {
                        context.read<SettingsBloc>().add(
                          WipeAfterFailedAttemptsChanged(
                            enabled: value,
                            threshold: settings.wipeThreshold,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DestructionSettings extends StatefulWidget {
  final AppSettings settings;

  const _DestructionSettings({required this.settings, Key? key}) : super(key: key);

  @override
  State<_DestructionSettings> createState() => _DestructionSettingsState();
}

class _DestructionSettingsState extends State<_DestructionSettings> {
  final _urlController = TextEditingController();
  final _secretController = TextEditingController();
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.settings.autoDestructionUrl ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MacosIcon(
                CupertinoIcons.flame_fill,
                color: MacosColors.systemOrangeColor,
              ),
              const SizedBox(width: 8),
              Text(
                'Remote Destruction',
                style: MacosTheme.of(context).typography.title2,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure a remote endpoint that can trigger secure vault destruction. '
            'When the endpoint returns a valid signed trigger, all vault data will be crypto-shredded.',
            style: MacosTheme.of(context).typography.body.copyWith(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          
          Row(
            children: [
              const Expanded(
                child: Text('Enable Remote Destruction'),
              ),
              MacosSwitch(
                value: widget.settings.autoDestructionEnabled,
                onChanged: (value) {
                  _saveSettings();
                },
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          if (widget.settings.autoDestructionEnabled) ...[
            MacosTextField(
              controller: _urlController,
              placeholder: 'https://api.example.com/vault/trigger',
              prefix: const MacosIcon(CupertinoIcons.link),
            ),
            
            const SizedBox(height: 16),
            
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Check Interval: ${widget.settings.autoDestructionInterval} minutes'),
                const SizedBox(height: 8),
                MacosSlider(
                  value: widget.settings.autoDestructionInterval.toDouble(),
                  min: 1,
                  max: 60,
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(
                      AutoDestructionConfigured(
                        enabled: true,
                        url: _urlController.text,
                        interval: value.round(),
                        signed: widget.settings.autoDestructionSigned,
                        secret: _secretController.text.isNotEmpty
                          ? _secretController.text
                          : null,
                      ),
                    );
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Require Signed Triggers'),
                      Text(
                        'Use HMAC-SHA256 to verify trigger authenticity',
                        style: MacosTheme.of(context).typography.caption1,
                      ),
                    ],
                  ),
                ),
                MacosSwitch(
                  value: widget.settings.autoDestructionSigned,
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(
                      AutoDestructionConfigured(
                        enabled: widget.settings.autoDestructionEnabled,
                        url: _urlController.text,
                        interval: widget.settings.autoDestructionInterval,
                        signed: value,
                        secret: _secretController.text.isNotEmpty
                          ? _secretController.text
                          : null,
                      ),
                    );
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            if (widget.settings.autoDestructionSigned) ...[
              MacosTextField(
                controller: _secretController,
                placeholder: 'Shared Secret (for HMAC)',
                obscureText: true,
                prefix: const MacosIcon(CupertinoIcons.lock_shield_fill),
              ),
              const SizedBox(height: 8),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: () {
                  final service = context.read<AutoDestructionService>();
                  final secret = service.generateSharedSecret();
                  _secretController.text = secret;
                },
                child: const Text('Generate Secret'),
              ),
            ],
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: _isTesting ? null : _testConnection,
                  child: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressCircle(),
                      )
                    : const Text('Test Connection'),
                ),
                const SizedBox(width: 8),
                PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: _saveSettings,
                  child: const Text('Save Configuration'),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 204, 0, 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color.fromRGBO(255, 204, 0, 0.5),
              ),
            ),
            child: Row(
              children: [
                const MacosIcon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: MacosColors.systemYellowColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Warning: When triggered, your vault will be permanently destroyed. '
                    'This action cannot be undone.',
                    style: MacosTheme.of(context).typography.caption1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    
    final service = context.read<AutoDestructionService>();
    final result = await service.testUrl(_urlController.text);
    
    setState(() => _isTesting = false);
    
    if (mounted) {
      showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: MacosIcon(
            result.reachable
              ? CupertinoIcons.checkmark_circle
              : CupertinoIcons.exclamationmark_circle,
            size: 56,
            color: result.reachable
              ? MacosColors.systemGreenColor
              : MacosColors.systemRedColor,
          ),
          title: Text(result.reachable ? 'Success' : 'Error'),
          message: Text(
            result.reachable
              ? 'Endpoint is reachable. ${result.validResponse ? 'Valid response format.' : 'Warning: ${result.error}'}'
              : 'Failed to connect: ${result.error}',
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ),
      );
    }
  }

  void _saveSettings() {
    context.read<SettingsBloc>().add(
      AutoDestructionConfigured(
        enabled: widget.settings.autoDestructionEnabled,
        url: _urlController.text,
        interval: widget.settings.autoDestructionInterval,
        signed: widget.settings.autoDestructionSigned,
        secret: _secretController.text.isNotEmpty
          ? _secretController.text
          : null,
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _secretController.dispose();
    super.dispose();
  }
}

class _BackupSettings extends StatelessWidget {
  final AppSettings settings;

  const _BackupSettings({required this.settings, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final lastBackup = settings.lastBackupTime != null
      ? DateTime.fromMillisecondsSinceEpoch(settings.lastBackupTime!)
      : null;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Backup & Recovery',
            style: MacosTheme.of(context).typography.title2,
          ),
          const SizedBox(height: 24),
          
          if (lastBackup != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(52, 199, 89, 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const MacosIcon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: MacosColors.systemGreenColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Last backup: ${_formatDate(lastBackup)}',
                    style: MacosTheme.of(context).typography.body,
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 16),
          
          GestureDetector(
            onTap: () {
              // Trigger export
            },
            child: Row(
              children: [
                const MacosIcon(CupertinoIcons.arrow_up_doc),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Export Vault'),
                      Text(
                        'Create an encrypted backup of your vault',
                        style: MacosTheme.of(context).typography.caption1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          GestureDetector(
            onTap: () {
              // Trigger import
            },
            child: Row(
              children: [
                const MacosIcon(CupertinoIcons.arrow_down_doc),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Import Vault'),
                      Text(
                        'Restore from a previous backup',
                        style: MacosTheme.of(context).typography.caption1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          GestureDetector(
            onTap: () {
              // Show recovery key
            },
            child: Row(
              children: [
                const MacosIcon(CupertinoIcons.lock_shield_fill),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Show Recovery Key'),
                      Text(
                        'Display your 12-word recovery phrase',
                        style: MacosTheme.of(context).typography.caption1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 122, 255, 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MacosIcon(
                  CupertinoIcons.info_circle,
                  color: MacosColors.systemBlueColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your vault backup contains encrypted files. You will need your '
                    'recovery key to restore the backup on a new device.',
                    style: MacosTheme.of(context).typography.caption1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
