import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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
  static const int currentManifestVersion = 1;
  
  String? _vaultPath;
  
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
  
  /// Load all files from manifest
  Future<List<StoredFile>> loadManifest() async {
    final manifestPath = await _getManifestPath();
    final manifestFile = File(manifestPath);
    
    if (!await manifestFile.exists()) {
      return [];
    }
    
    try {
      final jsonContent = await manifestFile.readAsString();
      final manifest = jsonDecode(jsonContent) as Map<String, dynamic>;
      
      final files = (manifest['files'] as List<dynamic>? ?? [])
          .map((f) => _storedFileFromJson(f as Map<String, dynamic>))
          .toList();
      
      return files;
    } catch (e) {
      // If manifest is corrupted, return empty list
      return [];
    }
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
      final content = await manifestFile.readAsString();
      manifest = jsonDecode(content) as Map<String, dynamic>;
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
    
    await manifestFile.writeAsString(
      jsonEncode(manifest),
      flush: true,
    );
  }
  
  /// Remove file from manifest
  Future<void> _removeFromManifest(String fileId) async {
    final manifestPath = await _getManifestPath();
    final manifestFile = File(manifestPath);
    
    if (!await manifestFile.exists()) return;
    
    final content = await manifestFile.readAsString();
    final manifest = jsonDecode(content) as Map<String, dynamic>;
    
    final files = manifest['files'] as List<dynamic>;
    files.removeWhere((f) => (f as Map<String, dynamic>)['id'] == fileId);
    
    manifest['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    
    await manifestFile.writeAsString(
      jsonEncode(manifest),
      flush: true,
    );
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

