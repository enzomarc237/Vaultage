import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'application/blocs/blocs.dart';
import 'application/services/services.dart';
import 'infrastructure/repositories/repositories.dart';
import 'presentation/screens/screens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize window manager
  await windowManager.ensureInitialized();
  
  // Configure macOS window for modern translucent look
  await _configureMacOSWindow();
  
  // Configure window options
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    title: 'Secure File Vault',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  // Initialize tray
  await trayManager.setIcon('assets/tray_icon.png');
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  runApp(const SecureFileVaultApp());
}

/// This method initializes macos_window_utils and styles the window.
Future<void> _configureMacOSWindow() async {
  if (!Platform.isMacOS) return;
  
  // Configure macOS window for modern translucent look
  const config = MacosWindowUtilsConfig(
    toolbarStyle: NSWindowToolbarStyle.unified,
  );
  await config.apply();
}

class SecureFileVaultApp extends StatelessWidget {
  const SecureFileVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => KeychainService()),
        RepositoryProvider(create: (_) => CryptoService()),
        RepositoryProvider(create: (_) => FileRepository()),
        RepositoryProvider(create: (_) => SettingsRepository()),
        RepositoryProvider(
          create: (context) => AutoDestructionService(
            settingsRepository: context.read<SettingsRepository>(),
            fileRepository: context.read<FileRepository>(),
            keychainService: context.read<KeychainService>(),
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(
              keychainService: context.read<KeychainService>(),
              cryptoService: context.read<CryptoService>(),
            )..add(AuthCheckRequested()),
          ),
          BlocProvider(
            create: (context) => VaultBloc(
              fileRepository: context.read<FileRepository>(),
              cryptoService: context.read<CryptoService>(),
              keychainService: context.read<KeychainService>(),
            ),
          ),
          BlocProvider(
            create: (context) => SettingsBloc(
              settingsRepository: context.read<SettingsRepository>(),
              autoDestructionService: context.read<AutoDestructionService>(),
            )..add(SettingsLoadRequested()),
          ),
        ],
        child: const MacosApp(
          title: 'Secure File Vault',
          themeMode: ThemeMode.system,
          home: AppWindow(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}

class AppWindow extends StatefulWidget {
  const AppWindow({super.key});

  @override
  State<AppWindow> createState() => _AppWindowState();
}

class _AppWindowState extends State<AppWindow> with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initTray();
  }

  Future<void> _initTray() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'show',
            label: 'Show Secure Vault',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'lock',
            label: 'Lock Vault',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit',
            label: 'Quit',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowBlur() {
    // Auto-lock on unfocus based on settings
    context.read<AuthBloc>().add(AppUnfocused());
  }

  @override
  void onWindowFocus() {
    context.read<AuthBloc>().add(AppFocused());
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'lock':
        context.read<AuthBloc>().add(LockRequested());
        break;
      case 'quit':
        windowManager.close();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthFailure) {
          showMacosAlertDialog(
            context: context,
            builder: (_) => MacosAlertDialog(
              appIcon: const MacosIcon(
                CupertinoIcons.exclamationmark_triangle,
                size: 56,
              ),
              title: const Text('Authentication Error'),
              message: Text(state.message),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          );
        }
      },
      builder: (context, state) {
        return MacosWindow(
          disableWallpaperTinting: false,
          titleBar: TitleBar(
            title: const Text('Secure File Vault'),
          ),
          sidebar: _buildSidebar(context, state),
          child: _buildContent(state),
        );
      },
    );
  }

  Widget _buildWindowActions(BuildContext context, AuthState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state is AuthAuthenticated) ...[
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.lock),
            onPressed: () => context.read<AuthBloc>().add(LockRequested()),
          ),
          const SizedBox(width: 8),
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.plus),
            onPressed: () => context.read<VaultBloc>().add(AddFilesRequested()),
          ),
          const SizedBox(width: 8),
        ],
        MacosIconButton(
          icon: const MacosIcon(CupertinoIcons.gear),
          onPressed: () => _showSettings(context),
        ),
      ],
    );
  }

  Sidebar _buildSidebar(BuildContext context, AuthState state) {
    final isAuthenticated = state is AuthAuthenticated;
    
    return Sidebar(
      minWidth: 200,
      maxWidth: 300,
      startWidth: 250,
      builder: (context, scrollController) {
        return SidebarItems(
          currentIndex: 0,
          onChanged: (index) {},
          scrollController: scrollController,
          itemSize: SidebarItemSize.large,
          items: [
            SidebarItem(
              leading: MacosIcon(
                isAuthenticated 
                  ? CupertinoIcons.lock_open_fill 
                  : CupertinoIcons.lock_fill,
                color: isAuthenticated 
                  ? MacosColors.systemGreenColor 
                  : MacosColors.systemRedColor,
              ),
              label: Text(isAuthenticated ? 'Vault Unlocked' : 'Vault Locked'),
            ),
            if (isAuthenticated)
              const SidebarItem(
                leading: MacosIcon(CupertinoIcons.folder_fill),
                label: Text('All Files'),
              ),
            const SidebarItem(
              leading: MacosIcon(CupertinoIcons.settings),
              label: Text('Settings'),
            ),
          ],
        );
      },
      bottom: isAuthenticated
        ? Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const MacosIcon(
                  CupertinoIcons.checkmark_shield_fill,
                  color: MacosColors.systemGreenColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Protected by AES-256',
                    style: MacosTheme.of(context).typography.caption1.copyWith(
                      color: MacosColors.systemGreenColor,
                    ),
                  ),
                ),
              ],
            ),
          )
        : null,
    );
  }

  Widget _buildContent(AuthState state) {
    if (state is AuthInitial || state is AuthLoading) {
      return const Center(
        child: ProgressCircle(),
      );
    }

    if (state is AuthNeedsSetup) {
      return SetupScreen(onComplete: (pin) {
        context.read<AuthBloc>().add(SetupCompleted(pin: pin));
      });
    }

    if (state is AuthLocked || state is AuthFailure) {
      return LockScreen(
        attemptsRemaining: state is AuthLocked ? state.attemptsRemaining : 10,
        lockoutDuration: state is AuthLocked ? state.lockoutDuration : null,
        onUnlock: (pin) {
          context.read<AuthBloc>().add(UnlockRequested(pin: pin));
        },
      );
    }

    if (state is AuthAuthenticated) {
      return const VaultScreen();
    }

    return const Center(
      child: Text('Unknown state'),
    );
  }

  void _showSettings(BuildContext context) {
    showMacosSheet(
      context: context,
      barrierDismissible: true,
      builder: (_) => BlocProvider.value(
        value: context.read<SettingsBloc>(),
        child: const SettingsScreen(),
      ),
    );
  }
}

