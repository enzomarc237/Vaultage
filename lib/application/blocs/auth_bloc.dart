import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/crypto_service.dart';
import '../services/keychain_service.dart';

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class UnlockRequested extends AuthEvent {
  final String pin;

  const UnlockRequested({required this.pin});

  @override
  List<Object?> get props => [pin];
}

class LockRequested extends AuthEvent {}

class SetupCompleted extends AuthEvent {
  final String pin;
  final String recoveryKey;

  const SetupCompleted({required this.pin, required this.recoveryKey});

  @override
  List<Object?> get props => [pin, recoveryKey];
}

class AppUnfocused extends AuthEvent {}

class AppFocused extends AuthEvent {}

class RecoveryKeySubmitted extends AuthEvent {
  final String recoveryKey;

  const RecoveryKeySubmitted({required this.recoveryKey});

  @override
  List<Object?> get props => [recoveryKey];
}

class PinChanged extends AuthEvent {
  final String currentPin;
  final String newPin;

  const PinChanged({required this.currentPin, required this.newPin});

  @override
  List<Object?> get props => [currentPin, newPin];
}

// States
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthNeedsSetup extends AuthState {}

class AuthLocked extends AuthState {
  final int attemptsRemaining;
  final Duration? lockoutDuration;
  final DateTime? lockoutEndTime;

  const AuthLocked({
    this.attemptsRemaining = 10,
    this.lockoutDuration,
    this.lockoutEndTime,
  });

  @override
  List<Object?> get props => [attemptsRemaining, lockoutDuration, lockoutEndTime];
}

class AuthAuthenticated extends AuthState {
  final DateTime authenticatedAt;

  const AuthAuthenticated({required this.authenticatedAt});

  @override
  List<Object?> get props => [authenticatedAt];
}

class AuthFailure extends AuthState {
  final String message;

  const AuthFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

class AuthLockout extends AuthState {
  final Duration remainingDuration;
  final int totalAttempts;

  const AuthLockout({
    required this.remainingDuration,
    required this.totalAttempts,
  });

  @override
  List<Object?> get props => [remainingDuration, totalAttempts];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final KeychainService _keychainService;
  final CryptoService _cryptoService;
  
  // Rate limiting state
  int _failedAttempts = 0;
  DateTime? _lockoutEndTime;
  static const int maxAttempts = 10;
  static const Duration initialLockoutDuration = Duration(seconds: 30);
  
  AuthBloc({
    required KeychainService keychainService,
    required CryptoService cryptoService,
  }) : _keychainService = keychainService,
       _cryptoService = cryptoService,
       super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<UnlockRequested>(_onUnlockRequested);
    on<LockRequested>(_onLockRequested);
    on<SetupCompleted>(_onSetupCompleted);
    on<AppUnfocused>(_onAppUnfocused);
    on<AppFocused>(_onAppFocused);
    on<RecoveryKeySubmitted>(_onRecoveryKeySubmitted);
    on<PinChanged>(_onPinChanged);
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    final isInitialized = await _keychainService.isVaultInitialized();
    
    if (!isInitialized) {
      emit(AuthNeedsSetup());
      return;
    }
    
    emit(const AuthLocked(attemptsRemaining: maxAttempts));
  }

  Future<void> _onUnlockRequested(
    UnlockRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Check if currently in lockout
    if (_lockoutEndTime != null && DateTime.now().isBefore(_lockoutEndTime!)) {
      final remaining = _lockoutEndTime!.difference(DateTime.now());
      emit(AuthLockout(
        remainingDuration: remaining,
        totalAttempts: _failedAttempts,
      ));
      return;
    }
    
    emit(AuthLoading());
    
    try {
      final wrappedKey = await _keychainService.getWrappedMasterKey();
      final salt = await _keychainService.getKdfSalt();
      
      if (wrappedKey == null || salt == null) {
        emit(const AuthFailure(message: 'Vault not properly initialized'));
        emit(const AuthLocked(attemptsRemaining: maxAttempts));
        return;
      }
      
      final unlocked = await _cryptoService.unlockWithPin(
        event.pin,
        wrappedKey,
        salt,
      );
      
      if (unlocked) {
        // Reset failed attempts on successful unlock
        _failedAttempts = 0;
        _lockoutEndTime = null;
        
        await _keychainService.recordLockEvent();
        emit(AuthAuthenticated(authenticatedAt: DateTime.now()));
      } else {
        _failedAttempts++;
        final remainingAttempts = maxAttempts - _failedAttempts;
        
        if (remainingAttempts <= 0) {
          // Calculate exponential backoff
          final lockoutMultiplier = _failedAttempts - maxAttempts + 1;
          final lockoutDuration = Duration(
            seconds: initialLockoutDuration.inSeconds * (1 << lockoutMultiplier),
          );
          _lockoutEndTime = DateTime.now().add(lockoutDuration);
          
          emit(AuthLockout(
            remainingDuration: lockoutDuration,
            totalAttempts: _failedAttempts,
          ));
        } else {
          emit(const AuthFailure(message: 'Incorrect PIN'));
          emit(AuthLocked(
            attemptsRemaining: remainingAttempts,
            lockoutDuration: _calculateBackoffDuration(),
          ));
        }
      }
    } catch (e) {
      emit(AuthFailure(message: 'Authentication error: $e'));
      emit(const AuthLocked(attemptsRemaining: maxAttempts));
    }
  }

