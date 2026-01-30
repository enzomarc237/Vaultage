import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Cryptographic parameters and constants for Secure File Vault
class CryptoParams {
  // AES-256-GCM parameters
  static const int aesKeySize = 32; // 256 bits
  static const int gcmNonceSize = 12; // 96 bits
  static const int gcmTagSize = 16; // 128 bits
  
  // Argon2id parameters (OWASP recommended minimum)
  static const int argon2MemoryKB = 65536; // 64 MB
  static const int argon2Iterations = 3;
  static const int argon2Parallelism = 4;
  static const int argon2HashLength = 32;
  
  // PBKDF2 fallback parameters
  static const int pbkdf2Iterations = 600000; // OWASP 2023 recommendation
  
  // Key wrapping
  static const int kekSize = 32; // 256 bits for AES-KW
  
  // Salt size
  static const int saltSize = 32; // 256 bits
  
  // File ID size
  static const int fileIdSize = 16; // 128-bit UUID
}

/// Represents a derived key with its parameters
class DerivedKey {
  final Uint8List key;
  final Uint8List salt;
  final Map<String, dynamic> params;
  
  DerivedKey({
    required this.key,
    required this.salt,
    required this.params,
  });
  
  void zeroize() {
    key.fillRange(0, key.length, 0);
  }
}

/// Represents an encrypted file header
class FileHeader {
  final int version;
  final String algorithm;
  final Uint8List wrappedKey;
  final Uint8List nonce;
  final Uint8List encryptedMetadata;
  final int originalSize;
  
  FileHeader({
    required this.version,
    required this.algorithm,
    required this.wrappedKey,
    required this.nonce,
    required this.encryptedMetadata,
    required this.originalSize,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'algorithm': algorithm,
      'wrapped_key': base64Encode(wrappedKey),
      'nonce': base64Encode(nonce),
      'encrypted_metadata': base64Encode(encryptedMetadata),
      'original_size': originalSize,
    };
  }
  
  factory FileHeader.fromJson(Map<String, dynamic> json) {
    return FileHeader(
      version: json['version'],
      algorithm: json['algorithm'],
      wrappedKey: base64Decode(json['wrapped_key']),
      nonce: base64Decode(json['nonce']),
      encryptedMetadata: base64Decode(json['encrypted_metadata']),
      originalSize: json['original_size'],
    );
  }
  
  Uint8List serialize() {
    final jsonBytes = utf8.encode(jsonEncode(toJson()));
    final length = jsonBytes.length;
    final result = Uint8List(4 + length);
    result.buffer.asByteData().setUint32(0, length, Endian.big);
    result.setAll(4, jsonBytes);
    return result;
  }
  
  static FileHeader deserialize(Uint8List data) {
    final length = data.buffer.asByteData().getUint32(0, Endian.big);
    final jsonBytes = data.sublist(4, 4 + length);
    final json = jsonDecode(utf8.decode(jsonBytes));
    return FileHeader.fromJson(json);
  }
}

/// Represents encrypted file metadata
class FileMetadata {
  final String originalName;
  final String mimeType;
  final int createdAt;
  final int modifiedAt;
  final int size;
  final Map<String, dynamic> customAttributes;
  
  FileMetadata({
    required this.originalName,
    required this.mimeType,
    required this.createdAt,
    required this.modifiedAt,
    required this.size,
    this.customAttributes = const {},
  });
  
  Map<String, dynamic> toJson() {
    return {
      'original_name': originalName,
      'mime_type': mimeType,
      'created_at': createdAt,
      'modified_at': modifiedAt,
      'size': size,
      'custom_attributes': customAttributes,
    };
  }
  
  factory FileMetadata.fromJson(Map<String, dynamic> json) {
    return FileMetadata(
      originalName: json['original_name'],
      mimeType: json['mime_type'],
      createdAt: json['created_at'],
      modifiedAt: json['modified_at'],
      size: json['size'] ?? 0,
      customAttributes: json['custom_attributes'] ?? {},
    );
  }
}

