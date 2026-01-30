import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mime/mime.dart';

import '../../core/security/crypto_utils.dart';
import '../services/crypto_service.dart';
import '../services/keychain_service.dart';
import '../../infrastructure/repositories/file_repository.dart';

// Events
abstract class VaultEvent extends Equatable {
  const VaultEvent();

  @override
  List<Object?> get props => [];
}

class VaultLoadRequested extends VaultEvent {}

class AddFilesRequested extends VaultEvent {
  final List<String>? filePaths;

  const AddFilesRequested({this.filePaths});

  @override
  List<Object?> get props => [filePaths];
}

class FileDecryptRequested extends VaultEvent {
  final String fileId;

  const FileDecryptRequested({required this.fileId});

  @override
  List<Object?> get props => [fileId];
}

class FileDeleteRequested extends VaultEvent {
  final String fileId;
  final bool secureDelete;

  const FileDeleteRequested({
    required this.fileId,
    this.secureDelete = true,
  });

  @override
  List<Object?> get props => [fileId, secureDelete];
}

class VaultLockRequested extends VaultEvent {}

class VaultSearchRequested extends VaultEvent {
  final String query;

  const VaultSearchRequested({required this.query});

  @override
  List<Object?> get props => [query];
}

class VaultExportRequested extends VaultEvent {
  final String destinationPath;

  const VaultExportRequested({required this.destinationPath});

  @override
  List<Object?> get props => [destinationPath];
}

// States
abstract class VaultState extends Equatable {
  const VaultState();

  @override
  List<Object?> get props => [];
}

class VaultInitial extends VaultState {}

class VaultLoading extends VaultState {}

class VaultLoaded extends VaultState {
  final List<VaultFile> files;
  final String vaultPath;
  final int totalSize;

  const VaultLoaded({
    required this.files,
    required this.vaultPath,
    required this.totalSize,
  });

  @override
  List<Object?> get props => [files, vaultPath, totalSize];
}

class VaultFileDecrypting extends VaultState {
  final String fileId;

  const VaultFileDecrypting({required this.fileId});

  @override
  List<Object?> get props => [fileId];
}

class VaultFileDecrypted extends VaultState {
  final String fileId;
  final Uint8List data;
  final FileMetadata metadata;

  const VaultFileDecrypted({
    required this.fileId,
    required this.data,
    required this.metadata,
  });

  @override
  List<Object?> get props => [fileId, data, metadata];
}

class VaultFileAdding extends VaultState {
  final int current;
  final int total;

  const VaultFileAdding({
    required this.current,
    required this.total,
  });

  @override
  List<Object?> get props => [current, total];
}

class VaultFileAdded extends VaultState {
  final VaultFile file;

  const VaultFileAdded({required this.file});

  @override
  List<Object?> get props => [file];
}

class VaultFileDeleting extends VaultState {
  final String fileId;

  const VaultFileDeleting({required this.fileId});

  @override
  List<Object?> get props => [fileId];
}

class VaultFileDeleted extends VaultState {
  final String fileId;

  const VaultFileDeleted({required this.fileId});

  @override
  List<Object?> get props => [fileId];
}

class VaultError extends VaultState {
  final String message;

  const VaultError({required this.message});

  @override
  List<Object?> get props => [message];
}

class VaultSearching extends VaultState {
  final String query;

  const VaultSearching({required this.query});

  @override
  List<Object?> get props => [query];
}

class VaultSearchResults extends VaultState {
  final List<VaultFile> results;
  final String query;

  const VaultSearchResults({
    required this.results,
    required this.query,
  });

  @override
  List<Object?> get props => [results, query];
}

class VaultExporting extends VaultState {
  final String destinationPath;

  const VaultExporting({required this.destinationPath});

  @override
  List<Object?> get props => [destinationPath];
}

class VaultExported extends VaultState {
  final String destinationPath;

  const VaultExported({required this.destinationPath});

  @override
  List<Object?> get props => [destinationPath];
}

// Domain model
class VaultFile extends Equatable {
  final String id;
  final String filename;
  final String? filenameHmac;
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? mimeType;
  final String ciphertextHash;

  const VaultFile({
    required this.id,
    required this.filename,
    this.filenameHmac,
    required this.size,
    required this.createdAt,
    required this.modifiedAt,
    this.mimeType,
    required this.ciphertextHash,
  });

  @override
  List<Object?> get props => [
    id, filename, filenameHmac, size, 
    createdAt, modifiedAt, mimeType, ciphertextHash,
  ];
}

// BLoC
class VaultBloc extends Bloc<VaultEvent, VaultState> {
  final FileRepository _fileRepository;
  final CryptoService _cryptoService;

  
  List<VaultFile> _currentFiles = [];
  String? _vaultPath;

  VaultBloc({
    required FileRepository fileRepository,
    required CryptoService cryptoService,
    required KeychainService keychainService,
  }) : _fileRepository = fileRepository,
       _cryptoService = cryptoService,

       super(VaultInitial()) {
    on<VaultLoadRequested>(_onVaultLoadRequested);
    on<AddFilesRequested>(_onAddFilesRequested);
    on<FileDecryptRequested>(_onFileDecryptRequested);
    on<FileDeleteRequested>(_onFileDeleteRequested);
    on<VaultLockRequested>(_onVaultLockRequested);
    on<VaultSearchRequested>(_onVaultSearchRequested);
    on<VaultExportRequested>(_onVaultExportRequested);
  }

