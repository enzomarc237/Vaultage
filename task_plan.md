# Task Plan: Complete Secure File Vault Implementation

## Goal
Implement all missing critical features to reach production-ready v1.0, including security fixes, file management, UI polish, tests, and proper git workflow.

## Current State (v0.2)
- ✅ AES-256-GCM encryption with per-file keys
- ✅ PIN authentication with rate limiting
- ✅ BLoC architecture, macOS UI
- ✅ Auto-destruction service
- ❌ File picker is stub (dialog only)
- ❌ Drag & drop not implemented
- 🔴 CRITICAL: Hardcoded recovery key
- ❌ Biometric unlock not wired
- ❌ Manifest not encrypted
- ❌ No tests

---

## Phase Overview

| Phase | Focus | Est. Time | Priority |
|-------|-------|-----------|----------|
| 1 | Security Fixes | 1 day | CRITICAL |
| 2 | File Management Core | 2 days | HIGH |
| 3 | Authentication Polish | 1 day | HIGH |
| 4 | Testing Infrastructure | 2 days | HIGH |
| 5 | Advanced Features | 2 days | MEDIUM |
| 6 | Polish & Release | 1 day | MEDIUM |

---

## Detailed Phases

### Phase 1: CRITICAL Security Fixes 🔴
**Status:** ✅ COMPLETE  
**Branch:** `feat/security-fixes`

- [x] 1.1 Fix hardcoded recovery key in `main.dart:478`
  - Use `CryptoUtils.generateRecoveryKey()` instead
  - Display in setup screen
  - Add "Copy to clipboard" functionality
  - Add "I've saved it" confirmation

- [x] 1.2 Encrypt file manifest
  - Encrypt manifest with master key before writing
  - Decrypt on load
  - Handle migration from unencrypted (v0.2 → v0.3)

- [ ] 1.3 Add manifest HMAC signing (deferred to v1.1)
  - Sign manifest with master key-derived signing key
  - Verify on load
  - Tamper detection

**Deliverables:**
- Security fixes committed
- Migration path documented

---

### Phase 2: File Management Core 📁
**Status:** ✅ COMPLETE  
**Branch:** `feat/file-management`

- [x] 2.1 Implement file picker integration
  - Wire up `file_picker` package
  - Multi-file selection support
  - Error handling

- [x] 2.2 Add drag & drop support
  - `desktop_drop` package added
  - Visual drop zone overlay
  - Handle multiple files

- [ ] 2.3 Implement file preview (deferred to Phase 5)
  - Image preview (thumbnails)
  - Text file preview
  - PDF preview (basic)

- [x] 2.4 Add export/import vault
  - Export dialog with directory picker
  - Import dialog with safety confirmations (stub)
  - Warning messages for backup/restore

**Deliverables:**
- Full file management working
- UI polished

---

### Phase 3: Authentication Polish 🔐
**Status:** NOT STARTED  
**Branch:** `feat/auth-polish`

- [ ] 3.1 Wire up biometric unlock
  - Integrate `local_auth` package
  - Touch ID / Face ID flow
  - Fallback to PIN
  - Settings toggle

- [ ] 3.2 Complete recovery key flow
  - Recovery key input screen
  - Verification logic
  - Reset PIN after recovery

- [ ] 3.3 Add PIN change UI
  - Settings screen option
  - Current PIN verification
  - New PIN confirmation

- [ ] 3.4 Add keyboard shortcuts
  - ⌘L to lock
  - ⌘O to add files
  - ⌘, for settings
  - ⌘Q to quit

**Deliverables:**
- Complete auth flows
- Keyboard shortcuts working

---

### Phase 4: Testing Infrastructure 🧪
**Status:** NOT STARTED  
**Branch:** `feat/testing`

- [ ] 4.1 Unit tests for crypto
  - `CryptoUtils` tests
  - Encrypt/decrypt round-trip
  - Key wrapping/unwrapping
  - Hash verification

- [ ] 4.2 Unit tests for services
  - `CryptoService` tests
  - `KeychainService` mocks
  - `AutoDestructionService` tests

- [ ] 4.3 BLoC tests
  - `AuthBloc` state transitions
  - `VaultBloc` events
  - `SettingsBloc` configuration

- [ ] 4.4 Widget tests
  - Lock screen PIN entry
  - Vault screen file grid
  - Settings screen toggles

- [ ] 4.5 Integration tests
  - Full unlock → add file → lock flow
  - Recovery key flow
  - Export/import flow

**Deliverables:**
- 80%+ test coverage
- CI test automation

---

### Phase 5: Advanced Features ⚡
**Status:** NOT STARTED  
**Branch:** `feat/advanced`

- [ ] 5.1 Replace PBKDF2 with Argon2id
  - FFI setup for native Argon2
  - Secure memory handling
  - Migration for existing vaults

- [ ] 5.2 Add folder organization
  - Create folders in vault
  - Move files between folders
  - Folder tree navigation

- [ ] 5.3 Add tags system
  - Tag creation
  - Tag filtering
  - Color-coded tags

- [ ] 5.4 Search improvements
  - Full-text search in file names
  - Tag-based search
  - Date range filtering

**Deliverables:**
- Advanced features working
- Performance optimized

---

### Phase 6: Polish & Release 🚀
**Status:** NOT STARTED  
**Branch:** `release/v1.0`

- [ ] 6.1 UI/UX polish
  - Loading states
  - Error handling dialogs
  - Empty states
  - Animations

- [ ] 6.2 Documentation
  - Update README with new features
  - API documentation
  - Security whitepaper

- [ ] 6.3 Build & sign
  - macOS notarization setup
  - Code signing
  - DMG creation

- [ ] 6.4 Final testing
  - End-to-end testing
  - Security review
  - Performance profiling

**Deliverables:**
- v1.0 release
- Signed & notarized app

---

## Git Workflow Strategy

### Branch Structure
```
main (production-ready)
  ↑
develop (integration)
  ↑
feat/* (feature branches)
  ↑
hotfix/* (emergency fixes)
```

### Branch Naming
- `feat/feature-name` - New features
- `fix/bug-description` - Bug fixes
- `refactor/component-name` - Refactoring
- `test/component-name` - Test additions
- `docs/topic` - Documentation
- `release/vX.Y.Z` - Release preparation

### Commit Message Format
```
type(scope): subject

body

footer
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `security`

Examples:
- `security(crypto): fix hardcoded recovery key generation`
- `feat(files): add drag & drop file support`
- `test(bloc): add AuthBloc unit tests`

---

## Key Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-01-30 | Use desktop_drop for drag & drop | Best Flutter desktop support |
| 2026-01-30 | FFI for Argon2id | Native performance & security |
| 2026-01-30 | Encrypt manifest in v0.3 | Security gap identified in review |

---

## Errors Encountered

*None yet - log errors here as they occur*

---

## Status

**Phase 1: ✅ COMPLETE** - Security fixes implemented
**Phase 2: ✅ COMPLETE** - File management features implemented

**Current:** `develop` branch
**Next Action:** Start Phase 3 - Authentication Polish

**Completed so far:**
- Phase 1: Fixed hardcoded recovery key, encrypted manifest
- Phase 2: File picker, drag & drop, export vault
- Ready for Phase 3: Biometric unlock, PIN change, keyboard shortcuts

## Git Branches

- `main` - Production-ready code
- `develop` - Integration branch (current)
- `feat/security-fixes` - Phase 1 ✅
- `feat/file-management` - Phase 2 (next)
- `feat/auth-polish` - Phase 3
- `feat/testing` - Phase 4
- `feat/advanced` - Phase 5
