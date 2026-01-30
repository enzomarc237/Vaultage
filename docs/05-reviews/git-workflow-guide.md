# Git Workflow Guide

## Branch Strategy: Git Flow (Simplified)

```
main (production)
  ↑
develop (integration)
  ↑
feat/* (features)
fix/* (bugfixes)
refactor/* (refactoring)
```

---

## Setup Commands

### Initialize Workflow
```bash
# Create develop branch
git checkout -b develop

# Push to remote
git push -u origin develop
```

### Feature Branch Workflow
```bash
# Start new feature
git checkout develop
git pull origin develop
git checkout -b feat/feature-name

# Work on feature...
git add .
git commit -m "feat(scope): description"

# Push feature branch
git push -u origin feat/feature-name

# Create PR to develop (via GitHub/GitLab)
# After merge, cleanup
git branch -d feat/feature-name
git push origin --delete feat/feature-name
```

---

## Commit Message Convention

### Format
```
type(scope): subject

body (optional)

footer (optional)
```

### Types
| Type | Use For |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `security` | Security fix |
| `refactor` | Code restructuring |
| `test` | Adding tests |
| `docs` | Documentation |
| `chore` | Maintenance |

### Scopes
- `crypto` - Cryptography
- `auth` - Authentication
- `files` - File management
- `ui` - User interface
- `bloc` - State management
- `deps` - Dependencies

### Examples
```
security(recovery): fix hardcoded recovery key generation

Use CryptoUtils.generateRecoveryKey() instead of static string.
Added copy-to-clipboard functionality.

Closes #1
```

```
feat(files): add drag & drop file support

- Integrate desktop_drop package
- Add visual drop zone overlay
- Support multiple file selection
- Show progress during encryption
```

---

## Branch Protection Rules

### main
- [ ] Require pull request reviews (1)
- [ ] Require status checks (CI tests)
- [ ] Require linear history
- [ ] No force push
- [ ] No deletion

### develop
- [ ] Require pull request reviews (1)
- [ ] Require status checks (CI tests)
- [ ] Allow force push (for cleanup)

---

## Release Process

### Prepare Release
```bash
# Checkout develop
git checkout develop
git pull origin develop

# Create release branch
git checkout -b release/v1.0.0

# Update version in pubspec.yaml
# Update CHANGELOG.md

git add .
git commit -m "chore(release): prepare v1.0.0"
```

### Finalize Release
```bash
# Merge to main
git checkout main
git merge release/v1.0.0 --no-ff
git tag -a v1.0.0 -m "Release v1.0.0"

# Merge back to develop
git checkout develop
git merge release/v1.0.0 --no-ff

# Cleanup
git branch -d release/v1.0.0
```

---

## Hotfix Process

```bash
# Create hotfix from main
git checkout main
git pull origin main
git checkout -b hotfix/critical-fix

# Fix the issue...
git add .
git commit -m "fix(scope): critical fix description"

# Merge to both branches
git checkout main
git merge hotfix/critical-fix --no-ff
git tag -a v1.0.1 -m "Hotfix v1.0.1"

git checkout develop
git merge hotfix/critical-fix --no-ff

# Cleanup
git branch -d hotfix/critical-fix
```

---

## CI/CD Integration

### GitHub Actions Workflow
```yaml
name: CI
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.7.0'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build macos
```

---

## Current Branches Setup

### Phase 1: Security Fixes
```bash
git checkout develop
git checkout -b feat/security-fixes
```

### Phase 2: File Management
```bash
git checkout develop
git checkout -b feat/file-management
```

### Phase 3: Auth Polish
```bash
git checkout develop
git checkout -b feat/auth-polish
```

### Phase 4: Testing
```bash
git checkout develop
git checkout -b feat/testing
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Start feature | `git checkout -b feat/name develop` |
| Start fix | `git checkout -b fix/name develop` |
| Sync with develop | `git pull origin develop` |
| Push branch | `git push -u origin branch-name` |
| Delete local branch | `git branch -d branch-name` |
| Delete remote branch | `git push origin --delete branch-name` |
| Tag release | `git tag -a v1.0.0 -m "message"` |
| Push tags | `git push origin --tags` |
