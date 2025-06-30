# Release Process for SelectFileCLI

This document outlines the complete release process for publishing new versions of SelectFileCLI.

## Release Types

- **Patch Release** (0.3.0 → 0.3.1): Bug fixes, documentation updates
- **Minor Release** (0.3.0 → 0.4.0): New features, backwards compatible
- **Major Release** (0.3.0 → 1.0.0): Breaking changes

## Pre-Release Checklist

- [ ] All tests pass: `uv run pytest`
- [ ] Linting passes: `uv run ruff check`
- [ ] Coverage ≥ 80%: Check test output
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] No uncommitted changes: `git status`

## Release Methods

### Method 1: Automated GitHub Workflow (Recommended)

1. Go to GitHub Actions → "Create Release" workflow
2. Click "Run workflow"
3. Enter version number (e.g., "0.3.1")
4. Add release notes (optional)
5. Click "Run workflow"

This will automatically:
- Update version in pyproject.toml
- Run tests
- Create git tag
- Build packages
- Create GitHub release
- Trigger PyPI publish (if configured)

### Method 2: Local Release with Script

1. **Update version:**
   ```bash
   ./bump-version.sh patch  # or minor/major
   ```

2. **Review and commit:**
   ```bash
   git diff pyproject.toml
   git add pyproject.toml
   git commit -m "chore: bump version to 0.3.1"
   ```

3. **Create tag:**
   ```bash
   git tag -a v0.3.1 -m "Release v0.3.1"
   ```

4. **Push changes:**
   ```bash
   git push origin main
   git push origin v0.3.1
   ```

5. **Build and publish:**
   ```bash
   uv build
   uv publish
   ```

### Method 3: Manual Process

1. **Update version in pyproject.toml:**
   ```toml
   version = "0.3.1"
   ```

2. **Update CHANGELOG.md:**
   ```markdown
   ## [0.3.1] - 2024-06-30
   ### Fixed
   - Bug fixes...
   ```

3. **Commit changes:**
   ```bash
   git add pyproject.toml CHANGELOG.md
   git commit -m "chore: prepare release v0.3.1"
   ```

4. **Create and push tag:**
   ```bash
   git tag -a v0.3.1 -m "Release v0.3.1"
   git push origin main --follow-tags
   ```

5. **Build packages:**
   ```bash
   rm -rf dist/
   uv build
   ```

6. **Upload to PyPI:**
   ```bash
   uv publish
   # or
   twine upload dist/*
   ```

## Post-Release Tasks

- [ ] Verify PyPI page: https://pypi.org/project/selectfilecli/
- [ ] Test installation: `pip install selectfilecli=={version}`
- [ ] Create GitHub release if not automated
- [ ] Update project boards/issues
- [ ] Announce release (if applicable)

## Troubleshooting

### Build Failures
```bash
# Clean build artifacts
rm -rf dist/ build/ *.egg-info
# Retry build
uv build
```

### Tag Already Exists
```bash
# Delete local tag
git tag -d v0.3.1
# Delete remote tag
git push origin :refs/tags/v0.3.1
# Recreate tag
git tag -a v0.3.1 -m "Release v0.3.1"
```

### PyPI Upload Failed
- Check credentials in ~/.pypirc or UV_PUBLISH_TOKEN
- Ensure version doesn't already exist on PyPI
- Try test.pypi.org first

## Version History Format

Follow semantic versioning and keep track in CHANGELOG.md:

```markdown
## [0.3.1] - 2024-06-30
### Added
- New feature X

### Changed
- Updated Y behavior

### Fixed
- Bug in Z component

### Security
- Patched vulnerability in dependency
```

## Emergency Rollback

If a bad release is published:

1. **Yank from PyPI** (marks as unsafe):
   ```bash
   pip install twine
   twine yank selectfilecli=={version}
   ```

2. **Fix issues and release patch:**
   ```bash
   ./bump-version.sh patch
   # Fix issues...
   # Release new version
   ```

Note: You cannot delete or reupload the same version to PyPI.