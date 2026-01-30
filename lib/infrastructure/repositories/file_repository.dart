import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../application/services/crypto_service.dart';
import '../../core/security/crypto_utils.dart';

/// Internal representation of a stored file
class StoredFile {
  final String id;
  final FileHeader header;
  final FileMetadata metadata;
  final String ciphertextHash;
  final String storagePath;

  StoredFile({
    required this.id,
    required this.header,
    required this.metadata,
    required this.ciphertextHash,
    required this.storagePath,
  });
}

/// Repository for file operations
class FileRepository {
  static const String vaultDirName = 'SecureVault';
  static const String filesSubdir = 'files';
  static const String manifestFileName = 'manifest.enc';
  static const String configFileName = 'config.enc';
  static const int currentManifestVersion = 2; // Bumped for encrypted manifest
  
  final CryptoService _cryptoService;
  String? _vaultPath;
  
  FileRepository({CryptoService? cryptoService}) 
      : _cryptoService = cryptoService ?? CryptoService();
  
  /// Get or create vault path
  Future<String> getVaultPath() async {
    if (_vaultPath != null) return _vaultPath!;
    
    final documentsDir = await getApplicationDocumentsDirectory();
    _vaultPath = path.join(documentsDir.path, vaultDirName);
    
    // Create vault directory structure
    final vaultDir = Directory(_vaultPath!);
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    
    final filesDir = Directory(path.join(_vaultPath!, filesSubdir));
    if (!await filesDir.exists()) {
      await filesDir.create(recursive: true);
    }
    
    return _vaultPath!;
  }
  
  /// Get files directory path
  Future<String> _getFilesPath() async {
    final vaultPath = await getVaultPath();
    return path.join(vaultPath, filesSubdir);
  }
  
  /// Get manifest file path
  Future<String> _getManifestPath() async {
    final vaultPath = await getVaultPath();
    return path.join(vaultPath, manifestFileName);
  }
  
  /// Save an encrypted file to the vault
  Future<StoredFile> saveFile(
    FileHeader header,
    Uint8List ciphertext, {
    required String originalFilename,
    required String mimeType,
    required int originalSize,
  }) async {
    final fileId = CryptoUtils.generateFileId();
    final filesPath = await _getFilesPath();
    final storagePath = path.join(filesPath, '$fileId.vfile');
    
    // Serialize header
    final headerBytes = header.serialize();
    
    // Write file: header + ciphertext
    final file = File(storagePath);
    await file.writeAsBytes(headerBytes + ciphertext);
    
    // Compute ciphertext hash
    final ciphertextHash = CryptoUtils.computeCiphertextHash(ciphertext)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');
    
    // Create metadata
    final metadata = FileMetadata(
      originalName: originalFilename,
      mimeType: mimeType,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      modifiedAt: DateTime.now().millisecondsSinceEpoch,
      size: originalSize,
    );
    
    final storedFile = StoredFile(
      id: fileId,
      header: header,
      metadata: metadata,
      ciphertextHash: ciphertextHash,
      storagePath: storagePath,
    );
    
    // Add to manifest
    await _addToManifest(storedFile);
    
    return storedFile;
  }
  
  /// Load a file from the vault
  Future<({FileHeader header, Uint8List ciphertext})> loadFile(String fileId) async {
    final filesPath = await _getFilesPath();
    final storagePath = path.join(filesPath, '$fileId.vfile');
    
    final file = File(storagePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', storagePath);
    }
    
    final bytes = await file.readAsBytes();
    
    // Parse header length (first 4 bytes, big-endian)
    final headerLength = bytes.buffer.asByteData().getUint32(0, Endian.big);
    
    // Extract header and ciphertext
    final headerBytes = bytes.sublist(4, 4 + headerLength);
    final ciphertext = bytes.sublist(4 + headerLength);
    
    final header = FileHeader.deserialize(headerBytes);
    
    return (header: header, ciphertext: ciphertext);
  }
  
