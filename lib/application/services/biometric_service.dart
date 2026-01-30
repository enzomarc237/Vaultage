import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

/// Service for biometric authentication (Touch ID / Face ID)
class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      accountName: 'secure_file_vault_biometric',
    ),
  );

  static const String _biometricKeyStorage = 'biometric_wrapped_key';
  static const String _biometricEnabledKey = 'biometric_enabled';

  /// Check if biometric authentication is available on this device
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get list of available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Check if biometric unlock is enabled
  Future<bool> isBiometricEnabled() async {
    final prefs = await _secureStorage.read(key: _biometricEnabledKey);
    return prefs == 'true';
  }

  /// Enable biometric authentication
  /// Stores a special key that can only be accessed after biometric auth
  Future<void> enableBiometric(Uint8List wrappedMasterKey) async {
    // Store the wrapped key with biometric protection
    await _secureStorage.write(
      key: _biometricKeyStorage,
      value: String.fromCharCodes(wrappedMasterKey),
    );
    await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
  }

  /// Disable biometric authentication
  Future<void> disableBiometric() async {
    await _secureStorage.delete(key: _biometricKeyStorage);
    await _secureStorage.write(key: _biometricEnabledKey, value: 'false');
  }

  /// Authenticate with biometrics and retrieve the wrapped master key
  Future<BiometricAuthResult> authenticateWithBiometrics() async {
    if (!await isBiometricEnabled()) {
      return BiometricAuthResult.notEnabled();
    }

    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Unlock Secure File Vault',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );

      if (didAuthenticate) {
        // Retrieve the key from secure storage
        final keyString = await _secureStorage.read(key: _biometricKeyStorage);
        if (keyString != null) {
          final keyBytes = Uint8List.fromList(keyString.codeUnits);
          return BiometricAuthResult.success(keyBytes);
        } else {
          return BiometricAuthResult.error('Biometric key not found');
        }
      } else {
        return BiometricAuthResult.cancelled();
      }
    } on PlatformException catch (e) {
      if (e.code == auth_error.notAvailable) {
        return BiometricAuthResult.error('Biometric authentication not available');
      } else if (e.code == auth_error.notEnrolled) {
        return BiometricAuthResult.error('No biometrics enrolled on this device');
      } else if (e.code == auth_error.lockedOut) {
        return BiometricAuthResult.error('Too many failed attempts. Biometric authentication locked.');
      } else if (e.code == auth_error.permanentlyLockedOut) {
        return BiometricAuthResult.error('Biometric authentication permanently locked. Please use PIN.');
      }
      return BiometricAuthResult.error('Biometric error: ${e.message}');
    } catch (e) {
      return BiometricAuthResult.error('Unexpected error: $e');
    }
  }
}

/// Result of biometric authentication
class BiometricAuthResult {
  final bool success;
  final Uint8List? wrappedMasterKey;
  final String? errorMessage;
  final bool cancelled;
  final bool notEnabled;

  BiometricAuthResult._({
    required this.success,
    this.wrappedMasterKey,
    this.errorMessage,
    this.cancelled = false,
    this.notEnabled = false,
  });

  factory BiometricAuthResult.success(Uint8List key) =>
      BiometricAuthResult._(success: true, wrappedMasterKey: key);

  factory BiometricAuthResult.cancelled() =>
      BiometricAuthResult._(success: false, cancelled: true);

  factory BiometricAuthResult.notEnabled() =>
      BiometricAuthResult._(success: false, notEnabled: true);

  factory BiometricAuthResult.error(String message) =>
      BiometricAuthResult._(success: false, errorMessage: message);
}
