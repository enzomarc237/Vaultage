import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../infrastructure/repositories/settings_repository.dart';
import '../services/auto_destruction_service.dart';

// Events
abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class SettingsLoadRequested extends SettingsEvent {}

class SettingsUpdated extends SettingsEvent {
  final AppSettings settings;

  const SettingsUpdated({required this.settings});

  @override
  List<Object?> get props => [settings];
}

class AutoLockTimeoutChanged extends SettingsEvent {
  final int timeout;

  const AutoLockTimeoutChanged({required this.timeout});

  @override
  List<Object?> get props => [timeout];
}

class MaxLoginAttemptsChanged extends SettingsEvent {
  final int attempts;

  const MaxLoginAttemptsChanged({required this.attempts});

  @override
  List<Object?> get props => [attempts];
}

class WipeAfterFailedAttemptsChanged extends SettingsEvent {
  final bool enabled;
  final int threshold;

  const WipeAfterFailedAttemptsChanged({
    required this.enabled,
    required this.threshold,
  });

  @override
  List<Object?> get props => [enabled, threshold];
}

class AutoDestructionConfigured extends SettingsEvent {
  final bool enabled;
  final String? url;
  final int interval;
  final bool signed;
  final String? secret;

  const AutoDestructionConfigured({
    required this.enabled,
    this.url,
    required this.interval,
    required this.signed,
    this.secret,
  });

  @override
  List<Object?> get props => [enabled, url, interval, signed, secret];
}

class BiometricUnlockChanged extends SettingsEvent {
  final bool enabled;

  const BiometricUnlockChanged({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

class StartAtLoginChanged extends SettingsEvent {
  final bool enabled;

  const StartAtLoginChanged({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

class ShowInMenuBarChanged extends SettingsEvent {
  final bool enabled;

  const ShowInMenuBarChanged({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

class VaultLocationChanged extends SettingsEvent {
  final String location;

  const VaultLocationChanged({required this.location});

  @override
  List<Object?> get props => [location];
}

class PinLengthChanged extends SettingsEvent {
  final int length;

  const PinLengthChanged({required this.length});

  @override
  List<Object?> get props => [length];
}

class BackupCreated extends SettingsEvent {
  final String path;

  const BackupCreated({required this.path});

  @override
  List<Object?> get props => [path];
}

class SettingsResetRequested extends SettingsEvent {}

// States
abstract class SettingsState extends Equatable {
  const SettingsState();

  @override
  List<Object?> get props => [];
}

class SettingsInitial extends SettingsState {}

class SettingsLoading extends SettingsState {}

class SettingsLoaded extends SettingsState {
  final AppSettings settings;
  final bool hasUnsavedChanges;

  const SettingsLoaded({
    required this.settings,
    this.hasUnsavedChanges = false,
  });

  @override
  List<Object?> get props => [settings, hasUnsavedChanges];

  SettingsLoaded copyWith({
    AppSettings? settings,
    bool? hasUnsavedChanges,
  }) {
    return SettingsLoaded(
      settings: settings ?? this.settings,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }
}

class SettingsSaved extends SettingsState {
  final AppSettings settings;

  const SettingsSaved({required this.settings});

  @override
  List<Object?> get props => [settings];
}

class SettingsError extends SettingsState {
  final String message;

  const SettingsError({required this.message});

  @override
  List<Object?> get props => [message];
}

class AutoDestructionStatusChanged extends SettingsState {
  final bool isActive;
  final DateTime? lastCheck;
  final String? status;

  const AutoDestructionStatusChanged({
    required this.isActive,
    this.lastCheck,
    this.status,
  });

  @override
  List<Object?> get props => [isActive, lastCheck, status];
}

class BackupInProgress extends SettingsState {}

class BackupCompleted extends SettingsState {
  final String path;

  const BackupCompleted({required this.path});

  @override
  List<Object?> get props => [path];
}

// BLoC
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository _settingsRepository;
  final AutoDestructionService _autoDestructionService;

  SettingsBloc({
    required SettingsRepository settingsRepository,
    required AutoDestructionService autoDestructionService,
  }) : _settingsRepository = settingsRepository,
       _autoDestructionService = autoDestructionService,
       super(SettingsInitial()) {
    on<SettingsLoadRequested>(_onSettingsLoadRequested);
    on<SettingsUpdated>(_onSettingsUpdated);
    on<AutoLockTimeoutChanged>(_onAutoLockTimeoutChanged);
    on<MaxLoginAttemptsChanged>(_onMaxLoginAttemptsChanged);
    on<WipeAfterFailedAttemptsChanged>(_onWipeAfterFailedAttemptsChanged);
    on<AutoDestructionConfigured>(_onAutoDestructionConfigured);
    on<BiometricUnlockChanged>(_onBiometricUnlockChanged);
    on<StartAtLoginChanged>(_onStartAtLoginChanged);
    on<ShowInMenuBarChanged>(_onShowInMenuBarChanged);
    on<VaultLocationChanged>(_onVaultLocationChanged);
    on<PinLengthChanged>(_onPinLengthChanged);
    on<BackupCreated>(_onBackupCreated);
    on<SettingsResetRequested>(_onSettingsResetRequested);
  }

  Future<void> _onSettingsLoadRequested(
    SettingsLoadRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    
    try {
      final settings = await _settingsRepository.loadSettings();
      emit(SettingsLoaded(settings: settings));
      
      // Initialize auto-destruction if enabled
      if (settings.autoDestructionEnabled && settings.autoDestructionUrl != null) {
        await _autoDestructionService.startMonitoring(
          url: settings.autoDestructionUrl!,
          interval: Duration(minutes: settings.autoDestructionInterval),
          useSignedTriggers: settings.autoDestructionSigned,
        );
      }
    } catch (e) {
      emit(SettingsError(message: 'Failed to load settings: $e'));
    }
  }

  Future<void> _onSettingsUpdated(
    SettingsUpdated event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _settingsRepository.saveSettings(event.settings);
      emit(SettingsSaved(settings: event.settings));
      emit(SettingsLoaded(settings: event.settings));
    } catch (e) {
      emit(SettingsError(message: 'Failed to save settings: $e'));
    }
  }

  Future<void> _onAutoLockTimeoutChanged(
    AutoLockTimeoutChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        autoLockTimeout: event.timeout,
      );
      await _updateSettings(newSettings, emit);
    }
  }

  Future<void> _onMaxLoginAttemptsChanged(
    MaxLoginAttemptsChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        maxLoginAttempts: event.attempts,
      );
      await _updateSettings(newSettings, emit);
    }
  }

  Future<void> _onWipeAfterFailedAttemptsChanged(
    WipeAfterFailedAttemptsChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        wipeAfterFailedAttempts: event.enabled,
        wipeThreshold: event.threshold,
      );
      await _updateSettings(newSettings, emit);
    }
  }

  Future<void> _onAutoDestructionConfigured(
    AutoDestructionConfigured event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        autoDestructionEnabled: event.enabled,
        autoDestructionUrl: event.url,
        autoDestructionInterval: event.interval,
        autoDestructionSigned: event.signed,
      );
      
      // Save secret separately
      if (event.secret != null) {
        await _settingsRepository.saveAutoDestructionSecret(event.secret!);
      }
      
      await _updateSettings(newSettings, emit);
      
      // Start or stop auto-destruction monitoring
      if (event.enabled && event.url != null) {
        await _autoDestructionService.startMonitoring(
          url: event.url!,
          interval: Duration(minutes: event.interval),
          useSignedTriggers: event.signed,
        );
      } else {
        await _autoDestructionService.stopMonitoring();
      }
    }
  }

