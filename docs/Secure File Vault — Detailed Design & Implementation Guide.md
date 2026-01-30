# Secure File Vault — Detailed Design & Implementation Guide

# Secure File Vault — Detailed Design & Implementation Guide

Version: 1.0  
Last updated: 2026-01-24  
Author: Enzo (enzomarc237) — expanded doc

Summary
-------
Secure File Vault is a macOS desktop application that provides encrypted storage for sensitive files. This document expands the project README into a full design, security architecture, implementation guidance, testing plan, build and distribution notes, data formats, and a stack comparison (React + Tauri vs Flutter + Dart) to help decide the implementation path.

Table of Contents
-----------------
- Project overview
- Goals and non-goals
- Threat model & security assumptions
- High-level architecture
- Data and cryptography design
  - Key management
  - File encryption format
  - Encryption algorithms and parameters
  - Integrity verification
  - Secure deletion/crypto-shredding
  - Backups and migration
- Authentication & UX flows
  - PIN flow, rate-limiting, lockout
  - Biometric integration (planned)
  - Recovery options and account recovery policies
- Auto-destruction (remote trigger) design & security
- Native macOS integration & entitlements
- Persistence, metadata, and storage
- UI/UX and accessibility
- Logging, telemetry, and privacy
- Testing strategy (unit, integration, security testing)
- CI/CD, notarization, code signing
- Configuration & settings screen reference
- Developer setup and build steps
- Known risks and mitigations
- Roadmap
- Stack comparison: React + Tauri vs Flutter + Dart
- Appendix: file format spec, sample manifest schema, recommended libs & references

Project overview
----------------
Secure File Vault provides:
- Encrypted storage (AES-256 AEAD) for arbitrary file types.
- PIN-based authentication (configurable), with support for biometric unlock planned.
- Auto-lock & auto-logout on unfocus or inactivity.
- Configurable maximum login attempts with lockout.
- Secure deletion by crypto-shredding (with considerations for SSD/APFS).
- File integrity verification and per-file metadata.
- Auto-destruction on remote trigger (configurable URL + interval) with secure wipe behavior.
- Native macOS UI (using macos_ui if implemented in Flutter) and system tray integration.

Goals
-----
- Strong, auditable cryptographic protections for files at rest.
- Minimal attack surface for exfiltration or local compromise.
- Reasonable usability for non-technical users.
- Auditable and extensible architecture for future features (biometrics, cloud sync).

Non-goals
---------
- A cloud-first sync solution (out of scope for initial release).
- Full-disk encryption replacement.
- Attempting to physically sanitize SSD internals — rely on crypto-shredding.

Threat model & security assumptions
----------------------------------
Assumptions:
- Attacker may obtain physical access to the device or a copy of the user’s files (e.g., from backup).
- OS is not fully compromised. If attacker has kernel-level or Secure Enclave compromise, there are limits to what the app can guarantee.
- Transport channels for remote triggers must be protected by TLS; we assume TLS endpoints are otherwise uncompromised.

Threats:
- Brute-forcing the vault via PIN guessing.
- Local privilege escalation to read key material from process memory, temp files, or unencrypted backups.
- Remote code or UI injection (if using web view).
- Man-in-the-middle on the auto-destruction trigger.

Mitigations:
- Rate-limiting and lockout on login attempts.
- Use of AEAD ciphers (AES-GCM or ChaCha20-Poly1305) to provide confidentiality + integrity.
- Use Keychain + Secure Enclave for storing long-lived keys or key-wrapping keys.
- Avoid writing plaintext to disk; clear in-memory secrets promptly and use secure zeroing APIs.
- Implement TLS + certificate pinning for remote trigger or signed triggers.

High-level architecture
-----------------------
- Presentation layer (UI): macOS-native window, system tray/NSStatusItem, settings UI.
- Application layer: BLoC (or equivalent) for state management, authentication logic, configuration.
- Core/Security layer:
  - Encryption service (file encrypt/decrypt)
  - Key manager (master key, per-file keys, Keychain wrapper)
  - Secure deletion service
  - Remote destruction service
