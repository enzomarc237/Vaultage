import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Settings keys
class SettingsKeys {
  static const String vaultLocation = 'vault_location';
  static const String autoLockTimeout = 'auto_lock_timeout';
  static const String maxLoginAttempts = 'max_login_attempts';
  static const String enableLockoutPolicy = 'enable_lockout_policy';
  static const String wipeAfterFailedAttempts = 'wipe_after_failed_attempts';
  static const String wipeThreshold = 'wipe_threshold';
  static const String autoDestructionEnabled = 'auto_destruction_enabled';
  static const String autoDestructionUrl = 'auto_destruction_url';
  static const String autoDestructionInterval = 'auto_destruction_interval';
  static const String autoDestructionSigned = 'auto_destruction_signed';
  static const String autoDestructionSecret = 'auto_destruction_secret';
  static const String biometricUnlockEnabled = 'biometric_unlock_enabled';
  static const String startAtLogin = 'start_at_login';
  static const String showInMenuBar = 'show_in_menu_bar';
  static const String lastBackupTime = 'last_backup_time';
  static const String pinLength = 'pin_length';
}

/// Application settings model
class AppSettings {
  final String? vaultLocation;
  final int autoLockTimeout; // seconds
  final int maxLoginAttempts;
  final bool enableLockoutPolicy;
  final bool wipeAfterFailedAttempts;
  final int wipeThreshold;
  final bool autoDestructionEnabled;
  final String? autoDestructionUrl;
  final int autoDestructionInterval; // minutes
  final bool autoDestructionSigned;
  final String? autoDestructionSecret;
  final bool biometricUnlockEnabled;
  final bool startAtLogin;
  final bool showInMenuBar;
  final int? lastBackupTime;
  final int pinLength;

  const AppSettings({
    this.vaultLocation,
    this.autoLockTimeout = 300, // 5 minutes default
    this.maxLoginAttempts = 10,
    this.enableLockoutPolicy = true,
    this.wipeAfterFailedAttempts = false,
    this.wipeThreshold = 10,
    this.autoDestructionEnabled = false,
    this.autoDestructionUrl,
    this.autoDestructionInterval = 5, // 5 minutes default
    this.autoDestructionSigned = true,
    this.autoDestructionSecret,
    this.biometricUnlockEnabled = false,
    this.startAtLogin = false,
    this.showInMenuBar = true,
    this.lastBackupTime,
    this.pinLength = 6,
  });

  AppSettings copyWith({
    String? vaultLocation,
    int? autoLockTimeout,
    int? maxLoginAttempts,
    bool? enableLockoutPolicy,
    bool? wipeAfterFailedAttempts,
    int? wipeThreshold,
    bool? autoDestructionEnabled,
    String? autoDestructionUrl,
    int? autoDestructionInterval,
    bool? autoDestructionSigned,
    String? autoDestructionSecret,
    bool? biometricUnlockEnabled,
    bool? startAtLogin,
    bool? showInMenuBar,
    int? lastBackupTime,
    int? pinLength,
  }) {
    return AppSettings(
      vaultLocation: vaultLocation ?? this.vaultLocation,
      autoLockTimeout: autoLockTimeout ?? this.autoLockTimeout,
      maxLoginAttempts: maxLoginAttempts ?? this.maxLoginAttempts,
      enableLockoutPolicy: enableLockoutPolicy ?? this.enableLockoutPolicy,
      wipeAfterFailedAttempts: wipeAfterFailedAttempts ?? this.wipeAfterFailedAttempts,
      wipeThreshold: wipeThreshold ?? this.wipeThreshold,
      autoDestructionEnabled: autoDestructionEnabled ?? this.autoDestructionEnabled,
      autoDestructionUrl: autoDestructionUrl ?? this.autoDestructionUrl,
      autoDestructionInterval: autoDestructionInterval ?? this.autoDestructionInterval,
      autoDestructionSigned: autoDestructionSigned ?? this.autoDestructionSigned,
      autoDestructionSecret: autoDestructionSecret ?? this.autoDestructionSecret,
      biometricUnlockEnabled: biometricUnlockEnabled ?? this.biometricUnlockEnabled,
      startAtLogin: startAtLogin ?? this.startAtLogin,
      showInMenuBar: showInMenuBar ?? this.showInMenuBar,
      lastBackupTime: lastBackupTime ?? this.lastBackupTime,
      pinLength: pinLength ?? this.pinLength,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vault_location': vaultLocation,
      'auto_lock_timeout': autoLockTimeout,
      'max_login_attempts': maxLoginAttempts,
      'enable_lockout_policy': enableLockoutPolicy,
      'wipe_after_failed_attempts': wipeAfterFailedAttempts,
      'wipe_threshold': wipeThreshold,
      'auto_destruction_enabled': autoDestructionEnabled,
      'auto_destruction_url': autoDestructionUrl,
      'auto_destruction_interval': autoDestructionInterval,
      'auto_destruction_signed': autoDestructionSigned,
      'biometric_unlock_enabled': biometricUnlockEnabled,
      'start_at_login': startAtLogin,
      'show_in_menu_bar': showInMenuBar,
      'last_backup_time': lastBackupTime,
      'pin_length': pinLength,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      vaultLocation: json['vault_location'],
      autoLockTimeout: json['auto_lock_timeout'] ?? 300,
      maxLoginAttempts: json['max_login_attempts'] ?? 10,
      enableLockoutPolicy: json['enable_lockout_policy'] ?? true,
      wipeAfterFailedAttempts: json['wipe_after_failed_attempts'] ?? false,
      wipeThreshold: json['wipe_threshold'] ?? 10,
      autoDestructionEnabled: json['auto_destruction_enabled'] ?? false,
      autoDestructionUrl: json['auto_destruction_url'],
      autoDestructionInterval: json['auto_destruction_interval'] ?? 5,
      autoDestructionSigned: json['auto_destruction_signed'] ?? true,
      biometricUnlockEnabled: json['biometric_unlock_enabled'] ?? false,
      startAtLogin: json['start_at_login'] ?? false,
      showInMenuBar: json['show_in_menu_bar'] ?? true,
      lastBackupTime: json['last_backup_time'],
      pinLength: json['pin_length'] ?? 6,
    );
  }
}

