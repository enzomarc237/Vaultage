# Secure File Vault

A secure file vault application for macOS that provides encrypted storage for sensitive files.

## Features
- **Secure Authentication**
  - PIN-based authentication
  - Configurable auto-logout
  - Maximum login attempts with lockout
  - Biometric authentication (planned)
 
- **File Security**
  - AES-256 encryption  
  - Secure file deletion
  - Automatic encryption on app unfocus
  - File integrity verification
  - Support for various file types
 
- **Auto-Destruction**
  - Remote destruction trigger via URL
  - Configurable check interval
  - Secure deletion of all files
 
- **Native macOS Integration**
  - Native UI using macos_ui package
  - System tray integration
  - Start at login option
  - Multi-window support
 
## Requirements
- macOS 10.15 or later
- Xcode 14.0 or later
- Flutter 3.7.0 or later
 
## Setup
1. **Clone the repository**
    ```bash
    git clone https://github.com/enzomarc237/crypto-vault-macos.git
    cd crypto-vault-macos
    ```
 
2. **Install dependencies**
    ```bash
    flutter pub get
    ```
 
3. **Run the app**
    ```bash
    flutter run -d macos
    ```
 
## Development
### Project Structure
``` 
lib/
├── application/          # BLoC and application logic
│   └── blocs/
├── core/                # Core business logic
│   ├── data/           # Data layer implementations
│   ├── domain/         # Domain models and repositories
│   └── security/       # Security services
├── presentation/       # UI layer
│   ├── screens/        # App screens
│   └── widgets/        # Reusable widgets
```
### Key Components
 
- **Authentication Service**: Handles user authentication and PIN management
- **Encryption Service**: Manages file encryption/decryption using AES-256
- **File Repository**: Manages file operations and metadata
- **Settings Repository**: Handles application configuration
- **BLoC Pattern**: Used for state management
 
### Building
 
To build a release version:
 
```bash
flutter build macos
``` 

The built app will be available in `build/macos/Build/Products/Release/`.
 
## Security Features
 
- AES-256 encryption for all files
- Secure key storage using macOS Keychain
- Secure file deletion with multiple overwrites
- File integrity verification
- Auto-encryption on app unfocus
- Configurable auto-logout
- Remote destruction capability
 
## Configuration
 
The app can be configured through the Settings screen:
 
- Vault location
- Auto-logout duration
- Maximum login attempts
- Auto-destruction URL and interval
- System integration options
 
## Contributing
 
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
 
## License
 
This project is licensed under the MIT License - see the LICENSE file for details.
 
## Acknowledgments
 
- [macos_ui](https://pub.dev/packages/macos_ui) for native macOS UI components
- [flutter_bloc](https://pub.dev/packages/flutter_bloc) for state management
- [encrypt](https://pub.dev/packages/encrypt) for encryption functionality