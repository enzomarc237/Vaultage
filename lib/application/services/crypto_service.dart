import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/security/crypto_utils.dart';

/// Service responsible for all cryptographic operations
class CryptoService {
  // Master key cache (cleared when locked)
  Uint8List? _cachedMasterKey;
  
  // Salt for key derivation (persisted)
  Uint8List? _keyDerivationSalt;
  
  /// Check if the vault has been initialized
  bool get isInitialized => _cachedMasterKey != null;
  
  /// Initialize the crypto service with a PIN (first-time setup)
  Future<({String recoveryKey, Uint8List wrappedMasterKey, Uint8List salt, Map<String, dynamic> params})> 
      initializeWithPin(String pin, {String? recoveryKey}) async {
    // Generate master key
    final masterKey = CryptoUtils.generateMasterKey();
    
    // Derive KEK from PIN
    final derivedKey = await CryptoUtils.deriveKeyFromPin(pin, null);
    _keyDerivationSalt = derivedKey.salt;
    
    // Wrap master key with KEK
    final wrappedMasterKey = CryptoUtils.wrapKey(masterKey, derivedKey.key);
    
    // Use provided recovery key or generate new one
    final effectiveRecoveryKey = recoveryKey ?? CryptoUtils.generateRecoveryKey();
    
    // Cache master key for current session
    _cachedMasterKey = Uint8List.fromList(masterKey);
    
    // Zeroize sensitive data
    CryptoUtils.zeroize(masterKey);
    derivedKey.zeroize();
    
    return (
      recoveryKey: effectiveRecoveryKey,
      wrappedMasterKey: wrappedMasterKey,
      salt: _keyDerivationSalt!,
      params: derivedKey.params,
    );
  }
  
