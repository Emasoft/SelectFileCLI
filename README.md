# selectFileCLI

<div align="center">

[![GitHub CI](https://github.com/Emasoft/SelectFileCLI/actions/workflows/check.yml/badge.svg)](https://github.com/Emasoft/SelectFileCLI/actions/workflows/check.yml)
[![Tests](https://github.com/Emasoft/SelectFileCLI/actions/workflows/test.yml/badge.svg)](https://github.com/Emasoft/SelectFileCLI/actions/workflows/test.yml)
[![Lint](https://github.com/Emasoft/SelectFileCLI/actions/workflows/lint.yml/badge.svg)](https://github.com/Emasoft/SelectFileCLI/actions/workflows/lint.yml)
[![Build](https://github.com/Emasoft/SelectFileCLI/actions/workflows/build.yml/badge.svg)](https://github.com/Emasoft/SelectFileCLI/actions/workflows/build.yml)
[![codecov](https://codecov.io/gh/Emasoft/SelectFileCLI/branch/main/graph/badge.svg)](https://codecov.io/gh/Emasoft/SelectFileCLI)

[![Python Version](https://img.shields.io/pypi/pyversions/selectfilecli.svg)](https://pypi.org/project/selectfilecli/)
[![PyPI Version](https://img.shields.io/pypi/v/selectfilecli.svg)](https://pypi.org/project/selectfilecli/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Downloads](https://img.shields.io/pypi/dm/selectfilecli.svg)](https://pypi.org/project/selectfilecli/)
[![Code style: ruff](https://img.shields.io/badge/code%20style-ruff-000000.svg)](https://github.com/astral-sh/ruff)

**A powerful and intuitive file selection browser for CLI applications using the Textual TUI framework**

![Demo](https://github.com/Emasoft/selectfilecli/assets/713559/demo.gif)

</div>

---

> ⚠️ **EARLY ALPHA WARNING**: This project is in early alpha stage and is **NOT** ready for production use. APIs may change, and stability is not guaranteed. Use at your own risk!

---

## 📋 Table of Contents

- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Usage Examples](#-usage-examples)
- [Keyboard Controls](#️-keyboard-controls)
- [Development](#-development)
- [Contributing](#-contributing)
- [License](#-license)
- [Support](#-support)
- [Acknowledgments](#-acknowledgments)

## ✨ Features

- 🎨 **Modern TUI** - Built with the powerful Textual framework for beautiful terminal interfaces
- 📁 **Intuitive Navigation** - Easy file and directory browsing with keyboard controls
- 🔍 **Advanced Sorting** - Multiple sort modes: Name, Date, Size, Extension with memory
- ⌨️ **Keyboard-Driven** - Fully accessible via keyboard with vim-style shortcuts
- 🎯 **Simple API** - Just one function call: `select_file()` with backward compatibility
- 🖥️ **Cross-Platform** - Works on Linux, macOS, and Windows (experimental)
- 🧪 **Well-Tested** - 93.92% test coverage with snapshot testing
- 📦 **Zero Config** - Works out of the box, no configuration needed

### New in v0.4.5

- 📆 **Enhanced DateTime Display** - Fixed 24h format with emojis: `📆YYYY-MM-DD 🕚HH:MM:SS`
- 📊 **File Size Formatting** - Localized number formatting with proper units (KB, MB, GB)
- 🎯 **Visual Navigation** - Emoji buttons with underlined shortcuts: 🔼Parent(u) 🏠Home(h) ⏫Root(r)
- 🎨 **ls-style Visual Cues** - File type indicators: `/` dirs, `*` executable, `@` symlinks
- ✨ **Virtual Environment Detection** - Folders containing Python venvs marked with ✨
- 📁 **Folder Selection** - Select directories with configurable options
- 📋 **Comprehensive FileInfo** - Returns detailed file/folder information
- 🚀 **Performance** - Async loading with visual feedback, column-aligned entries
- ❌ **Error Handling** - Graceful error messages in FileInfo.error_message
- 📐 **Responsive UI** - Real-time terminal resizing support

## 📋 Requirements

- **Python**: 3.10 or higher
- **Terminal**: Unicode support required
- **OS**: Linux, macOS, or Windows (experimental)

## 📦 Installation

### From PyPI (Recommended)

```bash
pip install selectfilecli
```

### Using uv (Fast Python Package Manager)

```bash
uv pip install selectfilecli
```

### From Source

```bash
git clone https://github.com/Emasoft/SelectFileCLI.git
cd SelectFileCLI
pip install -e .
```

### Development Installation

```bash
git clone https://github.com/Emasoft/SelectFileCLI.git
cd SelectFileCLI
uv venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
uv pip install -e ".[dev]"
```

## 🚀 Quick Start

```python
from selectfilecli import select_file

# Open file browser in current directory
selected_file = select_file()

if selected_file:
    print(f"You selected: {selected_file}")
else:
    print("No file selected")
```

## 📖 Usage Examples

### Basic File Selection (Backward Compatible)

```python
from selectfilecli import select_file

# Returns string path for backward compatibility
selected_file = select_file()

if selected_file:
    print(f"You selected: {selected_file}")
else:
    print("No file selected")
```

### Advanced File Selection with FileInfo

```python
from selectfilecli import select_file

# Get comprehensive file information
result = select_file(return_info=True)

if result and result.error_message:
    print(f"Error: {result.error_message}")
elif result and result.file_path:
    print(f"📄 File: {result.file_path}")
    print(f"   Size: {result.size_in_bytes:,} bytes")
    print(f"   Modified: 📆{result.last_modified_datetime:%Y-%m-%d} 🕚{result.last_modified_datetime:%H:%M:%S}")
    print(f"   Read-only: {'Yes ⛔' if result.readonly else 'No ✅'}")
    if result.is_symlink:
        print(f"   Symlink: {'Broken 🔗💔' if result.symlink_broken else 'Yes 🔗'}")
```

### Folder Selection

```python
from selectfilecli import select_file

# Select folders only
result = select_file(
    select_files=False,
    select_dirs=True,
    return_info=True
)

if result and result.folder_path:
    print(f"📁 Folder: {result.folder_path}")
    print(f"   Has venv: {'Yes ✨' if result.folder_has_venv else 'No'}")
    if result.size_in_bytes:
        print(f"   Size: {result.size_in_bytes:,} bytes (recursive)")
```

### Mixed Mode - Files and Folders

```python
from selectfilecli import select_file

# Allow selection of both files and folders
# Press 'd' to select current directory, Enter for files
result = select_file(
    select_files=True,
    select_dirs=True,
    return_info=True
)

if result:
    if result.file_path:
        print(f"Selected file: {result.file_path}")
    elif result.folder_path:
        print(f"Selected folder: {result.folder_path}")
```

### Integration with Click CLI

```python
import click
from selectfilecli import select_file

@click.command()
@click.option('--input-file', help='Input file path')
def process_file(input_file):
    if not input_file:
        # Let user select file interactively with detailed info
        result = select_file(return_info=True)
        if not result or not result.file_path:
            click.echo("No file selected.")
            return

        input_file = result.file_path
        click.echo(f"Processing: {input_file}")
        click.echo(f"File size: {result.size_in_bytes:,} bytes")

    # Your processing logic here

if __name__ == '__main__':
    process_file()
```

### Configuration File Selector

```python
from pathlib import Path
from selectfilecli import select_file

def load_config():
    config_dir = Path.home() / '.config' / 'myapp'

    # Use backward compatible mode for simple path return
    config_file = select_file(str(config_dir))

    if config_file and config_file.endswith('.json'):
        import json
        with open(config_file) as f:
            return json.load(f)
    else:
        print("Please select a valid JSON config file")
        return None
```

## ⌨️ Keyboard Controls

### Main Navigation

| Key | Action | Description |
|-----|--------|-------------|
| `↑` / `k` | Move up | Navigate to previous item |
| `↓` / `j` | Move down | Navigate to next item |
| `Enter` | Select / Open | Select file or enter directory |
| `u` / `Backspace` | Parent Directory 🔼 | Navigate to parent directory |
| `h` | Home Directory 🏠 | Go to user's home directory |
| `r` | Root Directory ⏫ | Go to system root (/) |
| `d` | Select Directory | Select current directory (when dirs enabled) |
| `s` | Sort Menu 📊 | Open sort options dialog |
| `q` / `Escape` | Cancel ❌ | Exit without selecting |
| `Ctrl+C` | Force Quit | Immediate exit |

### Sort Dialog Controls

| Key | Action | Description |
|-----|--------|-------------|
| `↑` / `↓` | Navigate options | Move between sort modes |
| `Space` | Toggle order | Switch between ascending/descending |
| `Enter` | Apply sort | Apply selected sort mode |
| `Escape` | Cancel | Close dialog without changes |

### Available Sort Modes

- **Name** - Alphabetical order
- **Creation Date** - When file was created
- **Last Accessed** - Most recently accessed files
- **Last Modified** - Most recently modified files
- **Size** - File size (largest/smallest first)
- **Extension** - Group by file extension

## 🛠️ Development

### Setup Development Environment

```bash
# Install uv (recommended)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Clone repository
git clone https://github.com/Emasoft/SelectFileCLI.git
cd SelectFileCLI

# Create virtual environment
uv venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install with dev dependencies
uv pip install -e ".[dev]"

# Install pre-commit hooks
pre-commit install
```

### Running Tests

```bash
# Run all tests
uv run pytest

# Run with coverage report
uv run pytest --cov=src/selectfilecli --cov-report=html

# Run specific test file
uv run pytest tests/test_file_browser_app.py

# Update UI snapshots after changes
uv run pytest --snapshot-update
```

### Code Quality Tools

```bash
# Format code
uv run ruff format --line-length=320

# Lint code
uv run ruff check --fix

# Type checking
uv run mypy src

# Run all pre-commit hooks
pre-commit run --all-files
```

### Building & Publishing

```bash
# Build package
uv build

# Test locally
pip install dist/*.whl

# Publish to PyPI (requires credentials)
uv publish
```

## 🤝 Contributing

Contributions are welcome! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Quick Contribution Guide

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2024 Emasoft

## 💬 Support

- 🐛 **Report Bugs**: [GitHub Issues](https://github.com/Emasoft/SelectFileCLI/issues)
- 💡 **Request Features**: [Feature Requests](https://github.com/Emasoft/SelectFileCLI/issues/new?labels=enhancement)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/Emasoft/SelectFileCLI/discussions)
- 📧 **Contact**: 713559+Emasoft@users.noreply.github.com

## 🙏 Acknowledgments

Special thanks to these amazing projects:

- [**Textual**](https://github.com/Textualize/textual) - The incredible TUI framework that powers this project
- [**pytest-textual-snapshot**](https://github.com/Textualize/pytest-textual-snapshot) - Snapshot testing for Textual apps
- [**Ruff**](https://github.com/astral-sh/ruff) - Lightning-fast Python linter
- [**uv**](https://github.com/astral-sh/uv) - Blazingly fast Python package manager

---

<div align="center">

**Made with ❤️ by [Emasoft](https://github.com/Emasoft)**

⭐ Star this repository if you find it useful!

</div>
