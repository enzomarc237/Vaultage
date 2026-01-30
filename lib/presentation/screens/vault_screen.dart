import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../application/blocs/vault_bloc.dart';
import '../../application/blocs/auth_bloc.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _searchController = TextEditingController();
  String _selectedFileId = '';
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    // Load vault when screen initializes
    context.read<VaultBloc>().add(VaultLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VaultBloc, VaultState>(
      listener: (context, state) {
        if (state is VaultFileDecrypted) {
          _showFilePreview(state);
        } else if (state is VaultError) {
          _showError(state.message);
        }
      },
      builder: (context, state) {
        return MacosScaffold(
          toolBar: ToolBar(
            title: Text(_getTitle(state)),
            titleWidth: 200,
            leading: MacosTooltip(
              message: 'Lock Vault (⌘L)',
              child: MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.lock),
                onPressed: () => context.read<AuthBloc>().add(LockRequested()),
              ),
            ),
            actions: [
              ToolBarIconButton(
                label: 'Add Files',
                icon: const MacosIcon(CupertinoIcons.plus),
                onPressed: () => _showAddFilesDialog(),
                showLabel: true,
              ),
              ToolBarIconButton(
                label: 'Search',
                icon: const MacosIcon(CupertinoIcons.search),
                onPressed: () {},
                showLabel: false,
              ),
              const ToolBarSpacer(),
              ToolBarPullDownButton(
                label: 'Actions',
                icon: CupertinoIcons.ellipsis_circle,
                items: [
                  MacosPulldownMenuItem(
                    title: const Text('Export Vault'),
                    onTap: () => _showExportDialog(),
                  ),
                  MacosPulldownMenuItem(
                    title: const Text('Import Files'),
                    onTap: () => _showAddFilesDialog(),
                  ),
                  const MacosPulldownMenuDivider(),
                  MacosPulldownMenuItem(
                    title: const Text('Select All'),
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          children: [
            DropTarget(
              onDragDone: (details) {
                final files = details.files
                    .where((f) => f.path != null)
                    .map((f) => f.path!)
                    .toList();
                if (files.isNotEmpty) {
                  context.read<VaultBloc>().add(AddFilesRequested(filePaths: files));
                }
                setState(() => _isDragging = false);
              },
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              child: ContentArea(
                builder: (context, scrollController) {
                  Widget content;
                  
                  if (state is VaultLoading || state is VaultInitial) {
                    content = const Center(child: ProgressCircle());
                  } else if (state is VaultError && state is! VaultLoaded) {
                    content = Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const MacosIcon(
                            CupertinoIcons.exclamationmark_triangle_fill,
                            size: 48,
                            color: MacosColors.systemRedColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading vault',
                            style: MacosTheme.of(context).typography.title2,
                          ),
                          const SizedBox(height: 8),
                          Text((state as VaultError).message),
                          const SizedBox(height: 16),
                          PushButton(
                            controlSize: ControlSize.regular,
                            onPressed: () {
                              context.read<VaultBloc>().add(VaultLoadRequested());
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  } else if (state is VaultLoaded || state is VaultFileAdding || state is VaultFileDecrypting) {
                    final files = state is VaultLoaded 
                      ? state.files 
                      : (state as dynamic).files ?? [];
                    
                    if (files.isEmpty) {
                      content = _buildEmptyState();
                    } else {
                      content = _buildFileGrid(files, state);
                    }
                  } else {
                    content = const Center(child: Text('Unknown state'));
                  }
                  
                  // Show drag overlay when dragging files
                  if (_isDragging) {
                    return Container(
                      color: MacosColors.systemBlueColor.withOpacity(0.1),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: MacosColors.systemBlueColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: MacosColors.systemBlueColor,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const MacosIcon(
                                CupertinoIcons.arrow_down_doc,
                                size: 64,
                                color: MacosColors.systemBlueColor,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Drop files here to encrypt',
                                style: MacosTheme.of(context).typography.title1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  
                  return content;
                },
              ),
            ),
            if (_selectedFileId.isNotEmpty)
              ResizablePane(
                minSize: 200,
                startSize: 300,
                maxSize: 400,
                windowBreakpoint: 600,
                resizableSide: ResizableSide.left,
                builder: (_, __) => _buildFileDetails(),
              ),
          ],
        );
      },
    );
  }

  String _getTitle(VaultState state) {
    if (state is VaultLoaded) {
      final fileCount = state.files.length;
      final sizeStr = _formatFileSize(state.totalSize);
      return '$fileCount files • $sizeStr';
    }
    if (state is VaultFileAdding) {
      return 'Adding file ${state.current} of ${state.total}...';
    }
    return 'Secure Vault';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(128, 128, 128, 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: MacosIcon(
                  CupertinoIcons.folder_badge_plus,
                  size: 48,
                  color: MacosColors.systemGrayColor,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your vault is empty',
              style: MacosTheme.of(context).typography.title1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Add files to get started. Your files will be encrypted with AES-256-GCM.',
              style: MacosTheme.of(context).typography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: () => _showAddFilesDialog(),
              child: const Text('Add Files'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileGrid(List<dynamic> files, VaultState state) {
    final isLoading = state is VaultFileAdding || state is VaultFileDecrypting;
    
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.8,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final isSelected = file.id == _selectedFileId;
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFileId = isSelected ? '' : file.id;
                  });
                },
                onDoubleTap: () {
                  context.read<VaultBloc>().add(
                    FileDecryptRequested(fileId: file.id),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                      ? const Color.fromRGBO(0, 122, 255, 0.1)
                      : const Color.fromRGBO(128, 128, 128, 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                        ? MacosColors.systemBlueColor
                        : MacosColors.systemGrayColor.withOpacity(0.2),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MacosIcon(
                        _getFileIcon(file.mimeType),
                        size: 48,
                        color: MacosColors.systemBlueColor,
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          file.filename,
                          style: MacosTheme.of(context).typography.body,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatFileSize(file.size),
                        style: MacosTheme.of(context).typography.caption1.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        if (isLoading)
          Container(
            color: MacosColors.windowBackgroundColor.withOpacity(0.8),
            child: const Center(
              child: ProgressCircle(),
            ),
          ),
      ],
    );
  }

  Widget _buildFileDetails() {
    return BlocBuilder<VaultBloc, VaultState>(
      builder: (context, state) {
        if (state is! VaultLoaded) return const SizedBox.shrink();
        
        final file = state.files.firstWhere(
          (f) => f.id == _selectedFileId,
          orElse: () => null as dynamic,
        );
        
        if (file == null) return const SizedBox.shrink();
        
        return Container(
          color: const Color.fromRGBO(240, 240, 240, 1),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: MacosIcon(
                  _getFileIcon(file.mimeType),
                  size: 64,
                  color: MacosColors.systemBlueColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                file.filename,
                style: MacosTheme.of(context).typography.title2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              _buildDetailRow('Type', file.mimeType ?? 'Unknown'),
              _buildDetailRow('Size', _formatFileSize(file.size)),
              _buildDetailRow('Created', _formatDate(file.createdAt)),
              _buildDetailRow('Modified', _formatDate(file.modifiedAt)),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: () {
                  context.read<VaultBloc>().add(
                    FileDecryptRequested(fileId: file.id),
                  );
                },
                child: const Text('Decrypt & Open'),
              ),
              const SizedBox(height: 8),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => _showDeleteConfirmation(file.id, file.filename),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: MacosTheme.of(context).typography.caption1.copyWith(
                color: MacosColors.secondaryLabelColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: MacosTheme.of(context).typography.body,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String? mimeType) {
    if (mimeType == null) return CupertinoIcons.doc;
    
    if (mimeType.startsWith('image/')) {
      return CupertinoIcons.photo;
    } else if (mimeType.startsWith('video/')) {
      return CupertinoIcons.videocam;
    } else if (mimeType.startsWith('audio/')) {
      return CupertinoIcons.music_note;
    } else if (mimeType.contains('pdf')) {
      return CupertinoIcons.doc_text;
    } else if (mimeType.contains('text')) {
      return CupertinoIcons.text_alignleft;
    } else if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return CupertinoIcons.archivebox;
    }
    
    return CupertinoIcons.doc;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showFilePreview(VaultFileDecrypted state) {
    showMacosSheet(
      context: context,
      barrierDismissible: true,
      builder: (_) => MacosSheet(
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MacosIcon(
                    CupertinoIcons.doc_checkmark_fill,
                    color: MacosColors.systemGreenColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.metadata.originalName,
                      style: MacosTheme.of(context).typography.title2,
                    ),
                  ),
                  MacosIconButton(
                    icon: const MacosIcon(CupertinoIcons.xmark),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  color: const Color.fromRGBO(128, 128, 128, 0.05),
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'File decrypted successfully!\nSize: ${_formatFileSize(state.data.length)}',
                      textAlign: TextAlign.center,
                      style: MacosTheme.of(context).typography.body,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.regular,
                    onPressed: () {
                      // Save decrypted file
                      Navigator.pop(context);
                    },
                    child: const Text('Save to...'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddFilesDialog() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final filePaths = result.files
            .where((f) => f.path != null)
            .map((f) => f.path!)
            .toList();
        
        if (filePaths.isNotEmpty) {
          context.read<VaultBloc>().add(AddFilesRequested(filePaths: filePaths));
        }
      }
    } catch (e) {
      _showError('Failed to pick files: $e');
    }
  }

  void _showDeleteConfirmation(String fileId, String filename) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(
          CupertinoIcons.trash,
          size: 56,
          color: MacosColors.systemRedColor,
        ),
        title: const Text('Confirm Delete'),
        message: Text(
          'Are you sure you want to delete "$filename"?\n\n'
          'This will use crypto-shredding to make the file unrecoverable.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () {
            Navigator.pop(context);
            context.read<VaultBloc>().add(
              FileDeleteRequested(fileId: fileId, secureDelete: true),
            );
            setState(() {
              _selectedFileId = '';
            });
          },
          child: const Text('Delete'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showExportDialog() {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(
          CupertinoIcons.arrow_up_doc,
          size: 56,
        ),
        title: const Text('Export Vault'),
        message: const Text(
          'Export your entire encrypted vault for backup. '
          'The backup will be encrypted with your current keys.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () {
            Navigator.pop(context);
            // Trigger export
          },
          child: const Text('Export'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showError(String message) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(
          CupertinoIcons.exclamationmark_circle,
          size: 56,
          color: MacosColors.systemRedColor,
        ),
        title: const Text('Error'),
        message: Text(message),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ),
    );
  }
}