  /// Load all files from manifest (handles both encrypted v2 and unencrypted v1)
  Future<List<StoredFile>> loadManifest() async {
    final manifestPath = await _getManifestPath();
    final manifestFile = File(manifestPath);
    
    if (!await manifestFile.exists()) {
      return [];
    }
    
    try {
      final bytes = await manifestFile.readAsBytes();
      Map<String, dynamic> manifest;
      
      // Try to detect if manifest is encrypted
      if (_isEncryptedManifest(bytes)) {
        // Decrypt manifest using crypto service
        if (!_cryptoService.isUnlocked) {
          throw StateError('Vault is locked - cannot decrypt manifest');
        }
        manifest = await _decryptManifest(bytes);
      } else {
        // Legacy unencrypted manifest (v1)
        final jsonContent = utf8.decode(bytes);
        manifest = jsonDecode(jsonContent) as Map<String, dynamic>;
        
        // Migrate to encrypted format if vault is unlocked
        if (_cryptoService.isUnlocked) {
          await _migrateManifestToEncrypted(manifest);
        }
      }
      
      final files = (manifest['files'] as List<dynamic>? ?? [])
          .map((f) => _storedFileFromJson(f as Map<String, dynamic>))
          .toList();
      
      return files;
    } catch (e) {
      // If manifest is corrupted or decryption fails, return empty list
      print('Error loading manifest: $e');
      return [];
    }
  }
  
  /// Check if manifest bytes appear to be encrypted
  bool _isEncryptedManifest(Uint8List bytes) {
    // Encrypted manifest starts with a specific header
    if (bytes.length < 4) return false;
    
    // Try to parse as JSON - if it succeeds, it's unencrypted
    try {
      final str = utf8.decode(bytes);
      jsonDecode(str);
      return false; // Successfully parsed as JSON = unencrypted
    } catch (e) {
      return true; // Not valid JSON = likely encrypted
    }
  }
  
  /// Decrypt manifest bytes
  Future<Map<String, dynamic>> _decryptManifest(Uint8List encryptedBytes) async {
    // Format: [version: 1 byte][nonce: 12 bytes][ciphertext + tag]
    final version = encryptedBytes[0];
    if (version != 1) {
      throw UnsupportedError('Unknown manifest encryption version: $version');
    }
    
    final nonce = encryptedBytes.sublist(1, 13);
    final ciphertextWithTag = encryptedBytes.sublist(13);
    
    // Decrypt using crypto service
    // We use a special 'manifest' file ID for manifest encryption
    final decrypted = await _cryptoService.decryptFile(
      FileHeader(
        version: 1,
        algorithm: 'AES-256-GCM',
        wrappedKey: Uint8List(0), // Manifest uses master key directly
        nonce: nonce,
        encryptedMetadata: Uint8List(0),
        originalSize: 0,
      ),
      ciphertextWithTag,
    );
    
    final jsonStr = utf8.decode(decrypted.plaintext);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }
  
  /// Migrate unencrypted manifest to encrypted format
  Future<void> _migrateManifestToEncrypted(Map<String, dynamic> manifest) async {
    try {
      await _saveManifestEncrypted(manifest);
      print('Manifest migrated to encrypted format (v2)');
    } catch (e) {
      print('Failed to migrate manifest to encrypted format: $e');
    }
  }
  
  /// Save manifest in encrypted format
  Future<void> _saveManifestEncrypted(Map<String, dynamic> manifest) async {
    if (!_cryptoService.isUnlocked) {
      throw StateError('Vault is locked - cannot encrypt manifest');
    }
    
    final manifestPath = await _getManifestPath();
    final manifestFile = File(manifestPath);
    
    final jsonBytes = utf8.encode(jsonEncode(manifest));
    
    // Encrypt using crypto service
    final encrypted = await _cryptoService.encryptFile(
      Uint8List.fromList(jsonBytes),
      'manifest',
      'application/json',
    );
    
    // Format: [version: 1 byte][nonce: 12 bytes][ciphertext + tag]
    final result = Uint8List(1 + 12 + encrypted.ciphertext.length);
    result[0] = 1; // Encryption version
    result.setAll(1, encrypted.header.nonce);
    result.setAll(13, encrypted.ciphertext);
    
    await manifestFile.writeAsBytes(result, flush: true);
  }
  