/// Repository for application settings
class SettingsRepository {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Load settings from storage
  Future<AppSettings> loadSettings() async {
    final prefs = await _preferences;
    
    return AppSettings(
      vaultLocation: prefs.getString(SettingsKeys.vaultLocation),
      autoLockTimeout: prefs.getInt(SettingsKeys.autoLockTimeout) ?? 300,
      maxLoginAttempts: prefs.getInt(SettingsKeys.maxLoginAttempts) ?? 10,
      enableLockoutPolicy: prefs.getBool(SettingsKeys.enableLockoutPolicy) ?? true,
      wipeAfterFailedAttempts: prefs.getBool(SettingsKeys.wipeAfterFailedAttempts) ?? false,
      wipeThreshold: prefs.getInt(SettingsKeys.wipeThreshold) ?? 10,
      autoDestructionEnabled: prefs.getBool(SettingsKeys.autoDestructionEnabled) ?? false,
      autoDestructionUrl: prefs.getString(SettingsKeys.autoDestructionUrl),
      autoDestructionInterval: prefs.getInt(SettingsKeys.autoDestructionInterval) ?? 5,
      autoDestructionSigned: prefs.getBool(SettingsKeys.autoDestructionSigned) ?? true,
      biometricUnlockEnabled: prefs.getBool(SettingsKeys.biometricUnlockEnabled) ?? false,
      startAtLogin: prefs.getBool(SettingsKeys.startAtLogin) ?? false,
      showInMenuBar: prefs.getBool(SettingsKeys.showInMenuBar) ?? true,
      lastBackupTime: prefs.getInt(SettingsKeys.lastBackupTime),
      pinLength: prefs.getInt(SettingsKeys.pinLength) ?? 6,
    );
  }

  /// Save settings to storage
  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await _preferences;
    
    await prefs.setString(SettingsKeys.vaultLocation, settings.vaultLocation ?? '');
    await prefs.setInt(SettingsKeys.autoLockTimeout, settings.autoLockTimeout);
    await prefs.setInt(SettingsKeys.maxLoginAttempts, settings.maxLoginAttempts);
    await prefs.setBool(SettingsKeys.enableLockoutPolicy, settings.enableLockoutPolicy);
    await prefs.setBool(SettingsKeys.wipeAfterFailedAttempts, settings.wipeAfterFailedAttempts);
    await prefs.setInt(SettingsKeys.wipeThreshold, settings.wipeThreshold);
    await prefs.setBool(SettingsKeys.autoDestructionEnabled, settings.autoDestructionEnabled);
    await prefs.setString(SettingsKeys.autoDestructionUrl, settings.autoDestructionUrl ?? '');
    await prefs.setInt(SettingsKeys.autoDestructionInterval, settings.autoDestructionInterval);
    await prefs.setBool(SettingsKeys.autoDestructionSigned, settings.autoDestructionSigned);
    await prefs.setBool(SettingsKeys.biometricUnlockEnabled, settings.biometricUnlockEnabled);
    await prefs.setBool(SettingsKeys.startAtLogin, settings.startAtLogin);
    await prefs.setBool(SettingsKeys.showInMenuBar, settings.showInMenuBar);
    if (settings.lastBackupTime != null) {
      await prefs.setInt(SettingsKeys.lastBackupTime, settings.lastBackupTime!);
    }
    await prefs.setInt(SettingsKeys.pinLength, settings.pinLength);
  }

  /// Get auto-destruction secret (stored separately for security)
  Future<String?> getAutoDestructionSecret() async {
    final prefs = await _preferences;
    return prefs.getString(SettingsKeys.autoDestructionSecret);
  }

  /// Save auto-destruction secret
  Future<void> saveAutoDestructionSecret(String secret) async {
    final prefs = await _preferences;
    await prefs.setString(SettingsKeys.autoDestructionSecret, secret);
  }

  /// Clear auto-destruction secret
  Future<void> clearAutoDestructionSecret() async {
    final prefs = await _preferences;
    await prefs.remove(SettingsKeys.autoDestructionSecret);
  }

  /// Update specific setting
  Future<void> updateSetting<T>(String key, T value) async {
    final prefs = await _preferences;
    
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is List<String>) {
      await prefs.setStringList(key, value);
    }
  }

  /// Get specific setting
  Future<T?> getSetting<T>(String key) async {
    final prefs = await _preferences;
    
    if (T == String) {
      return prefs.getString(key) as T?;
    } else if (T == int) {
      return prefs.getInt(key) as T?;
    } else if (T == bool) {
      return prefs.getBool(key) as T?;
    } else if (T == double) {
      return prefs.getDouble(key) as T?;
    } else if (T == List<String>) {
      return prefs.getStringList(key) as T?;
    }
    return null;
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    final prefs = await _preferences;
    await prefs.clear();
  }

  /// Export settings as JSON
  Future<String> exportSettings() async {
    final settings = await loadSettings();
    return jsonEncode(settings.toJson());
  }

  /// Import settings from JSON
  Future<void> importSettings(String json) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final settings = AppSettings.fromJson(map);
    await saveSettings(settings);
  }
}