  /// Unlock the vault with PIN
  Future<bool> unlockWithPin(String pin, Uint8List wrappedMasterKey, Uint8List salt) async {
    try {
      // Derive KEK from PIN
      final derivedKey = await CryptoUtils.deriveKeyFromPin(pin, salt);
      
      // Unwrap master key
      final masterKey = CryptoUtils.unwrapKey(wrappedMasterKey, derivedKey.key);
      
      // Validate by checking key length
      if (masterKey.length != CryptoParams.aesKeySize) {
        CryptoUtils.zeroize(masterKey);
        derivedKey.zeroize();
        return false;
      }
      
      // Cache master key
      _cachedMasterKey = masterKey;
      _keyDerivationSalt = salt;
      
      derivedKey.zeroize();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Lock the vault and clear sensitive data from memory
  void lock() {
    if (_cachedMasterKey != null) {
      CryptoUtils.zeroize(_cachedMasterKey);
      _cachedMasterKey = null;
    }
  }
  
  /// Check if vault is unlocked
  bool get isUnlocked => _cachedMasterKey != null;
  
  /// Unlock the vault with biometric (the wrapped key was already decrypted via biometric auth)
  void unlockWithBiometricKey(Uint8List wrappedMasterKey) {
    try {
      // For biometric unlock, we assume the key was already authenticated
      // We just need to unwrap it using a stored KEK or directly if stored differently
      // This is a simplified version - in production, you'd have a biometric-specific wrapping
      _cachedMasterKey = wrappedMasterKey;
    } catch (e) {
      // Failed to unlock
    }
  }
  
  /// Encrypt a file
  Future<({FileHeader header, Uint8List ciphertext})> encryptFile(
    Uint8List plaintext,
    String originalFilename,
    String mimeType,
  ) async {
    if (_cachedMasterKey == null) {
      throw StateError('Vault is locked');
    }
    
    // Generate per-file key
    final fileKey = CryptoUtils.generateRandomBytes(CryptoParams.aesKeySize);
    
    // Encrypt file content
    final encryptionResult = await CryptoUtils.encryptAesGcm(plaintext, fileKey);
    
    // Create ciphertext with tag appended (standard GCM format)
    final ciphertext = Uint8List(
      encryptionResult.ciphertext.length + encryptionResult.tag.length,
    );
    ciphertext.setAll(0, encryptionResult.ciphertext);
    ciphertext.setAll(encryptionResult.ciphertext.length, encryptionResult.tag);
    
    // Wrap file key with master key
    final wrappedKey = CryptoUtils.wrapKey(fileKey, _cachedMasterKey!);
    
    // Create metadata
    final now = DateTime.now().millisecondsSinceEpoch;
    final metadata = FileMetadata(
      originalName: originalFilename,
      mimeType: mimeType,
      createdAt: now,
      modifiedAt: now,
      size: plaintext.length,
    );
    
    // Encrypt metadata
    final metadataJson = utf8.encode(jsonEncode(metadata.toJson()));
    final encryptedMetadata = await CryptoUtils.encryptAesGcm(
      metadataJson,
      _cachedMasterKey!,
    );
    
    // Combine nonce and ciphertext for metadata
    final encryptedMetadataBytes = Uint8List(
      encryptedMetadata.nonce.length + 
      encryptedMetadata.ciphertext.length + 
      encryptedMetadata.tag.length,
    );
    encryptedMetadataBytes.setAll(0, encryptedMetadata.nonce);
    encryptedMetadataBytes.setAll(
      encryptedMetadata.nonce.length, 
      encryptedMetadata.ciphertext,
    );
    encryptedMetadataBytes.setAll(
      encryptedMetadata.nonce.length + encryptedMetadata.ciphertext.length,
      encryptedMetadata.tag,
    );
    
    // Create header
    final header = FileHeader(
      version: 1,
      algorithm: 'AES-256-GCM',
      wrappedKey: wrappedKey,
      nonce: encryptionResult.nonce,
      encryptedMetadata: encryptedMetadataBytes,
      originalSize: plaintext.length,
    );
    
    // Zeroize sensitive data
    CryptoUtils.zeroize(fileKey);
    
    return (header: header, ciphertext: ciphertext);
  }
  
  /// Decrypt a file
  Future<({Uint8List plaintext, FileMetadata metadata})> decryptFile(
    FileHeader header,
    Uint8List ciphertext,
  ) async {
    if (_cachedMasterKey == null) {
      throw StateError('Vault is locked');
    }
    
    // Unwrap file key
    final fileKey = CryptoUtils.unwrapKey(header.wrappedKey, _cachedMasterKey!);
    
    // Extract tag from end of ciphertext
    final actualCiphertext = ciphertext.sublist(0, ciphertext.length - CryptoParams.gcmTagSize);
    final tag = ciphertext.sublist(ciphertext.length - CryptoParams.gcmTagSize);
    
    // Decrypt file content
    final plaintext = await CryptoUtils.decryptAesGcm(
      actualCiphertext,
      fileKey,
      header.nonce,
      tag,
    );
    
    // Decrypt metadata
    final metadataNonce = header.encryptedMetadata.sublist(0, CryptoParams.gcmNonceSize);
    final metadataCiphertextEnd = header.encryptedMetadata.length - CryptoParams.gcmTagSize;
    final metadataCiphertext = header.encryptedMetadata.sublist(
      CryptoParams.gcmNonceSize, 
      metadataCiphertextEnd,
    );
    final metadataTag = header.encryptedMetadata.sublist(metadataCiphertextEnd);
    
    final metadataJson = await CryptoUtils.decryptAesGcm(
      metadataCiphertext,
      _cachedMasterKey!,
      metadataNonce,
      metadataTag,
    );
    
    final metadata = FileMetadata.fromJson(
      jsonDecode(utf8.decode(metadataJson)),
    );
    
    // Zeroize sensitive data
    CryptoUtils.zeroize(fileKey);
    
    return (plaintext: plaintext, metadata: metadata);
  }
  
  /// Crypto-shred a file (delete wrapped key to make data unrecoverable)
  Uint8List? cryptoShredFile(FileHeader header) {
    // Simply return null to indicate the wrapped key should be deleted
    // The actual deletion is handled by the repository
    return null;
  }
  
  /// Change PIN (re-wrap master key with new KEK)
  Future<({Uint8List wrappedMasterKey, Uint8List salt, Map<String, dynamic> params})>
      changePin(String currentPin, String newPin, Uint8List currentWrappedKey, Uint8List currentSalt) async {
    // First unlock with current PIN
    final unlocked = await unlockWithPin(currentPin, currentWrappedKey, currentSalt);
    if (!unlocked) {
      throw StateError('Current PIN is incorrect');
    }
    
    // Derive new KEK from new PIN
    final newDerivedKey = await CryptoUtils.deriveKeyFromPin(newPin, null);
    
    // Re-wrap master key with new KEK
    final newWrappedMasterKey = CryptoUtils.wrapKey(_cachedMasterKey!, newDerivedKey.key);
    
    final result = (
      wrappedMasterKey: newWrappedMasterKey,
      salt: newDerivedKey.salt,
      params: newDerivedKey.params,
    );
    
    newDerivedKey.zeroize();
    
    return result;
  }
  
  /// Generate HMAC for manifest signing
  Uint8List signManifest(Uint8List manifestData) {
    if (_cachedMasterKey == null) {
      throw StateError('Vault is locked');
    }
    
    // Derive signing key from master key
    final signingKey = CryptoUtils.hmacSha256(
      Uint8List.fromList(utf8.encode('manifest-signing-key')),
      _cachedMasterKey!,
    );
    
    final signature = CryptoUtils.hmacSha256(manifestData, signingKey);
    CryptoUtils.zeroize(signingKey);
    
    return signature;
  }
  
  /// Verify manifest signature
  bool verifyManifest(Uint8List manifestData, Uint8List signature) {
    if (_cachedMasterKey == null) {
      throw StateError('Vault is locked');
    }
    
    // Derive signing key from master key
    final signingKey = CryptoUtils.hmacSha256(
      utf8.encode('manifest-signing-key') as Uint8List,
      _cachedMasterKey!,
    );
    
    final computed = CryptoUtils.hmacSha256(manifestData, signingKey);
    CryptoUtils.zeroize(signingKey);
    
    return CryptoUtils.secureCompare(computed, signature);
  }
  
  /// Compute hash of ciphertext for integrity verification
  Uint8List computeCiphertextHash(Uint8List ciphertext) {
    return CryptoUtils.sha256Hash(ciphertext);
  }
  
  /// Generate filename HMAC to hide original filename
  String computeFilenameHmac(String filename) {
    if (_cachedMasterKey == null) {
      throw StateError('Vault is locked');
    }
    
    // Derive filename key from master key
    final filenameKey = CryptoUtils.hmacSha256(
      Uint8List.fromList(utf8.encode('filename-key')),
      _cachedMasterKey!,
    );
    
    final hmac = CryptoUtils.hmacSha256(
      utf8.encode(filename) as Uint8List,
      filenameKey,
    );
    
    CryptoUtils.zeroize(filenameKey);
    
    return hmac.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
  
  /// Clear all sensitive data (for emergency wipe)
  void clearAllData() {
    lock();
    _keyDerivationSalt = null;
  }
}