  /// Delete a file (regular delete)
  Future<void> deleteFile(String fileId) async {
    final filesPath = await _getFilesPath();
    final storagePath = path.join(filesPath, '$fileId.vfile');
    
    final file = File(storagePath);
    if (await file.exists()) {
      await file.delete();
    }
    
    // Remove from manifest
    await _removeFromManifest(fileId);
  }
  
  /// Secure delete a file (crypto-shredding)
  Future<void> secureDeleteFile(String fileId) async {
    // For crypto-shredding, we:
    // 1. Remove the wrapped key from the manifest
    // 2. Optionally overwrite the file with random data
    // 3. Delete the file
    
    final filesPath = await _getFilesPath();
    final storagePath = path.join(filesPath, '$fileId.vfile');
    final file = File(storagePath);
    
    if (await file.exists()) {
      // Get file size for overwrite
      final size = await file.length();
      
      // Overwrite with random data (3 passes for good measure)
      final random = Random.secure();
      for (var pass = 0; pass < 3; pass++) {
        final randomData = Uint8List.fromList(
          List.generate(size, (_) => random.nextInt(256)),
        );
        await file.writeAsBytes(randomData, flush: true);
      }
      
      await file.delete();
    }
    
    // Remove from manifest
    await _removeFromManifest(fileId);
  }
  
  /// Securely delete all files (for auto-destruction)
  Future<void> destroyAllFiles() async {
    final filesPath = await _getFilesPath();
    final filesDir = Directory(filesPath);
    
    if (await filesDir.exists()) {
      // List all files
      await for (final entity in filesDir.list()) {
        if (entity is File && entity.path.endsWith('.vfile')) {
          // Get file size for overwrite
          final size = await entity.length();
          
          // Multiple overwrite passes
          final random = Random.secure();
          for (var pass = 0; pass < 7; pass++) {
            final randomData = Uint8List.fromList(
              List.generate(size, (_) => random.nextInt(256)),
            );
            await entity.writeAsBytes(randomData, flush: true);
          }
          
          await entity.delete();
        }
      }
    }
    
    // Delete manifest
    final manifestPath = await _getManifestPath();
    final manifestFile = File(manifestPath);
    if (await manifestFile.exists()) {
      await manifestFile.delete();
    }
  }
  