  Future<void> _onVaultLoadRequested(
    VaultLoadRequested event,
    Emitter<VaultState> emit,
  ) async {
    emit(VaultLoading());
    
    try {
      _vaultPath ??= await _fileRepository.getVaultPath();
      final files = await _fileRepository.loadManifest();
      
      _currentFiles = files.map((f) => VaultFile(
        id: f.id,
        filename: f.metadata.originalName,
        size: f.metadata.size,
        createdAt: DateTime.fromMillisecondsSinceEpoch(f.metadata.createdAt),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(f.metadata.modifiedAt),
        mimeType: f.metadata.mimeType,
        ciphertextHash: f.ciphertextHash,
      )).toList();
      
      final totalSize = _currentFiles.fold<int>(0, (sum, f) => sum + f.size);
      
      emit(VaultLoaded(
        files: _currentFiles,
        vaultPath: _vaultPath!,
        totalSize: totalSize,
      ));
    } catch (e) {
      emit(VaultError(message: 'Failed to load vault: $e'));
    }
  }

  Future<void> _onAddFilesRequested(
    AddFilesRequested event,
    Emitter<VaultState> emit,
  ) async {
    if (!_cryptoService.isUnlocked) {
      emit(const VaultError(message: 'Vault is locked'));
      return;
    }
    
    List<String> filesToAdd = event.filePaths ?? [];
    
    // If no paths provided, file picker would be called here
    // For now, we'll require paths to be provided
    if (filesToAdd.isEmpty) {
      emit(const VaultError(message: 'No files selected'));
      return;
    }
    
    emit(VaultFileAdding(current: 0, total: filesToAdd.length));
    
    try {
      for (var i = 0; i < filesToAdd.length; i++) {
        final filePath = filesToAdd[i];
        final file = File(filePath);
        
        if (!await file.exists()) {
          continue;
        }
        
        emit(VaultFileAdding(current: i + 1, total: filesToAdd.length));
        
        // Read file
        final bytes = await file.readAsBytes();
        final filename = file.path.split(Platform.pathSeparator).last;
        final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
        
        // Encrypt file
        final encrypted = await _cryptoService.encryptFile(
          bytes,
          filename,
          mimeType,
        );
        
        // Save to vault
        final vaultFile = await _fileRepository.saveFile(
          encrypted.header,
          encrypted.ciphertext,
          originalFilename: filename,
          mimeType: mimeType,
          originalSize: bytes.length,
        );
        
        final newVaultFile = VaultFile(
          id: vaultFile.id,
          filename: filename,
          size: bytes.length,
          createdAt: DateTime.fromMillisecondsSinceEpoch(vaultFile.metadata.createdAt),
          modifiedAt: DateTime.fromMillisecondsSinceEpoch(vaultFile.metadata.modifiedAt),
          mimeType: mimeType,
          ciphertextHash: vaultFile.ciphertextHash,
        );
        
        _currentFiles.add(newVaultFile);
        emit(VaultFileAdded(file: newVaultFile));
      }
      
      // Reload vault state
      add(VaultLoadRequested());
    } catch (e) {
      emit(VaultError(message: 'Failed to add files: $e'));
    }
  }

  Future<void> _onFileDecryptRequested(
    FileDecryptRequested event,
    Emitter<VaultState> emit,
  ) async {
    if (!_cryptoService.isUnlocked) {
      emit(const VaultError(message: 'Vault is locked'));
      return;
    }
    
    emit(VaultFileDecrypting(fileId: event.fileId));
    
    try {
      final result = await _fileRepository.loadFile(event.fileId);
      
      final decrypted = await _cryptoService.decryptFile(
        result.header,
        result.ciphertext,
      );
      
      emit(VaultFileDecrypted(
        fileId: event.fileId,
        data: decrypted.plaintext,
        metadata: decrypted.metadata,
      ));
    } catch (e) {
      emit(VaultError(message: 'Failed to decrypt file: $e'));
    }
  }

  Future<void> _onFileDeleteRequested(
    FileDeleteRequested event,
    Emitter<VaultState> emit,
  ) async {
    emit(VaultFileDeleting(fileId: event.fileId));
    
    try {
      if (event.secureDelete) {
        // Crypto-shred: delete wrapped key from manifest
        await _fileRepository.secureDeleteFile(event.fileId);
      } else {
        // Regular delete
        await _fileRepository.deleteFile(event.fileId);
      }
      
      _currentFiles.removeWhere((f) => f.id == event.fileId);
      
      emit(VaultFileDeleted(fileId: event.fileId));
      add(VaultLoadRequested());
    } catch (e) {
      emit(VaultError(message: 'Failed to delete file: $e'));
    }
  }

  Future<void> _onVaultLockRequested(
    VaultLockRequested event,
    Emitter<VaultState> emit,
  ) async {
    _cryptoService.lock();
    _currentFiles = [];
    emit(VaultInitial());
  }

  Future<void> _onVaultSearchRequested(
    VaultSearchRequested event,
    Emitter<VaultState> emit,
  ) async {
    emit(VaultSearching(query: event.query));
    
    final query = event.query.toLowerCase();
    final results = _currentFiles.where((f) =>
      f.filename.toLowerCase().contains(query) ||
      f.mimeType?.toLowerCase().contains(query) == true
    ).toList();
    
    emit(VaultSearchResults(results: results, query: event.query));
  }

  Future<void> _onVaultExportRequested(
    VaultExportRequested event,
    Emitter<VaultState> emit,
  ) async {
    emit(VaultExporting(destinationPath: event.destinationPath));
    
    try {
      await _fileRepository.exportVault(event.destinationPath);
      emit(VaultExported(destinationPath: event.destinationPath));
    } catch (e) {
      emit(VaultError(message: 'Failed to export vault: $e'));
    }
  }
}