  Future<void> _onLockRequested(
    LockRequested event,
    Emitter<AuthState> emit,
  ) async {
    _cryptoService.lock();
    await _keychainService.recordLockEvent();
    emit(const AuthLocked(attemptsRemaining: maxAttempts));
  }

  Future<void> _onSetupCompleted(
    SetupCompleted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final result = await _cryptoService.initializeWithPin(
        event.pin,
        recoveryKey: event.recoveryKey,
      );
      
      // Store keys in keychain
      await _keychainService.storeWrappedMasterKey(result.wrappedMasterKey);
      await _keychainService.storeKdfSalt(result.salt);
      await _keychainService.storeKdfParams(result.params);
      await _keychainService.storeRecoveryKeyHash(result.recoveryKey);
      await _keychainService.setVaultInitialized(true);
      
      emit(AuthAuthenticated(authenticatedAt: DateTime.now()));
    } catch (e) {
      emit(AuthFailure(message: 'Setup failed: $e'));
      emit(AuthNeedsSetup());
    }
  }

  Future<void> _onAppUnfocused(
    AppUnfocused event,
    Emitter<AuthState> emit,
  ) async {
    // Auto-lock on unfocus (configurable in settings)
    if (state is AuthAuthenticated) {
      // For now, immediately lock on unfocus
      // In production, this would check settings for grace period
      _cryptoService.lock();
      await _keychainService.recordLockEvent();
      emit(const AuthLocked(attemptsRemaining: maxAttempts));
    }
  }

  Future<void> _onAppFocused(
    AppFocused event,
    Emitter<AuthState> emit,
  ) async {
    // Could add grace period logic here
  }

  Future<void> _onRecoveryKeySubmitted(
    RecoveryKeySubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    final isValid = await _keychainService.verifyRecoveryKey(event.recoveryKey);
    
    if (isValid) {
      // Recovery successful - user needs to set new PIN
      // For now, just authenticate them
      emit(AuthAuthenticated(authenticatedAt: DateTime.now()));
    } else {
      emit(const AuthFailure(message: 'Invalid recovery key'));
      emit(const AuthLocked(attemptsRemaining: maxAttempts));
    }
  }

  Future<void> _onPinChanged(
    PinChanged event,
    Emitter<AuthState> emit,
  ) async {
    if (state is! AuthAuthenticated) {
      emit(const AuthFailure(message: 'Must be authenticated to change PIN'));
      return;
    }
    
    emit(AuthLoading());
    
    try {
      final currentWrappedKey = await _keychainService.getWrappedMasterKey();
      final currentSalt = await _keychainService.getKdfSalt();
      
      if (currentWrappedKey == null || currentSalt == null) {
        emit(const AuthFailure(message: 'Vault keys not found'));
        emit(AuthAuthenticated(authenticatedAt: DateTime.now()));
        return;
      }
      
      final result = await _cryptoService.changePin(
        event.currentPin,
        event.newPin,
        currentWrappedKey,
        currentSalt,
      );
      
      await _keychainService.storeWrappedMasterKey(result.wrappedMasterKey);
      await _keychainService.storeKdfSalt(result.salt);
      await _keychainService.storeKdfParams(result.params);
      
      emit(AuthAuthenticated(authenticatedAt: DateTime.now()));
    } catch (e) {
      emit(AuthFailure(message: 'Failed to change PIN: $e'));
      emit(AuthAuthenticated(authenticatedAt: DateTime.now()));
    }
  }

  Duration? _calculateBackoffDuration() {
    if (_failedAttempts < 5) return null;
    
    final lockoutMultiplier = _failedAttempts - 4;
    return Duration(
      seconds: initialLockoutDuration.inSeconds * (1 << lockoutMultiplier),
    );
  }

  @override
  Future<void> close() {
    _cryptoService.lock();
    return super.close();
  }
}
