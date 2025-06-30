# Publishing Guide for SelectFileCLI

This guide explains how to publish SelectFileCLI to PyPI (Python Package Index).

## Prerequisites

1. **PyPI Account**: Create an account at https://pypi.org
2. **Test PyPI Account** (optional): Create an account at https://test.pypi.org
3. **API Token**: Generate an API token from your PyPI account settings

## Setting Up Authentication

### Option 1: Using uv (Recommended)

Configure your PyPI credentials for uv:

```bash
# Set PyPI token as environment variable
export UV_PUBLISH_TOKEN="pypi-your-token-here"

# Or use keyring for secure storage
uv publish --username __token__ --keyring
```

### Option 2: Using .pypirc file

Create `~/.pypirc` with your credentials:

```ini
[distutils]
index-servers =
    pypi
    testpypi

[pypi]
repository = https://upload.pypi.org/legacy/
username = __token__
password = pypi-your-token-here

[testpypi]
repository = https://test.pypi.org/legacy/
username = __token__
password = pypi-your-test-token-here
```

## Publishing Process

### 1. Update Version

Edit `pyproject.toml` and update the version:

```toml
[project]
version = "0.3.1"  # Increment as needed
```

### 2. Build the Package

```bash
# Clean previous builds
rm -rf dist/

# Build with uv
uv build
```

### 3. Test on TestPyPI (Optional)

```bash
# Upload to TestPyPI
uv publish --publish-url https://test.pypi.org/legacy/

# Test installation
pip install -i https://test.pypi.org/simple/ selectfilecli
```

### 4. Publish to PyPI

```bash
# Publish with uv
uv publish

# Or with twine
pip install twine
twine upload dist/*
```

### 5. Verify Installation

```bash
# Install from PyPI
pip install selectfilecli

# Test it works
python -c "from selectfilecli import select_file; print('Success!')"
```

## Version Management

Follow semantic versioning (https://semver.org/):
- **MAJOR** (1.0.0): Incompatible API changes
- **MINOR** (0.4.0): Add functionality (backwards compatible)
- **PATCH** (0.3.1): Bug fixes (backwards compatible)

## Automated Publishing

You can automate publishing using GitHub Actions. See `.github/workflows/publish.yml`.

## Post-Publishing Checklist

- [ ] Tag the release in git: `git tag v0.3.0`
- [ ] Push tags: `git push --tags`
- [ ] Create GitHub release with changelog
- [ ] Update project documentation
- [ ] Announce release (if applicable)

## Troubleshooting

### "Package already exists" Error
- You cannot re-upload the same version
- Increment the version number and rebuild

### Authentication Failed
- Ensure you're using `__token__` as username
- Check your API token is correct and active
- Verify token permissions include upload rights

### Build Issues
- Ensure all tests pass: `uv run pytest`
- Check linting: `uv run ruff check`
- Verify metadata in `pyproject.toml`