  /// Add file to manifest
  Future<void> _addToManifest(StoredFile file) async {
    final manifestPath = await _getManifestPath();
    final manifestFile = File(manifestPath);
    
    Map<String, dynamic> manifest;
    if (await manifestFile.exists()) {
      // Load existing manifest (handles both encrypted and unencrypted)
      final existingFiles = await loadManifest();
      manifest = {
        'version': currentManifestVersion,
        'files': existingFiles.map((f) => _storedFileToJson(_convertToStoredFile(f))).toList(),
      };
    } else {
      manifest = {
        'version': currentManifestVersion,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'files': <dynamic>[],
      };
    }
    
    final files = manifest['files'] as List<dynamic>;
    files.add(_storedFileToJson(file));
    
    manifest['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    
    // Save encrypted if vault is unlocked, otherwise unencrypted (for migration)
    if (_cryptoService.isUnlocked) {
      await _saveManifestEncrypted(manifest);
    } else {
      await manifestFile.writeAsString(
        jsonEncode(manifest),
        flush: true,
      );
    }
  }
  
  /// Helper to convert VaultFile back to StoredFile
  StoredFile _convertToStoredFile(VaultFile file) {
    return StoredFile(
      id: file.id,
      header: FileHeader(
        version: 1,
        algorithm: 'AES-256-GCM',
        wrappedKey: Uint8List(0),
        nonce: Uint8List(12),
        encryptedMetadata: Uint8List(0),
        originalSize: file.size,
      ),
      metadata: FileMetadata(
        originalName: file.filename,
        mimeType: file.mimeType ?? 'application/octet-stream',
        createdAt: file.createdAt.millisecondsSinceEpoch,
        modifiedAt: file.modifiedAt.millisecondsSinceEpoch,
        size: file.size,
      ),
      ciphertextHash: file.ciphertextHash,
      storagePath: '',
    );
  }
  
  /// Remove file from manifest
  Future<void> _removeFromManifest(String fileId) async {
    final manifestPath = await _getManifestPath();
    final manifestFile = File(manifestPath);
    
    if (!await manifestFile.exists()) return;
    
    // Load existing manifest
    final existingFiles = await loadManifest();
    final updatedFiles = existingFiles.where((f) => f.id != fileId).toList();
    
    final manifest = {
      'version': currentManifestVersion,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'files': updatedFiles.map((f) => _storedFileToJson(_convertToStoredFile(f))).toList(),
    };
    
    // Save encrypted if vault is unlocked
    if (_cryptoService.isUnlocked) {
      await _saveManifestEncrypted(manifest);
    } else {
      await manifestFile.writeAsString(
        jsonEncode(manifest),
        flush: true,
      );
    }
  }
  
  /// Export vault to a single package file
  Future<void> exportVault(String destinationPath) async {
    final vaultPath = await getVaultPath();
    
    // Create a tar-like archive (simplified as zip)
    // For simplicity, we just copy the vault directory
    // In production, this would create a proper archive with compression
    final vaultDir = Directory(vaultPath);
    
    if (destinationPath.endsWith('.vaultpkg')) {
      // Create vault package (zip-like format)
      // For now, just copy the directory
      await _copyDirectory(vaultDir, Directory(destinationPath));
    }
  }
  
  /// Import vault from package
  Future<void> importVault(String sourcePath) async {
    final vaultPath = await getVaultPath();
    
    // Clear existing vault
    final vaultDir = Directory(vaultPath);
    if (await vaultDir.exists()) {
      await vaultDir.delete(recursive: true);
    }
    
    // Copy imported vault
    await _copyDirectory(Directory(sourcePath), vaultDir);
  }
  
  /// Helper: Copy directory recursively
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    
    await for (final entity in source.list(recursive: false)) {
      final name = path.basename(entity.path);
      final destPath = path.join(destination.path, name);
      
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }
  
  /// Helper: Decrypt metadata from header
  Future<Uint8List> _decryptMetadata(FileHeader header) async {
    // Metadata is encrypted in the header
    // Format: nonce (12) + ciphertext + tag (16)
    final metadataBytes = header.encryptedMetadata;
    
    // For now, return empty - actual decryption requires master key
    // This would be done by the crypto service
    return Uint8List(0);
  }
  
  /// Convert StoredFile to JSON
  Map<String, dynamic> _storedFileToJson(StoredFile file) {
    return {
      'id': file.id,
      'metadata': {
        'original_name': file.metadata.originalName,
        'mime_type': file.metadata.mimeType,
        'created_at': file.metadata.createdAt,
        'modified_at': file.metadata.modifiedAt,
      },
      'ciphertext_hash': file.ciphertextHash,
      'storage_path': file.storagePath,
      'header': file.header.toJson(),
    };
  }
  
  /// Convert JSON to StoredFile
  StoredFile _storedFileFromJson(Map<String, dynamic> json) {
    final metadataJson = json['metadata'] as Map<String, dynamic>;
    final headerJson = json['header'] as Map<String, dynamic>;
    
    return StoredFile(
      id: json['id'],
      header: FileHeader.fromJson(headerJson),
      metadata: FileMetadata(
        originalName: metadataJson['original_name'],
        mimeType: metadataJson['mime_type'],
        createdAt: metadataJson['created_at'],
        modifiedAt: metadataJson['modified_at'],
        size: metadataJson['size'] ?? 0,
      ),
      ciphertextHash: json['ciphertext_hash'],
      storagePath: json['storage_path'],
    );
  }
}