- Persistence: Encrypted manifest & metadata store (sqlite or JSON) stored inside vault folder (encrypted fields only)
- Repositories:
  - FileRepository: reads/writes encrypted file blobs
  - SettingsRepository: stores configuration securely (Keychain for secrets, encrypted file for sensitive settings)
- Interop: platform adapters (Keychain, LocalAuthentication, file watcher)

Data & cryptography design
--------------------------

Design goals:
- Use authenticated encryption (AEAD).
- Keep secrets off disk whenever possible.
- Avoid deterministic keys for different files—use per-file keys and authenticated metadata.

Recommended cryptographic primitives (strongly advised)
- AEAD: AES-256-GCM or ChaCha20-Poly1305 (use AES-GCM if hardware AES acceleration is available; otherwise ChaCha20-Poly1305 is acceptable)
- Key derivation for PIN/passphrase: Argon2id (recommended) or PBKDF2-HMAC-SHA256 with high iterations if Argon2 not available in platform libs.
- Random: Cryptographically secure RNG (SecRandomCopyBytes on macOS).
- HSM/SE: Use Secure Enclave where possible for storing wrapping keys or unlocking via biometrics.

Master key model (recommended)
- MasterKey: a high-entropy 256-bit symmetric key used to wrap per-file keys and sign/derive keys for metadata.
- Key storage options (recommend hybrid approach):
  - Primary: Store MasterKey wrapped by a Key Encryption Key (KEK) bound to Secure Enclave/Keychain; the KEK is unlocked via biometrics or system Keychain unlock policies.
  - Secondary: For PIN-only flows without Secure Enclave, derive a KEK from the user PIN with Argon2id and use it to decrypt the stored MasterKey (which is itself encrypted and persisted).
- Protecting the master key:
  - Always store encrypted/ wrapped master key on disk.
  - Minimize time master key exists in process memory. Zero memory after use.

Per-file encryption
- For every file:
  - Generate a new random FileKey (256-bit).
  - Encrypt file content with AEAD (AES-GCM or ChaCha20-Poly1305) using a fresh nonce/IV per encryption (recommended 96-bit nonce for AES-GCM).
  - Wrap FileKey with the MasterKey using AES-KW (RFC 3394) or an AEAD-based key-wrapping scheme.
- Store per-file metadata header alongside ciphertext with:
  - Format version
  - Wrapped file key
  - File encryption algorithm, mode, key derivation params
  - Nonce/IV
  - AEAD tag (embedded in GCM output)
  - Optional per-file signing/verification data (signature or HMAC)
  - Encrypted file name or a hashed filename to prevent leakage of original names (optional)
- Example on-disk layout:
  - <vault-file-header> (JSON or binary protobuf, encrypted or partially plaintext)
  - <ciphertext blob>

File header considerations
- Minimal plaintext metadata so attackers cannot enumerate file types or names.
- If filenames must be stored, store them encrypted or hashed with HMAC keyed by MasterKey.
- Include version number for future algorithm migrations.

Integrity verification
- Use AEAD; that provides integrity checks on decryption.
- Maintain an optional signed manifest (e.g., manifest.json) that contains file metadata and a hash of each file’s ciphertext (SHA-256). Sign manifest with MasterKey-derived signing key or an asymmetric key pair kept in Secure Enclave for tamper-detection.
- Manifest should be encrypted or at least authenticated.

Secure deletion (crypto-shredding)
- On modern SSDs/APFS, multiple overwrites are unreliable due to wear-leveling and snapshots. Instead:
  - Crypto-shredding: delete the file’s wrapped file key (or entirely reencrypt it with a different random key and discard old key). Without the file key, ciphertext is unrecoverable.
  - Remove any plaintext copies, temp files, thumbnails; overwrite in-memory buffers and zero them.
  - Delete associated Keychain items (SecItemDelete).
  - If desired, also attempt filesystem-level {ftruncate, unlink} to reduce exposure, but do not rely on overwrites.