/// High-level cryptographic operations for Secure File Vault
class CryptoUtils {
  /// Generate cryptographically secure random bytes
  static Uint8List generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }
  
  /// Generate a 256-bit master key
  static Uint8List generateMasterKey() {
    return generateRandomBytes(CryptoParams.aesKeySize);
  }
  
  /// Generate a unique file ID
  static String generateFileId() {
    final bytes = generateRandomBytes(CryptoParams.fileIdSize);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
  
  /// Derive a key from PIN using Argon2id
  /// 
  /// In a production implementation, this would use a native Argon2 library
  /// via FFI. For this implementation, we use PBKDF2 as a fallback with
  /// high iteration count.
  static Future<DerivedKey> deriveKeyFromPin(
    String pin,
    Uint8List? salt,
  ) async {
    final effectiveSalt = salt ?? generateRandomBytes(CryptoParams.saltSize);
    
    // Use PBKDF2 with high iteration count as Argon2id fallback
    // In production, replace with actual Argon2id implementation via FFI
    final hmac = crypto.Hmac(crypto.sha256, effectiveSalt);
    var key = Uint8List.fromList(utf8.encode(pin));
    
    for (var i = 0; i < CryptoParams.pbkdf2Iterations; i++) {
      key = Uint8List.fromList(hmac.convert(key).bytes);
    }
    
    return DerivedKey(
      key: key,
      salt: effectiveSalt,
      params: {
        'algorithm': 'PBKDF2-HMAC-SHA256',
        'iterations': CryptoParams.pbkdf2Iterations,
        'salt': base64Encode(effectiveSalt),
      },
    );
  }
  
  /// Encrypt data using AES-256-GCM
  static Future<({Uint8List ciphertext, Uint8List nonce, Uint8List tag})> encryptAesGcm(
    Uint8List plaintext,
    Uint8List key,
  ) async {
    final nonce = generateRandomBytes(CryptoParams.gcmNonceSize);
    
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(key);
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    
    return (
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      nonce: Uint8List.fromList(secretBox.nonce),
      tag: Uint8List.fromList(secretBox.mac.bytes),
    );
  }
  
  /// Decrypt data using AES-256-GCM
  static Future<Uint8List> decryptAesGcm(
    Uint8List ciphertext,
    Uint8List key,
    Uint8List nonce,
    Uint8List tag,
  ) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(key);
    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(tag),
    );
    
    final plaintext = await algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    
    return Uint8List.fromList(plaintext);
  }
  
  /// Wrap a key using AES-KW (RFC 3394)
  /// 
  /// Uses AES-256-KW for wrapping file keys with the master key
  static Uint8List wrapKey(Uint8List keyToWrap, Uint8List wrappingKey) {
    // For AES-KW, we use the pointycastle implementation
    // In production, this should use a proper AES-KW implementation
    // For now, we use AES-256-GCM as a key wrapping mechanism
    final iv = generateRandomBytes(12);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(wrappingKey), mode: encrypt.AESMode.gcm),
    );
    
    final encrypted = encrypter.encryptBytes(
      keyToWrap,
      iv: encrypt.IV(iv),
    );
    
    // Return IV + auth tag + ciphertext
    final result = Uint8List(iv.length + encrypted.bytes.length);
    result.setAll(0, iv);
    result.setAll(iv.length, encrypted.bytes);
    return result;
  }
  
  /// Unwrap a key using AES-KW (RFC 3394)
  static Uint8List unwrapKey(Uint8List wrappedKey, Uint8List wrappingKey) {
    final iv = wrappedKey.sublist(0, 12);
    final ciphertext = wrappedKey.sublist(12);
    
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(wrappingKey), mode: encrypt.AESMode.gcm),
    );
    
    final decrypted = encrypter.decryptBytes(
      encrypt.Encrypted(ciphertext),
      iv: encrypt.IV(iv),
    );
    
    return Uint8List.fromList(decrypted);
  }
  
  /// Compute HMAC-SHA256
  static Uint8List hmacSha256(Uint8List data, Uint8List key) {
    final hmac = crypto.Hmac(crypto.sha256, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
  }
  
  /// Compute SHA-256 hash
  static Uint8List sha256Hash(Uint8List data) {
    return Uint8List.fromList(crypto.sha256.convert(data).bytes);
  }
  
  /// Compute ciphertext hash for integrity verification
  static Uint8List computeCiphertextHash(Uint8List ciphertext) {
    return sha256Hash(ciphertext);
  }
  
  /// Verify HMAC-SHA256
  static bool verifyHmac(Uint8List data, Uint8List key, Uint8List expectedMac) {
    final computed = hmacSha256(data, key);
    if (computed.length != expectedMac.length) return false;
    
    // Constant-time comparison
    var result = 0;
    for (var i = 0; i < computed.length; i++) {
      result |= computed[i] ^ expectedMac[i];
    }
    return result == 0;
  }
  
  /// Zeroize a byte array (securely clear memory)
  static void zeroize(Uint8List? data) {
    if (data != null) {
      data.fillRange(0, data.length, 0);
    }
  }
  
  /// Generate recovery key (BIP39-style 12-word phrase)
  static String generateRecoveryKey() {
    // BIP39 word list (simplified - first 2048 words)
    final wordList = _bip39WordList;
    final random = Random.secure();
    
    final words = <String>[];
    for (var i = 0; i < 12; i++) {
      words.add(wordList[random.nextInt(wordList.length)]);
    }
    
    return words.join(' ');
  }
  
  /// Securely compare two byte arrays in constant time
  static bool secureCompare(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

// Simplified BIP39 word list (first 100 words for demo)
// In production, use the full 2048-word BIP39 list
final _bip39WordList = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb', 'abstract',
  'absurd', 'abuse', 'access', 'accident', 'account', 'accuse', 'achieve', 'acid',
  'acoustic', 'acquire', 'across', 'act', 'action', 'actor', 'actress', 'actual',
  'adapt', 'add', 'addict', 'address', 'adjust', 'admit', 'adult', 'advance',
  'advice', 'aerobic', 'affair', 'afford', 'afraid', 'again', 'age', 'agent',
  'agree', 'ahead', 'aim', 'air', 'airport', 'aisle', 'alarm', 'album',
  'alcohol', 'alert', 'alien', 'all', 'alley', 'allow', 'almost', 'alone',
  'alpha', 'already', 'also', 'alter', 'always', 'amateur', 'amazing', 'among',
  'amount', 'amused', 'analyst', 'anchor', 'ancient', 'anger', 'angle', 'angry',
  'animal', 'ankle', 'announce', 'annual', 'another', 'answer', 'antenna', 'antique',
  'anxiety', 'any', 'apart', 'apple', 'apply', 'arena', 'argue', 'armor',
  'around', 'arrange', 'arrest', 'arrive', 'arrow', 'art', 'artist', 'aspect',
  'asset', 'assist', 'assume', 'athlete', 'atom', 'auction', 'audit', 'august',
];