  Future<void> _onBiometricUnlockChanged(
    BiometricUnlockChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        biometricUnlockEnabled: event.enabled,
      );
      await _updateSettings(newSettings, emit);
    }
  }

  Future<void> _onStartAtLoginChanged(
    StartAtLoginChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        startAtLogin: event.enabled,
      );
      await _updateSettings(newSettings, emit);
      
      // Configure start at login
      // This would use SMLoginItemSetEnabled on macOS
    }
  }

  Future<void> _onShowInMenuBarChanged(
    ShowInMenuBarChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        showInMenuBar: event.enabled,
      );
      await _updateSettings(newSettings, emit);
    }
  }

  Future<void> _onVaultLocationChanged(
    VaultLocationChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        vaultLocation: event.location,
      );
      await _updateSettings(newSettings, emit);
    }
  }

  Future<void> _onPinLengthChanged(
    PinLengthChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (state is SettingsLoaded) {
      final currentState = state as SettingsLoaded;
      final newSettings = currentState.settings.copyWith(
        pinLength: event.length,
      );
      await _updateSettings(newSettings, emit);
    }
  }

  Future<void> _onBackupCreated(
    BackupCreated event,
    Emitter<SettingsState> emit,
  ) async {
    emit(BackupInProgress());
    
    try {
      // Update last backup time
      if (state is SettingsLoaded) {
        final currentState = state as SettingsLoaded;
        final newSettings = currentState.settings.copyWith(
          lastBackupTime: DateTime.now().millisecondsSinceEpoch,
        );
        await _settingsRepository.saveSettings(newSettings);
        emit(SettingsLoaded(settings: newSettings));
      }
      
      emit(BackupCompleted(path: event.path));
    } catch (e) {
      emit(SettingsError(message: 'Backup failed: $e'));
    }
  }

  Future<void> _onSettingsResetRequested(
    SettingsResetRequested event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _settingsRepository.resetToDefaults();
      final settings = await _settingsRepository.loadSettings();
      emit(SettingsLoaded(settings: settings));
    } catch (e) {
      emit(SettingsError(message: 'Failed to reset settings: $e'));
    }
  }

  Future<void> _updateSettings(
    AppSettings settings,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _settingsRepository.saveSettings(settings);
      emit(SettingsSaved(settings: settings));
      emit(SettingsLoaded(settings: settings));
    } catch (e) {
      emit(SettingsError(message: 'Failed to save settings: $e'));
    }
  }
}
