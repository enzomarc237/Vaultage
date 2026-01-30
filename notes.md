# Implementation Notes

## Package Requirements

### Phase 1: Security
- `flutter_secure_storage` ✓ (already included)
- `crypto` ✓ (already included)

### Phase 2: File Management
- `file_picker` ✓ (already in pubspec but unused)
- `desktop_drop: ^0.4.0` - Drag & drop support
- `flutter_dropzone` - Alternative drag & drop
- `pdfx` or `native_pdf_view` - PDF preview
- `path_provider` ✓ (already included)

### Phase 3: Auth
- `local_auth` ✓ (already in pubspec but unused)
- `flutter/services.dart` ✓ (for keyboard shortcuts)

### Phase 4: Testing
- `flutter_test` ✓ (already included)
- `bloc_test` ✓ (already in dev_dependencies)
- `mockito` ✓ (already included)
- `mocktail` - Alternative mocking

### Phase 5: Advanced
- `ffi` - For Argon2 native binding
- `argon2_ffi` - If available, or custom FFI

---

## Critical Code Locations

### Hardcoded Recovery Key (CRITICAL)
**File:** `lib/main.dart:478`
```dart
// CURRENT (BAD):
final recoveryKey = 'apple lumber crystal brave ocean dentist flower magic seven captain bridge';

// FIX:
final recoveryKey = CryptoUtils.generateRecoveryKey();
```

### File Picker Stub
**File:** `lib/presentation/screens/vault_screen.dart:496`
```dart
// CURRENT (stub):
_showAddFilesDialog() { /* shows info dialog only */ }

// FIX:
_useFilePicker() async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
  // ... encrypt files
}
```

### Manifest Encryption
**File:** `lib/infrastructure/repositories/file_repository.dart`
```dart
// Add to _addToManifest:
final encryptedManifest = await _cryptoService.encryptData(
  utf8.encode(jsonEncode(manifest)),
  'manifest',
  'application/json',
);
```

---

## FFI Setup for Argon2

### Directory Structure
```
lib/
├── native/
│   ├── argon2/
│   │   ├── argon2.h
│   │   ├── argon2.c
│   │   └── libargon2.dylib (compiled)
│   └── ffi_bindings.dart
```

### Binding Example
```dart
import 'dart:ffi';
import 'dart:io';

typedef Argon2HashNative = Pointer<Utf8> Function(
  Pointer<Utf8> password,
  Pointer<Utf8> salt,
  Uint32 iterations,
  Uint32 memory,
  Uint32 parallelism,
);
typedef Argon2Hash = Pointer<Utf8> Function(
  Pointer<Utf8> password,
  Pointer<Utf8> salt,
  int iterations,
  int memory,
  int parallelism,
);
```

---

## Drag & Drop Implementation

### Using desktop_drop
```dart
DropTarget(
  onDragDone: (details) {
    final files = details.files;
    for (final file in files) {
      context.read<VaultBloc>().add(AddFilesRequested(filePaths: [file.path]));
    }
  },
  child: // vault grid or drop zone
)
```

---

## Keyboard Shortcuts

### Using CallbackShortcuts
```dart
CallbackShortcuts(
  bindings: <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () {
      context.read<AuthBloc>().add(LockRequested());
    },
    const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () {
      _showAddFilesDialog();
    },
  },
  child: child,
)
```

---

## Test Patterns

### BLoC Test Template
```dart
blocTest<AuthBloc, AuthState>(
  'emits [AuthLoading, AuthAuthenticated] when unlock succeeds',
  build: () => AuthBloc(
    keychainService: mockKeychainService,
    cryptoService: mockCryptoService,
  ),
  act: (bloc) => bloc.add(UnlockRequested(pin: '123456')),
  expect: () => [
    isA<AuthLoading>(),
    isA<AuthAuthenticated>(),
  ],
);
```

### Crypto Test Template
```dart
group('CryptoUtils', () {
  test('encrypt/decrypt round-trip', () async {
    final plaintext = utf8.encode('test data');
    final key = CryptoUtils.generateMasterKey();
    
    final encrypted = await CryptoUtils.encryptAesGcm(plaintext, key);
    final decrypted = await CryptoUtils.decryptAesGcm(
      encrypted.ciphertext,
      key,
      encrypted.nonce,
      encrypted.tag,
    );
    
    expect(decrypted, equals(plaintext));
  });
});
```

---

## Migration: Unencrypted → Encrypted Manifest

### Version Detection
```dart
Future<void> _migrateManifestIfNeeded() async {
  final manifestPath = await _getManifestPath();
  final file = File(manifestPath);
  
  if (!await file.exists()) return;
  
  final content = await file.readAsString();
  
  // Try to parse as JSON (old format)
  try {
    final json = jsonDecode(content);
    // It's old format, encrypt it
    await _encryptAndSaveManifest(json);
  } catch (e) {
    // Already encrypted or corrupted
  }
}
```

---

## Biometric Auth Flow

```dart
Future<void> _authenticateWithBiometrics() async {
  final localAuth = LocalAuthentication();
  
  final canCheck = await localAuth.canCheckBiometrics;
  if (!canCheck) return;
  
  final available = await localAuth.getAvailableBiometrics();
  if (!available.contains(BiometricType.face) && 
      !available.contains(BiometricType.fingerprint)) {
    return;
  }
  
  final didAuth = await localAuth.authenticate(
    localizedReason: 'Unlock Secure File Vault',
    options: const AuthenticationOptions(
      biometricOnly: true,
      stickyAuth: true,
    ),
  );
  
  if (didAuth) {
    // Unlock vault using stored key from Keychain
    // (Keychain item protected by biometry)
  }
}
```

---

## Resources

- [macos_ui docs](https://pub.dev/packages/macos_ui)
- [desktop_drop](https://pub.dev/packages/desktop_drop)
- [local_auth](https://pub.dev/packages/local_auth)
- [bloc_test](https://pub.dev/packages/bloc_test)
- [Dart FFI](https://dart.dev/guides/libraries/c-interop)