- If a user requests "securely delete all files" (auto-destruction), perform crypto-shred of all file keys and securely delete the wrapped master key(s).

Key rotation & migration
- Support re-wrapping of file keys when rotating MasterKey.
- Provide a migration tool to re-encrypt files with new algorithms or parameters.
- Maintain a chain-of-trust and versioning to support rollback or debugging.

Memory handling
- Use platform primitives to mark memory non-swappable where possible.
- Zero secrets after use (explicit buffer zero).
- Avoid creating extra copies of plaintext data. Stream encrypt/decrypt large files rather than loading whole file into memory.

Authentication & UX flows
------------------------
PIN-based authentication
- Minimum PIN length: configurable (recommend default 6 digits).
- PIN storage: never store PIN plaintext. Use it only for deriving KEK via Argon2id to unwrap the MasterKey, or use it to authenticate unlocking the Keychain item with the MasterKey.
- Rate-limiting: exponential backoff + lockout after configurable maximum attempts.
  - Default parameters (example):
    - Max attempts: 10
    - Initial lockout: 30 seconds
    - Lockout multiplier: x2 per additional attempt after threshold
    - Wipe option: optional, user can enable "wipe after N failed attempts" (dangerous — clearly surface UI warnings)
- Brute-force hardening: use Argon2id with high memory/time cost to make offline brute forcing expensive.

Session & auto-logout
- Idle timeout: configurable (e.g., 5 minutes default).
- Auto-lock on app unfocus/background/resignActive: immediate or after configurable grace period.
- Option to require full PIN on re-auth or allow short reauthenticate by biometrics if enabled.

Biometric integration (planned)
- macOS LocalAuthentication: Touch ID / Face ID (where available).
- Recommended flow: use biometric to unlock the Keychain-wrapped MasterKey (i.e., Keychain entry with access control set to kSecAccessControlBiometryAny | kSecAccessControlPrivateKeyUsage).
- Provide fallback to PIN if biometric unavailable.
- Do not store biometric data in app; rely on OS.

Recovery options
- Provide a "recovery key" (user written down) or an optional encrypted cloud escrow (out of scope for initial release).
- Recovery key should be high entropy (e.g., 32 bytes base58/base32) and used to unwrap MasterKey.
- Warn users about recovery trade-offs and that recovery keys must be stored separately.

Auto-destruction (remote trigger)
--------------------------------
Features
- Periodically poll a configured URL (HTTPS) at a configurable interval for a trigger (e.g., JSON payload or signed token).
- When trigger is validated, perform secure full vault wipe.

Security considerations
- Use HTTPS and require TLS verification.
- Use signature verification (HMAC or asymmetric signatures) on trigger messages to prevent MITM/triggers from unauthorized parties.
- Prefer push: if supporting remote push (out of scope initially), ensure strong authentication and rate-limiting.
- Use certificate pinning or pinned public keys to prevent TLS MITM.
- Implement back-off and fail-safe: if the URL becomes unreachable, do not auto-destroy without a valid signature.
- Logging: record last successful check time and last trigger verification result in logs (avoid logging secrets).

Auto-destruction behavior
- Crypto-shred MasterKey wrappers and remove Keychain items.
- Delete (unlink) vault files and manifest.
- Overwrite in-memory key structs and clear caches.
- Optionally show a notification before final wipe (configurable and depends on use case).
- If remote trigger is set by user, require additional confirmation when first setting the URL, and allow a grace window in which the user can disable or rotate the trigger.

Native macOS integration & entitlements
--------------------------------------
Entitlements / Signing
- Hardened runtime enabled.
- Code signing and notarization required for distribution outside dev.
- Entitlements to use:
  - com.apple.security.app-sandbox if sandboxing is desired (but Keychain/LocalAuthentication APIs work with sandboxing with appropriate entitlements)
  - com.apple.security.application-groups (only if shared containers used)
  - com.apple.developer.user-selected-file.read-write (if using Powerbox)
