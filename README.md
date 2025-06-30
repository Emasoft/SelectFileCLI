# selectFileCLI

[![Python Version](https://img.shields.io/pypi/pyversions/selectfilecli.svg)](https://pypi.org/project/selectfilecli/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PyPI Version](https://img.shields.io/pypi/v/selectfilecli.svg)](https://pypi.org/project/selectfilecli/)

A powerful file selection browser for CLI applications using the Textual TUI framework.

![Demo](https://github.com/Emasoft/selectfilecli/assets/713559/demo.gif)

## Features

- 🎨 Modern TUI with Textual framework
- 📁 Intuitive file and directory navigation
- 🔍 Advanced sorting options (Name, Date, Size, Extension)
- ⌨️ Keyboard-driven interface
- 🎯 Simple API - just one function call
- 🖥️ Cross-platform support (Linux, macOS, Windows*)
- 🎭 Full test coverage with snapshot testing

*Windows support coming soon

## Installation

Install from PyPI:

```bash
pip install selectfilecli
```

Or install from source:

```bash
git clone https://github.com/Emasoft/selectfilecli.git
cd selectfilecli
pip install -e .
```

## Quick Start

```python
from selectfilecli import select_file

# Open file browser in current directory
selected_file = select_file()

if selected_file:
    print(f"You selected: {selected_file}")
else:
    print("No file selected")
```

## Usage Examples

### Basic File Selection

```python
from selectfilecli import select_file

# Start from a specific directory
selected_file = select_file("/home/user/documents")

if selected_file:
    with open(selected_file, 'r') as f:
        content = f.read()
        print(f"File content: {content[:100]}...")
```

### Integration with CLI Tools

```python
import click
from selectfilecli import select_file

@click.command()
@click.option('--input-file', help='Input file path')
def process_file(input_file):
    if not input_file:
        # Let user select file interactively
        input_file = select_file()
        if not input_file:
            click.echo("No file selected.")
            return

    click.echo(f"Processing: {input_file}")
    # Your processing logic here

if __name__ == '__main__':
    process_file()
```

## Keyboard Controls

| Key | Action |
|-----|--------|
| `↑`/`↓` | Navigate files and directories |
| `Enter` | Select file / Enter directory |
| `S` | Open sort options dialog |
| `Q` | Quit without selecting |
| `Escape` | Cancel current operation |

### Sort Dialog

When you press `S`, a modal dialog appears with sorting options:

- **Sort by**: Name, Creation Date, Last Accessed, Last Modified, Size, Extension
- **Order**: Ascending (↓) or Descending (↑)

Navigate with arrow keys, select with Enter, cancel with Escape.

## Requirements

- Python 3.10 or higher
- Terminal with Unicode support
- Operating System: Linux, macOS, or Windows (experimental)

## Development

### Setup Development Environment

```bash
# Install uv package manager
curl -LsSf https://astral.sh/uv/install.sh | sh

# Clone and setup
git clone https://github.com/Emasoft/selectfilecli.git
cd selectfilecli
uv venv
source .venv/bin/activate
uv pip install -e ".[dev]"
```

### Running Tests

```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov

# Update UI snapshots after changes
uv run pytest --snapshot-update
```

### Code Quality

```bash
# Format code
uv run ruff format --line-length=320

# Lint code
uv run ruff check --fix

# Type checking
uv run mypy src
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2024 Emasoft

## Acknowledgments

- Built with [Textual](https://github.com/Textualize/textual) - An amazing TUI framework for Python
- Tested with [pytest-textual-snapshot](https://github.com/Textualize/pytest-textual-snapshot) - Snapshot testing for Textual apps
- Linted with [Ruff](https://github.com/astral-sh/ruff) - An extremely fast Python linter

## Contributing

Contributions are welcome! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes in each release.

## Support

- 📫 Report issues on [GitHub Issues](https://github.com/Emasoft/selectfilecli/issues)
- 💬 Ask questions in [Discussions](https://github.com/Emasoft/selectfilecli/discussions)
- 📧 Contact: 713559+Emasoft@users.noreply.github.com
