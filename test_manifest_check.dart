import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';

Future<void> main() async {
  // Get application documents directory
  final documentsDir = await getApplicationDocumentsDirectory();
  final vaultPath = path.join(documentsDir.path, 'SecureVault');
  final manifestPath = path.join(vaultPath, 'manifest.enc');

  print('Vault Path: $vaultPath');
  print('Manifest Path: $manifestPath');

  final manifestFile = File(manifestPath);

  if (await manifestFile.exists()) {
    print('Manifest file exists');

    final bytes = await manifestFile.readAsBytes();
    print('Manifest Size: ${bytes.length} bytes');

    // Try to decode as JSON
    try {
      final jsonStr = utf8.decode(bytes);
      print('Manifest Content:');
      print(jsonStr);

      final manifest = jsonDecode(jsonStr) as Map<String, dynamic>;
      print('Manifest Version: ${manifest['version']}');
      print('Files Count: ${(manifest['files'] as List).length}');

      for (var file in manifest['files']) {
        print('File: ${file['metadata']['original_name']}');
      }
    } catch (e) {
      print('Not valid JSON - likely encrypted');
    }
  } else {
    print('Manifest file does NOT exist');
  }

  // Check files directory
  final filesDir = Directory(path.join(vaultPath, 'files'));
  if (await filesDir.exists()) {
    print('Files Directory exists');

    final files = await filesDir.list().toList();
    print('Files in directory: ${files.length}');

    for (var file in files) {
      print('File: ${path.basename(file.path)}');
    }
  } else {
    print('Files Directory does NOT exist');
  }
}
