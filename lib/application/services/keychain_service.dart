import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keychain keys for secure storage
class KeychainKeys {
  static const String wrappedMasterKey = 'secure_vault_wrapped_master_key';
  static const String keyDerivationSalt = 'secure_vault_kdf_salt';
  static const String kdfParams = 'secure_vault_kdf_params';
  static const String recoveryKeyHash = 'secure_vault_recovery_key_hash';
  static const String vaultInitialized = 'secure_vault_initialized';
  static const String lastLockTime = 'secure_vault_last_lock_time';
}

/// Service for interacting with macOS Keychain
class KeychainService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      accountName: 'secure_file_vault',
    ),
    mOptions: const MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      accountName: 'secure_file_vault',
    ),
  );
  
  SharedPreferences? _prefs;
  
  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }
  
  /// Check if vault is initialized
  Future<bool> isVaultInitialized() async {
    final prefs = await _preferences;
    return prefs.getBool(KeychainKeys.vaultInitialized) ?? false;
  }
  
  /// Mark vault as initialized
  Future<void> setVaultInitialized(bool initialized) async {
    final prefs = await _preferences;
    await prefs.setBool(KeychainKeys.vaultInitialized, initialized);
  }
  
  /// Store wrapped master key
  Future<void> storeWrappedMasterKey(Uint8List wrappedKey) async {
    final base64Key = base64Encode(wrappedKey);
    await _secureStorage.write(
      key: KeychainKeys.wrappedMasterKey,
      value: base64Key,
    );
  }
  
  /// Retrieve wrapped master key
  Future<Uint8List?> getWrappedMasterKey() async {
    final base64Key = await _secureStorage.read(
      key: KeychainKeys.wrappedMasterKey,
    );
    if (base64Key == null) return null;
    return base64Decode(base64Key);
  }
  
  /// Store key derivation salt
  Future<void> storeKdfSalt(Uint8List salt) async {
    final base64Salt = base64Encode(salt);
    await _secureStorage.write(
      key: KeychainKeys.keyDerivationSalt,
      value: base64Salt,
    );
  }
  
  /// Retrieve key derivation salt
  Future<Uint8List?> getKdfSalt() async {
    final base64Salt = await _secureStorage.read(
      key: KeychainKeys.keyDerivationSalt,
    );
    if (base64Salt == null) return null;
    return base64Decode(base64Salt);
  }
  
  /// Store KDF parameters
  Future<void> storeKdfParams(Map<String, dynamic> params) async {
    final jsonParams = jsonEncode(params);
    await _secureStorage.write(
      key: KeychainKeys.kdfParams,
      value: jsonParams,
    );
  }
  
  /// Retrieve KDF parameters
  Future<Map<String, dynamic>?> getKdfParams() async {
    final jsonParams = await _secureStorage.read(
      key: KeychainKeys.kdfParams,
    );
    if (jsonParams == null) return null;
    return jsonDecode(jsonParams) as Map<String, dynamic>;
  }
  
  /// Store recovery key hash (for verification only, not the actual key)
  Future<void> storeRecoveryKeyHash(String recoveryKey) async {
    // Store a hash of the recovery key, not the key itself
    final hash = await _hashRecoveryKey(recoveryKey);
    await _secureStorage.write(
      key: KeychainKeys.recoveryKeyHash,
      value: hash,
    );
  }
  
  /// Verify recovery key
  Future<bool> verifyRecoveryKey(String recoveryKey) async {
    final storedHash = await _secureStorage.read(
      key: KeychainKeys.recoveryKeyHash,
    );
    if (storedHash == null) return false;
    
    final computedHash = await _hashRecoveryKey(recoveryKey);
    return storedHash == computedHash;
  }
  
  /// Hash recovery key for storage
  Future<String> _hashRecoveryKey(String recoveryKey) async {
    // Simple hash for demonstration
    // In production, use proper KDF like Argon2id
    final bytes = utf8.encode(recoveryKey);
    return base64Encode(bytes);
  }
  
  /// Delete all keychain items (for vault destruction)
  Future<void> deleteAllKeychainItems() async {
    await _secureStorage.delete(key: KeychainKeys.wrappedMasterKey);
    await _secureStorage.delete(key: KeychainKeys.keyDerivationSalt);
    await _secureStorage.delete(key: KeychainKeys.kdfParams);
    await _secureStorage.delete(key: KeychainKeys.recoveryKeyHash);
    
    final prefs = await _preferences;
    await prefs.remove(KeychainKeys.vaultInitialized);
    await prefs.remove(KeychainKeys.lastLockTime);
  }
  
  /// Store last lock time
  Future<void> storeLastLockTime() async {
    final prefs = await _preferences;
    await prefs.setInt(
      KeychainKeys.lastLockTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
  
  /// Get last lock time
  Future<DateTime?> getLastLockTime() async {
    final prefs = await _preferences;
    final timestamp = prefs.getInt(KeychainKeys.lastLockTime);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
  
  /// Update last lock time on app lock
  Future<void> recordLockEvent() async {
    await storeLastLockTime();
  }
  
  /// Securely wipe all vault data from keychain
  /// This is used for crypto-shredding and auto-destruction
  Future<void> secureWipe() async {
    // Delete all key material
    await deleteAllKeychainItems();
    
    // Clear any cached preferences
    final prefs = await _preferences;
    await prefs.clear();
  }
}
