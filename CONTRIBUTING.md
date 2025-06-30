# Contributing to selectFileCLI

Thank you for your interest in contributing to selectFileCLI!

## How to Contribute

### Reporting Issues

Before creating a new issue, please check if it already exists. When reporting an issue:

- Use a clear title
- Describe the steps to reproduce
- Include your environment details (OS, Python version)
- Add any error messages or screenshots

### Suggesting Features

Feature requests are welcome! Please:

- Explain the feature clearly
- Describe why it would be useful
- Provide examples if possible

### Submitting Changes

1. Fork the repository
2. Create a new branch from `main`
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/selectfilecli.git
   cd selectfilecli
   ```

2. Install uv package manager:
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

3. Set up development environment:
   ```bash
   uv venv
   source .venv/bin/activate
   uv pip install -e ".[dev]"
   ```

4. Run tests:
   ```bash
   uv run pytest
   ```

## Code Style

- Follow PEP 8 guidelines
- Format code: `uv run ruff format --line-length=320`
- Lint code: `uv run ruff check --fix`
- Add type hints to functions
- Write clear docstrings

## Testing

- Write tests for new features
- Run tests before submitting
- Keep test coverage above 80%
- Update UI snapshots when needed: `uv run pytest --snapshot-update`

## Commit Messages

Use clear commit messages:
- `feat:` for new features
- `fix:` for corrections
- `docs:` for documentation
- `test:` for test changes
- `refactor:` for code improvements

## Questions

Open an issue if you have questions or need help.

Thank you for contributing!
