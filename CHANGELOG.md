# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Docker testing environment with multi-stage Dockerfile
- Docker Compose profiles for test, lint, dev, build, and production
- Comprehensive test suite achieving 93.92% coverage
- GitHub Actions workflows (lint, test, build, check, publish, release)
- Pre-commit hooks configuration with uv
- Version bumping script (bump-version.sh)
- Publishing documentation (PUBLISHING.md)
- Release process documentation (RELEASE_PROCESS.md)
- Build summary documentation
- Test environment detection for Docker and CI
- Missing @pytest.mark.asyncio decorators for async tests

### Changed
- Improved project documentation structure
- Enhanced README with professional badges and examples
- Updated all snapshot tests to current UI state
- Formatted all code with ruff for consistency

### Fixed
- Async test failures due to missing decorators
- Snapshot test failures after UI updates
- Docker volume mounting issues for read-only testing

## [0.3.0] - 2025-01-29

### Added
- Modal sort dialog with radio button selection for sort modes and order
- Visual indicators for sort order (↓ for ascending, ↑ for descending)
- Support for multiple sort modes: Name, Creation Date, Last Accessed, Last Modified, Size, Extension
- Comprehensive test suite with SVG snapshot testing
- 80% test coverage achieved

### Changed
- Replaced cycling sort mode (repeatedly pressing 's') with unified sort dialog
- Simplified footer to show only essential commands (Q-Quit, S-Sort)
- Updated all tests to work with new dialog-based interaction

### Removed
- Individual sort shortcuts (n, d, z, e, o) - all sorting now through dialog
- Sort status display in main UI - now only visible in dialog

### Fixed
- TypeError when DirectoryTree nodes contained DirEntry objects
- ReactiveError when using reactive decorators before initialization
- AttributeError on non-existent super() method

## [0.2.0] - 2025-01-29

### Added
- Textual-based TUI implementation replacing raw terminal control
- Path display showing currently highlighted file/directory
- Keyboard navigation with arrow keys
- File selection with Enter key
- Cancel operation with Q or Escape keys

### Changed
- Complete rewrite using Textual framework for better cross-platform support
- Improved visual appearance with borders and styled components

## [0.1.0] - 2025-01-28

### Added
- Initial release
- Basic file browser functionality using raw terminal control
- Navigate directories with arrow keys
- Select files with Enter key
- Cancel with 'q' key
- Simple API: `select_file(start_path)`

[Unreleased]: https://github.com/Emasoft/selectfilecli/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Emasoft/selectfilecli/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Emasoft/selectfilecli/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Emasoft/selectfilecli/releases/tag/v0.1.0