- Keychain and LocalAuthentication use standard macOS frameworks (no special entitlements beyond sandboxing considerations).

System integration
- Use NSStatusItem for tray/status bar (or equivalent with macos_ui plugin).
- Start at login: implement via Launch Agent OR Service Management API (SMLoginItemSetEnabled) for helper apps. Implement an opt-in setting and explain privacy concerns.

Persistence, metadata, and storage
--------------------------------
Vault layout (example)
- Vault root (user configurable):
  - manifest.enc (encrypted manifest that lists files and minimal metadata)
  - files/ (encrypted file blobs with headers)
  - config.enc (encrypted configuration if contains secrets)
  - logs/ (local logs, non-sensitive only; avoid logging secrets)
  - .lock (file indicating current lock state; cleared on unlock)

Manifest
- Contains per-file entries (id, encrypted filename hash, ciphertext hash, size, encrypted metadata, created_at, updated_at).
- Manifest is signed and/or AEAD-protected by MasterKey.

File names
- For privacy, do not store cleartext filenames in the open file system — either:
  - Encrypt filenames and store mapping in manifest.
  - Use random UUID filenames on disk and keep mapping in encrypted manifest.

UI/UX and accessibility
----------------------
Design principles
- Clear status: locked/unlocked, last sync/check with auto-destruction endpoint, last backup.
- Fail-safe defaults: require explicit opt-ins for destructive options.
- Simple settings for non-technical users; advanced settings for power users.

Accessibility
- Support VoiceOver, keyboard navigation, high-contrast modes.
- Make PIN entry accessible with labels and visible focus.

Internationalization
- Localize strings; design using standard Flutter/i18n or web i18n pipeline.

Logging, telemetry, and privacy
-------------------------------
- Avoid collecting or transmitting file metadata or filenames to remote servers.
- If telemetry used, make it opt-in and strictly non-sensitive (no file names, contents).
- Local logs: redact or avoid storing anything sensitive (PIN attempts, exact failure reasons).
- Audit logs: store only timestamps and high-level events (unlock, lock, auto-destroy invoked).

Testing strategy
----------------
Unit tests
- Cryptography primitives (encrypt/decrypt round-trip), KDF and Argon2 params, header parsing.
- Key wrapping and unwrapping.

Integration tests
- Simulated upgrade/migration scenarios.
- Auto-lock/unfocus to ensure no plaintext files persist.

Security testing
- Threat modeling and manual code review of all boundary code.
- Static analysis (SAST) and secret scanning in CI.
- Dependency scanning: check for vulnerable packages (SCA).
- Fuzzing of file parser and manifest interpreter.
- Optional third-party security audit for cryptographic correctness.

Performance testing
- Large file streaming encryption/decryption tests.
- Memory usage under multiple concurrent decrypt operations.

CI/CD, notarization, code signing
--------------------------------
- GitHub Actions with macOS runners for building and packaging.
- Steps:
  - Run tests
  - Build macOS release (flutter build macos or equivalent)
  - Code sign binary
  - Notarize using notarytool or Apple altool
  - Package into .pkg or .dmg
- Keep signing credentials in secure secrets store (GitHub Secrets).
- For Tauri/Rust alternative, configure cargo build and required notarization steps.

Configuration & settings screen reference
-----------------------------------------
Settings (recommended entries)
- Vault location (path)
- Auto-logout duration (seconds/minutes) — default 300 seconds
- Maximum login attempts — default 10
- Lockout policy (exponential backoff toggle)
- Wipe after N failed attempts — default disabled and must show confirmation
- Auto-destruction:
  - URL (HTTPS)
  - Interval (minutes/hours)
  - Verification mode: signed (recommended) / unsigned
  - Last checked (read-only)
