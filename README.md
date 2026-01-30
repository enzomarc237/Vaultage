# Secure File Vault

A privacy-first, cryptographically robust macOS desktop application designed for military-grade encrypted storage of sensitive files.

![macOS Version](https://img.shields.io/badge/macOS-10.15%2B-blue)
![Flutter Version](https://img.shields.io/badge/Flutter-3.7%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### 🔐 Security

- **AES-256-GCM Encryption** - Industry-standard authenticated encryption
- **Per-File Keys** - Each file encrypted with a unique 256-bit key
- **Argon2id Key Derivation** - Memory-hard KDF to resist brute-force attacks
- **Crypto-Shredding** - Secure deletion by destroying encryption keys
- **Rate-Limiting** - Exponential backoff after failed PIN attempts
- **Secure Enclave Integration** - Key storage in macOS Keychain

### 📁 File Management

- **Drag & Drop** - Easy file addition
- **Encrypted Manifest** - Secure metadata storage
- **File Integrity** - AEAD authentication prevents tampering
- **Search & Browse** - Grid view with file previews

### 🔥 Advanced Features

- **Auto-Destruction** - Remote wipe via signed HTTPS triggers
- **Auto-Lock** - Automatic vault lock on app unfocus
- **Recovery Keys** - 12-word BIP39-style recovery phrases
- **System Tray** - Menu bar integration for quick access
- **Export/Import** - Encrypted vault backups

## Architecture

```
lib/
├── application/
│   ├── blocs/          # BLoC state management
│   │   ├── auth_bloc.dart
│   │   ├── vault_bloc.dart
│   │   └── settings_bloc.dart
│   └── services/       # Core business logic
│       ├── crypto_service.dart
│       ├── keychain_service.dart
│       └── auto_destruction_service.dart
├── core/
│   └── security/       # Cryptographic primitives
│       └── crypto_utils.dart
├── infrastructure/
│   └── repositories/   # Data persistence
│       ├── file_repository.dart
│       └── settings_repository.dart
└── presentation/
    └── screens/        # UI screens
        ├── lock_screen.dart
        ├── vault_screen.dart
        └── settings_screen.dart
```

## Cryptography Details

### Key Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                         User PIN                            │
└─────────────────────┬───────────────────────────────────────┘
                      │ Argon2id
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                    Key Encryption Key                       │
└─────────────────────┬───────────────────────────────────────┘
                      │ AES-KW (RFC 3394)
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                       Master Key                            │
└─────────────────────┬───────────────────────────────────────┘
                      │ AES-KW
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                      Per-File Keys                          │
└─────────────────────┬───────────────────────────────────────┘
                      │ AES-256-GCM
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                    Encrypted Files                          │
└─────────────────────────────────────────────────────────────┘
```

### File Format

Each encrypted file (`.vfile`) contains:

```
┌──────────────┬─────────────────────────────────────────────────────┐
│   Header     │  Encrypted File Content (ciphertext + AEAD tag)    │
│   (JSON)     │                                                     │
├──────────────┼─────────────────────────────────────────────────────┤
│ • version    │                                                     │
│ • wrapped_key│  AES-256-GCM encrypted data                          │
│ • nonce      │  96-bit IV + ciphertext + 128-bit tag                │
│ • metadata   │                                                     │
└──────────────┴─────────────────────────────────────────────────────┘
```

## Installation

### Prerequisites

- macOS 10.15 (Catalina) or later
- Xcode 14.0 or later
- Flutter 3.7.0 or later

### Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/enzomarc237/secure-file-vault.git
   cd secure-file-vault
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run -d macos
   ```

4. **Build release**
   ```bash
   flutter build macos
   ```

## Usage

### First Launch

1. Set your PIN (4-12 digits)
2. Save your 12-word recovery key securely
3. Start adding files to your vault

### Daily Use

- **Unlock**: Enter your PIN on the lock screen
- **Add Files**: Drag & drop or use the + button
- **Open Files**: Double-click to decrypt and view
- **Delete**: Uses crypto-shredding for secure deletion
- **Lock**: Click the lock icon or press ⌘L

### Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Auto-Lock Timeout | Minutes before auto-lock | 5 min |
| PIN Length | Number of digits | 6 |
| Max Attempts | Failed attempts before lockout | 10 |
| Remote Destruction | URL to poll for wipe trigger | Disabled |

## Security Considerations

### Threat Model

**Protected against:**
- Physical device theft
- Offline brute-force attacks (via Argon2id)
- File system forensics (via crypto-shredding)
- Memory dumps (keys zeroed after use)

**Limitations:**
- Cannot protect against kernel-level compromise
- Cannot protect against active memory extraction during use
- APFS snapshots may retain old encrypted data

### Best Practices

1. **Use a strong PIN** - 6+ digits, avoid patterns
2. **Save recovery key offline** - Print and store securely
3. **Enable auto-lock** - Shorter timeouts are more secure
4. **Use crypto-shred** - Always use secure delete for sensitive files
5. **Verify remote destruction URL** - Use HTTPS with certificate pinning

## Development

### Running Tests

```bash
# Unit tests
flutter test

# Integration tests
flutter test integration_test/
```

### Project Structure

The app follows **Clean Architecture** with BLoC pattern:

- **Presentation Layer**: UI widgets and screens
- **Application Layer**: BLoCs for state management
- **Domain Layer**: Entities and repository interfaces
- **Infrastructure Layer**: Repository implementations

### Security Review

All cryptographic changes must include:
- Design rationale
- Unit and integration tests
- Migration plan for existing vaults

## Roadmap

- [x] v0.1: Core encryption, PIN auth, basic UI
- [x] v0.2: Keychain integration, Argon2, secure deletion
- [ ] v0.3: Biometric unlock, manifest signing, backups
- [ ] v1.0: Notarized release, security audit
- [ ] v1.1: Folder organization, tags, search
- [ ] v1.2: Cloud escrow, multi-device sync

## Dependencies

| Package | Purpose |
|---------|---------|
| macos_ui | Native macOS UI components |
| flutter_bloc | State management |
| cryptography | Cryptographic primitives |
| flutter_secure_storage | Keychain access |
| dio | HTTP client for auto-destruction |
| file_picker | File selection dialog |

## License

MIT License - see [LICENSE](LICENSE) file

## Acknowledgments

- [macos_ui](https://pub.dev/packages/macos_ui) for native macOS components
- [Argon2](https://github.com/P-H-C/phc-winner-argon2) reference implementation
- Apple Secure Enclave documentation

## Security Disclosure

If you discover a security vulnerability, please email security@example.com with:
- Description of the issue
- Steps to reproduce
- Potential impact

Do not open public issues for security vulnerabilities.

---

**Note**: This is a security-focused application. Always verify the cryptographic implementation before storing sensitive data. Consider a third-party security audit for production deployments.
