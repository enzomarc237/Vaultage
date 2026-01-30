# Vaultage - Agent Guidelines

## Build & Run Commands
- **Run**: `flutter run -d macos`
- **Build**: `flutter build macos`
- **Analyze**: `flutter analyze`
- **Test all**: `flutter test`
- **Single test**: `flutter test test/unit/<file>_test.dart` or `flutter test --name "test name"`
- **Code generation**: `dart run build_runner build --delete-conflicting-outputs`

## Architecture (Clean Architecture + BLoC)
- `lib/core/` - Domain layer: entities, value objects, security utilities
- `lib/application/` - Application layer: BLoCs (state management), services
- `lib/infrastructure/` - Data layer: repositories, adapters (file system, keychain)
- `lib/presentation/` - UI layer: screens, widgets (macOS native via macos_ui)

## Code Style
- Use `flutter_bloc` for state management with `Equatable` for state/event equality
- Use `freezed` + `json_serializable` for immutable data classes (run build_runner after changes)
- Prefer `macos_ui` widgets over Material/Cupertino for native macOS look
- Security-critical: use `cryptography` package, store secrets via `flutter_secure_storage`
- Imports: dart → flutter → packages → relative (grouped with blank lines)
- Naming: `snake_case` files, `PascalCase` classes, `camelCase` methods/variables
- Error handling: use Result types or throw domain-specific exceptions