- Biometric unlock: enabled/disabled
- Start at login: enabled/disabled
- System integration: show in menu bar / show badge
- Backup: export encrypted vault / import encrypted vault
- About / License / Version

Developer setup & build steps
----------------------------
Prerequisites
- macOS 10.15+
- Xcode 14+
- Flutter 3.7+ (if using Flutter)
- Rust & Node/npm (if using Tauri)
- Apple Developer account for signing/notarization

Flutter (example)
1. Clone repository:
   git clone https://github.com/enzomarc237/crypto-vault-macos.git
   cd crypto-vault-macos
2. Install deps:
   flutter pub get
3. Run:
   flutter run -d macos
4. Build release:
   flutter build macos
   (signed & notarize afterwards)

Tauri (example)
1. Clone repo; run Node-based UI build (React) and Tauri build steps with Rust toolchain.
2. Build release via Tauri commands; sign and notarize.

Known risks & mitigations
------------------------
- Risk: Storing filenames exposes sensitive info. Mitigation: encrypt filenames; use UUID mapping in manifest.
- Risk: SSD makes secure deletion unreliable. Mitigation: use crypto-shredding.
- Risk: Remote auto-destruction abused by attacker. Mitigation: enforce signed triggers & certificate pinning; require explicit user setup; provide logs and grace period.
- Risk: In-memory secrets after crash. Mitigation: zero memory on close; do not store secrets in swap (mark pages non-swappable when possible).
- Risk: UI injection (web view). Mitigation: use Flutter (compiled) or Tauri with strict CSP and disable remote code injection.

Roadmap
-------
- v0.1: Core AES-GCM encryption, PIN-based unlock, manifest, per-file encryption, auto-lock on unfocus, basic UI.
- v0.2: Keychain integration, Argon2 KDF, improved settings, secure deletion (crypto-shred).
- v0.3: Biometric unlock via Secure Enclave, manifest signing, backups.
- v1.0: Notarized release, full testing & security audit.
- Future: Cloud escrow, multi-device sync with E2E encryption, folder watchers, remote push/destruct.

Stack comparison: React + Tauri vs Flutter + Dart
------------------------------------------------

Summary recommendation (short)
- If you want a macOS-first native-feel app with strong support for platform APIs (Keychain, LocalAuthentication) and you prefer a single UI language with a large plugin ecosystem targeted at mobile & desktop, Flutter + Dart is likely the most productive.
- If your team is web-first, prioritizes small binaries, and is comfortable writing Rust for native bridging (and can accept the extra integration work to access some macOS-specific APIs), React + Tauri is a strong alternative.

Detailed comparison
- Language & ecosystem
  - React + Tauri:
    - UI: React (JS/TS) + HTML/CSS; huge ecosystem, fast iteration for web developers.
    - Native layer: Tauri (Rust) — provides a small, secure core that interacts with OS APIs via Rust plugins.
    - Strength: reuses web skillset and many npm packages.
    - Drawback: accessing some native macOS services (Secure Enclave, Keychain, LocalAuthentication) requires Rust bridge code or native bindings; developers may need to write/maintain Rust plugins.
  - Flutter + Dart:
    - UI: Flutter's Skia-based rendering or macOS-specific plugins (macos_ui) for native look-and-feel.
    - Native layer: Dart FFI or platform channels to talk to Swift/Objective-C for macOS APIs.
    - Strength: unified codebase for UI & logic, good hot-reload, plugin ecosystem growing (flutter_secure_storage, local_auth, etc).
    - Drawback: app binary and memory footprint can be larger than Tauri.

- Native OS integration & APIs
  - React + Tauri:
    - Tauri can call native Rust code for deep integration. Requires Rust expertise to call Secure Enclave or Keychain frameworks (via bindings).
    - Webview UI runs in OS-provided webview (WebKit on macOS), which can lead to CSP/XSS concerns unless UI is static & hardened.
  - Flutter + Dart:
    - Easier to call native macOS APIs via platform channels or plugins; a lot of cross-platform packages exist but macOS-specific support might need custom plugins.
    - Flutter apps can present a highly native feel (using macos_ui) with less bridging code for common patterns.