class SetupScreen extends StatefulWidget {
  final Function(String) onComplete;

  const SetupScreen({super.key, required this.onComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  int _pinLength = 6;
  bool _isCreating = true;

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const MacosIcon(
                      CupertinoIcons.shield_fill,
                      size: 64,
                      color: MacosColors.systemBlueColor,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome to Secure File Vault',
                      style: MacosTheme.of(context).typography.title1,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a PIN to protect your encrypted vault. This PIN will be used to unlock your files.',
                      style: MacosTheme.of(context).typography.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (_isCreating) ...[
                      _buildPinSetup(),
                    ] else ...[
                      _buildRecoveryKey(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPinSetup() {
    return Column(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PIN Length: $_pinLength digits'),
            const SizedBox(height: 8),
            MacosSlider(
              value: _pinLength.toDouble(),
              min: 4,
              max: 12,
              onChanged: (value) {
                setState(() {
                  _pinLength = value.round();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        MacosTextField(
          controller: _pinController,
          placeholder: 'Enter PIN',
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: _pinLength,
          prefix: const MacosIcon(CupertinoIcons.lock),
        ),
        const SizedBox(height: 12),
        MacosTextField(
          controller: _confirmPinController,
          placeholder: 'Confirm PIN',
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: _pinLength,
          prefix: const MacosIcon(CupertinoIcons.lock),
        ),
        const SizedBox(height: 24),
        PushButton(
          controlSize: ControlSize.large,
          onPressed: _validateAndProceed,
          child: const Text('Create Vault'),
        ),
      ],
    );
  }

  Widget _buildRecoveryKey() {
    // Generate recovery key (in real implementation, this would be cryptographically secure)
    final recoveryKey = 'apple lumber crystal brave ocean dentist flower magic seven captain bridge';
    
    return Column(
      children: [
        const MacosIcon(
          CupertinoIcons.exclamationmark_triangle_fill,
          size: 48,
          color: MacosColors.systemOrangeColor,
        ),
        const SizedBox(height: 16),
        Text(
          'Save Your Recovery Key',
          style: MacosTheme.of(context).typography.title2,
        ),
        const SizedBox(height: 8),
        Text(
          'This is the ONLY way to recover your vault if you forget your PIN. Store it securely offline.',
          style: MacosTheme.of(context).typography.body,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MacosColors.systemGrayColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: MacosColors.systemOrangeColor.withOpacity(0.5),
            ),
          ),
          child: Text(
            recoveryKey,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PushButton(
              controlSize: ControlSize.regular,
              secondary: true,
              onPressed: () {
                // Copy to clipboard
              },
              child: const Text('Copy'),
            ),
            const SizedBox(width: 12),
            PushButton(
              controlSize: ControlSize.regular,
              onPressed: () {
                widget.onComplete(_pinController.text);
              },
              child: const Text('I\'ve Saved It'),
            ),
          ],
        ),
      ],
    );
  }

  void _validateAndProceed() {
    if (_pinController.text.length < _pinLength) {
      _showError('PIN must be $_pinLength digits');
      return;
    }
    if (_pinController.text != _confirmPinController.text) {
      _showError('PINs do not match');
      return;
    }
    setState(() {
      _isCreating = false;
    });
  }

  void _showError(String message) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(
          CupertinoIcons.exclamationmark_circle,
          size: 56,
        ),
        title: const Text('Error'),
        message: Text(message),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }
}
