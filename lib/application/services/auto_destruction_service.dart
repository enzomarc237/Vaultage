import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../infrastructure/repositories/file_repository.dart';
import '../../infrastructure/repositories/settings_repository.dart';
import 'keychain_service.dart';

/// Auto-destruction trigger response
class DestructionTrigger {
  final bool triggerDestruction;
  final String? signature;
  final int? timestamp;
  final Map<String, dynamic>? metadata;

  DestructionTrigger({
    required this.triggerDestruction,
    this.signature,
    this.timestamp,
    this.metadata,
  });

  factory DestructionTrigger.fromJson(Map<String, dynamic> json) {
    return DestructionTrigger(
      triggerDestruction: json['trigger_destruction'] ?? false,
      signature: json['signature'],
      timestamp: json['timestamp'],
      metadata: json['metadata'],
    );
  }
}

/// Service for monitoring remote destruction triggers
class AutoDestructionService {
  final SettingsRepository _settingsRepository;
  final FileRepository _fileRepository;
  final KeychainService _keychainService;
  final Dio _dio;

  Timer? _pollingTimer;
  DateTime? _lastCheck;
  String? _currentUrl;
  bool _isMonitoring = false;

  // Stream controller for destruction events
  final _destructionController = StreamController<void>.broadcast();
  Stream<void> get onDestructionTriggered => _destructionController.stream;

  // Callback for when destruction is triggered
  Future<void> Function()? onBeforeDestruction;

  AutoDestructionService({
    required SettingsRepository settingsRepository,
    required FileRepository fileRepository,
    required KeychainService keychainService,
  })  : _settingsRepository = settingsRepository,
        _fileRepository = fileRepository,
        _keychainService = keychainService,
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (status) => status != null && status < 500,
        ));

  /// Check if currently monitoring
  bool get isMonitoring => _isMonitoring;

  /// Get last check time
  DateTime? get lastCheck => _lastCheck;

  /// Start monitoring for destruction triggers
  Future<void> startMonitoring({
    required String url,
    required Duration interval,
    bool useSignedTriggers = true,
  }) async {
    // Stop any existing monitoring
    await stopMonitoring();

    _currentUrl = url;
    _isMonitoring = true;

    // Perform initial check
    await _checkForTrigger(useSignedTriggers);

    // Start periodic checking
    _pollingTimer = Timer.periodic(interval, (_) async {
      await _checkForTrigger(useSignedTriggers);
    });
  }

  /// Stop monitoring
  Future<void> stopMonitoring() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isMonitoring = false;
    _currentUrl = null;
  }

  /// Check for destruction trigger
  Future<void> _checkForTrigger(bool useSignedTriggers) async {
    if (_currentUrl == null) return;

    try {
      final response = await _dio.get(_currentUrl!);
      _lastCheck = DateTime.now();

      if (response.statusCode == 200) {
        final data = response.data;

        if (data is Map<String, dynamic>) {
          final trigger = DestructionTrigger.fromJson(data);

          if (trigger.triggerDestruction) {
            // Validate signature if required
            if (useSignedTriggers) {
              final isValid = await _validateTriggerSignature(trigger);
              if (!isValid) {
                // Log suspicious activity but don't destroy
                await _logSuspiciousTrigger(trigger);
                return;
              }
            }

            // Trigger validated - execute destruction
            await _executeDestruction();
          }
        }
      }
    } on DioException catch (e) {
      // Network errors shouldn't trigger destruction
      // Only trigger on valid, verified responses
      _logNetworkError(e);
    } catch (e) {
      _logError('Error checking destruction trigger: $e');
    }
  }

  /// Validate trigger signature using HMAC
  Future<bool> _validateTriggerSignature(DestructionTrigger trigger) async {
    if (trigger.signature == null || trigger.timestamp == null) {
      return false;
    }

    // Get the secret from secure storage
    final secret = await _settingsRepository.getAutoDestructionSecret();
    if (secret == null) {
      // No secret configured - reject unsigned triggers
      return false;
    }

    // Build the message to verify
    final message = jsonEncode({
      'trigger_destruction': trigger.triggerDestruction,
      'timestamp': trigger.timestamp,
    });

    // Compute expected signature
    final hmac = Hmac(sha256, utf8.encode(secret));
    final expectedSignature = base64Encode(
      hmac.convert(utf8.encode(message)).bytes,
    );

    // Constant-time comparison
    return _secureCompare(trigger.signature!, expectedSignature);
  }

  /// Public method to trigger complete data wipe
  Future<void> wipeAllData() async {
    await _executeDestruction();
  }

  /// Execute secure destruction of all vault data

  Future<void> _executeDestruction() async {
    try {
      // Notify listeners before destruction
      _destructionController.add(null);

      // Call pre-destruction callback if set
      if (onBeforeDestruction != null) {
        await onBeforeDestruction!();
      }

      // 1. Destroy all files (crypto-shredding)
      await _fileRepository.destroyAllFiles();

      // 2. Clear all keychain items
      await _keychainService.secureWipe();

      // 3. Stop monitoring
      await stopMonitoring();

      // 4. Reset settings
      await _settingsRepository.resetToDefaults();

      _logEvent('Auto-destruction executed successfully');
    } catch (e) {
      _logError('Error during auto-destruction: $e');
      // Continue destruction even if parts fail
    }
  }

  /// Test the destruction URL (without triggering)
  Future<({bool reachable, bool validResponse, String? error})> testUrl(
    String url,
  ) async {
    try {
      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;

        if (data is Map<String, dynamic>) {
          // Check if response has expected format
          final hasTriggerField = data.containsKey('trigger_destruction');

          return (
            reachable: true,
            validResponse: hasTriggerField,
            error: hasTriggerField
                ? null
                : 'Response missing trigger_destruction field',
          );
        }

        return (
          reachable: true,
          validResponse: false,
          error: 'Invalid response format',
        );
      }

      return (
        reachable: true,
        validResponse: false,
        error: 'HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      return (
        reachable: false,
        validResponse: false,
        error: e.message,
      );
    } catch (e) {
      return (
        reachable: false,
        validResponse: false,
        error: e.toString(),
      );
    }
  }

  /// Generate a new shared secret for trigger signing
  String generateSharedSecret() {
    final random = DateTime.now().millisecondsSinceEpoch;
    final bytes = utf8.encode('secret_$random${DateTime.now().microsecond}');
    final hash = sha256.convert(bytes);
    return base64Encode(hash.bytes);
  }

  /// Secure comparison of two strings (constant time)
  bool _secureCompare(String a, String b) {
    if (a.length != b.length) return false;

    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Log suspicious trigger attempt
  Future<void> _logSuspiciousTrigger(DestructionTrigger trigger) async {
    // In production, this would write to a secure audit log
    print(
        'SUSPICIOUS: Invalid destruction trigger signature at ${DateTime.now()}');
  }

  /// Log network error
  void _logNetworkError(DioException error) {
    // Silent fail for network errors - don't expose information
    // In production, this might log to a secure audit log
  }

  /// Log error
  void _logError(String message) {
    // In production, use proper logging
    print('ERROR: $message');
  }

  /// Log event
  void _logEvent(String message) {
    // In production, use proper logging
    print('EVENT: $message');
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _destructionController.close();
  }
}