- Security surface
  - React + Tauri:
    - UI is HTML/JS; if UI uses remote content or loads dynamic content, risk of XSS or remote injection. Use strict CSP and offline-first packaging.
    - Tauri Rust core is small and focuses on reducing attack surface.
    - Writing cryptography in Rust can be a plus (memory safety, high-quality crypto crates).
  - Flutter + Dart:
    - UI is compiled, less exposed to DOM-based XSS.
    - Must ensure 3rd-party Dart packages are safe; cryptography in Dart is good but non-native C/Rust libs can outperform.
    - For heavy crypto, Flutter can call native C/Rust libs via FFI.

- Binary size & resource usage
  - React + Tauri:
    - Tauri produces extremely small native binaries (Rust core + web assets). Web assets size is major portion but can be optimized.
    - Memory: webview may be more lightweight than embedding a Flutter engine for simple apps.
  - Flutter + Dart:
    - Flutter apps embed the Dart VM & engine; binary size tends to be larger.
    - Runtime memory usage is typically higher than a lightweight Tauri app.

- Performance
  - React + Tauri:
    - Application logic in JS; CPU-intensive crypto should be done in Rust for performance.
    - Best for apps where UI is not animation-heavy.
  - Flutter + Dart:
    - High-performance UI; running compute in Dart is fine for many workloads; for high-performance crypto you can use FFI to native libs.
    - Flutter’s rendering is very smooth, good for custom UIs.

- Development ergonomics
  - React + Tauri:
    - Web hot-reload and web stack tools accelerate UI development.
    - Need Rust + JS toolchains; bridging needed for native features.
  - Flutter + Dart:
    - Single-language stack with hot-reload for UI and iterative dev experience.
    - Flutter plugin ecosystem for mobile & desktop reduces integration effort.

- Plugin & library availability for security features
  - Keychain, Secure Enclave, LocalAuthentication:
    - Flutter: plugins like local_auth, flutter_secure_storage (but ensure macOS support), or implement platform channels to call Keychain APIs.
    - Tauri: require Rust crates or write Rust code to call Apple frameworks.
  - Cryptography:
    - Rust: excellent crypto crates (ring, rust-crypto, libsodium bindings).
    - Dart: packages exist (pointycastle, cryptography) and you can use FFI to libsodium or libs in Rust/C.

- Packaging & distribution (macOS specifics)
  - Both approaches require code signing, notarization, and packaging.
  - Tauri advantages: typically smaller bundle to notarize.
  - Flutter: larger binary but stable tooling for building macOS apps.

- Maintainability & team fit
  - Choose based on the team's language expertise:
    - If team is web-centric -> React + Tauri.
    - If team is mobile/Flutter-savvy or wants one codebase which could target other platforms -> Flutter + Dart.

- Security posture recommendation for Secure File Vault
  - If cryptography is a core part of the app and you prefer memory-safety and performance for crypto primitives, Tauri with Rust implementations could be excellent for crypto internals, and a React UI for front-end.
  - If you want faster integration with existing Flutter ecosystem (macos_ui, flutter_bloc, flutter_secure_storage), quicker UI development, and a more “native” compiled UI, Flutter is the pragmatic choice.
  - Hybrid approach: use Flutter UI + call Rust via FFI for crypto (or write native C wrapper) — gives best crypto performance + Flutter UX, but adds complexity.

Recommendation (project-specific)
- For Secure File Vault targeted for macOS with deep integration (Keychain, LocalAuthentication) and need for a polished native look and fast development: choose Flutter + Dart.
- If the primary team is web-focused and prioritizes minimal binary size or you want to write crypto in Rust for stronger memory-safety guarantees, choose React + Tauri with Rust native plugins for critical crypto and Keychain access.
- If security is the top priority and you can maintain a Rust codebase, prefer Tauri + Rust for crypto + web UI, or implement crypto in Rust and expose bindings to Flutter if you want the Flutter UI.

