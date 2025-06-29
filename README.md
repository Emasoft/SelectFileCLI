# selectfilecli

A handy file selection browser for CLI applications using Python.

## Features

- Simple TUI (Text User Interface) for file browsing
- Navigate directories with arrow keys
- Select files with Enter key
- Cancel with 'q' key
- Easy to integrate into any CLI application
- Works on Unix-like systems (Linux, macOS)

## Installation

```bash
pip install selectfilecli
```

Or install from source:

```bash
git clone https://github.com/Emasoft/selectfilecli.git
cd selectfilecli
pip install -e .
```

## Usage

### Basic Usage

```python
from selectfilecli import select_file

# Open file browser in current directory
selected_file = select_file()

if selected_file:
    print(f"You selected: {selected_file}")
else:
    print("No file selected")
```

### Start from Specific Directory

```python
from selectfilecli import select_file

# Open file browser in specific directory
selected_file = select_file("/home/user/documents")

if selected_file:
    with open(selected_file, 'r') as f:
        content = f.read()
```

## Controls

- **‘/“ Arrow Keys**: Navigate through files and directories
- **Enter**: Select the highlighted file
- **Enter** (on directory): Enter the directory
- **q**: Cancel and return None

## Requirements

- Python 3.10+
- Unix-like operating system (Linux, macOS)
- Terminal with ANSI escape code support

## Roadmap

- [ ] Add Windows support
- [ ] Migrate to Textual library for better cross-platform support
- [ ] Add file filtering options
- [ ] Add file preview functionality
- [ ] Add multi-file selection support

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.