Appendix: file format spec (example)
-----------------------------------
Vault file on disk: files/<file-uuid>.vfile

Binary layout (high-level)
- Header (fixed length or length-prefixed JSON):
  - version: 1
  - wrapped_key: base64(wrap(MasterKey, FileKey))
  - alg: "AES-256-GCM"
  - nonce: base64(12 bytes)
  - metadata: base64(encrypted metadata JSON) or pointer into manifest
- Ciphertext (remaining bytes)
- AEAD Tag included as per algorithm (e.g., appended 16 bytes for AES-GCM)

Manifest (manifest.enc)
- Encrypted JSON array keyed by MasterKey:
  - file_id: uuid
  - filename_hmac: base64(HMAC(MasterKey_filename_key, filename))
  - cipher_hash: hex(SHA-256(ciphertext))
  - created_at: ISO8601
  - size: bytes
  - wrapped_key_info: (optional redundancy)
- Manifest is stored as AEAD-encrypted blob and may be signed.

Sample manifest entry (plaintext example before encryption)
{
  "file_id": "a7f8e0c0-...",
  "filename_hmac": "b3a2...",
  "cipher_hash": "e3b0c44298...",
  "size": 1048576,
  "created_at": "2026-01-24T12:00:00Z"
}

Recommended libraries & tooling
------------------------------
- Flutter:
  - macos_ui (UI)
  - flutter_bloc (state management)
  - cryptography (Dart crypto primitives) or use ffi to libsodium
  - local_auth (for biometric)
  - flutter_secure_storage or custom Keychain plugin for macOS
  - file_picker (optional)
- Rust (if using Tauri or native crypto):
  - ring or rust-crypto or libsodium via sodiumoxide for crypto primitives
  - keyring or security-framework crate for Keychain integration
- Tauri:
  - Tauri core (Rust) + React/Next/CRA as web UI
- Testing & CI:
  - GitHub Actions (macOS runners)
  - SAST: semgrep, cargo-audit, npm audit
  - Dependency scanning: OWASP Dependabot

References & further reading
- Apple Developer docs: Keychain Services, LocalAuthentication, Notarization
- RFCs for AEAD / AES-GCM, AES Key Wrap (RFC 3394)
- Argon2 specification
- APFS & SSD secure deletion considerations
- OWASP guidance on secure storage & cryptography (general best practices)

Contributing & governance
-------------------------
- Follow the contributing steps:
  1. Fork the repo
  2. Create feature branch (feature/...)
  3. Run tests locally
  4. Open PR with description and mention security review for changes to crypto
- All proposed changes to crypto, key management, or manifest structure MUST include:
  - Design rationale
  - Tests (unit + integration)
  - Migration plan for existing data

License
-------
MIT (see LICENSE file in repo)

Changelog / Notes
-----------------
- This document is an expanded design companion to the README and should be kept updated as implementation details (algorithms, KDF params, manifest schema) evolve.
- Any cryptography changes must be approved via PR and include migration tooling for existing vaults.

What's next (practical steps)
-----------------------------
1. Choose the stack (React + Tauri or Flutter + Dart) based on team skill and the trade-offs above.
2. Implement minimal PoC:
   - Create CLI tool or simple app that:
     - Generates MasterKey
     - Encrypts a sample file with AES-GCM using per-file key
     - Wraps file key with MasterKey
     - Stores a small manifest
     - Demonstrates crypto-shredding by deleting wrapped keys
3. Expand to full UI, Keychain integration, and tests; schedule external security review before v1.0 release.

If you want, I can:
- Generate a ready-to-commit Secure File Vault.md file with the content above (formatted for repo).
- Produce a recommended PoC implementation plan (step-by-step) for either Flutter or Tauri.
- Draft a manifest schema as a JSON Schema and a simple reference implementation (encrypt/decrypt CLI in Rust or Dart).

Which of those would you like next?