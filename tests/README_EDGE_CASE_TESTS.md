# Edge Case Visual Snapshot Tests

This document describes the comprehensive edge case visual snapshot tests added to ensure the file browser's layout stability and correct rendering across various scenarios.

## Test Files Created

### 1. `test_edge_case_snapshots.py`
Tests for Unicode characters, special characters, and extreme filenames:
- **Unicode Language Support**: Tests filenames in Chinese, Japanese, Korean, Russian, Arabic, Hebrew, Hindi, Sanskrit, Greek
- **RTL Language Handling**: Arabic and Hebrew text displayed in LTR direction as requested
- **Special Characters**: Tests all common special characters in filenames
- **Control Characters**: Tests handling of newlines, tabs, null chars, escape sequences
- **Leading/Trailing Spaces**: Tests files with whitespace at beginning/end
- **Zero-Width Characters**: Tests invisible Unicode characters
- **Very Long Filenames**: Tests horizontal scrolling behavior
- **Emoji Support**: Tests mixed emoji and text filenames

### 2. `test_control_char_snapshots.py`
Focused tests for control and invisible characters:
- **ASCII Control Characters**: NULL, BELL, BACKSPACE, TAB, LF, CR, ESC, DEL
- **Unicode Control Characters**: Zero-width spaces, joiners, directional marks
- **Combining Characters**: Tests diacritical marks and combining accents
- **Zalgo Text**: Tests extreme combining character usage
- **Emoji Sequences**: Tests complex emoji with skin tones and ZWJ sequences
- **Boundary Conditions**: Tests filesystem limits and edge cases

### 3. `test_scrollbar_snapshots.py`
Tests scrollbar behavior and appearance:
- **Vertical Scrolling**: Tests with 100+ files
- **Horizontal Scrolling**: Tests with very long filenames
- **Mixed Scrolling**: Tests both scrollbars simultaneously
- **Nested Tree Scrolling**: Tests deeply nested directory structures
- **Page Navigation**: Tests Page Up/Down behavior
- **Continuous Scrolling**: Tests smooth scrolling behavior

### 4. `test_terminal_resize_snapshots.py`
Tests layout adaptation to different terminal sizes:
- **Standard Sizes**: 80x24, 120x40
- **Wide Terminals**: 160x15, 250x30
- **Narrow Terminals**: 40x50, 25x20
- **Extreme Sizes**: 20x8 (minimum), 300x80 (maximum)
- **Square Terminals**: 40x40, 100x100
- **Mobile-like Ratios**: 50x80 (portrait), 80x35 (landscape)

### 5. `test_snapshot_app_edge_cases.py`
Snapshot app for consistent edge case testing with predefined directory structure.

## Terminal Size Coverage

The tests cover a wide range of terminal sizes to ensure responsive behavior:

| Type | Sizes Tested |
|------|--------------|
| Tiny | 20x8, 25x20, 30x10 |
| Narrow | 25x20, 30x20, 35x15, 40x20, 40x50 |
| Standard | 80x24, 80x30, 80x40 |
| Wide | 100x30, 120x40, 160x15, 200x40, 250x30 |
| Square | 40x40, 60x60, 100x100 |
| Extreme | 20x8, 300x80 |

## Special Character Coverage

The tests ensure proper handling of:
- All printable ASCII special characters
- Unicode directional marks (LTR/RTL)
- Zero-width spaces and joiners
- Combining diacritical marks
- Control characters (properly escaped)
- Emoji and emoji sequences
- Mixed scripts and languages

## Why SVG Snapshots Are Critical

SVG snapshots are essential for these edge cases because:
1. They capture the exact visual output including character rendering
2. They preserve layout, alignment, and spacing precisely
3. They show scrollbar positions and UI element placement
4. They detect any layout breaks from special characters
5. They ensure consistent rendering across different terminal sizes

## Running the Tests

To run all edge case snapshot tests:
```bash
uv run pytest tests/test_edge_case_snapshots.py tests/test_control_char_snapshots.py tests/test_scrollbar_snapshots.py tests/test_terminal_resize_snapshots.py -v
```

To update snapshots after intentional changes:
```bash
uv run pytest tests/test_*_snapshots.py --snapshot-update
```

## Test Maintenance

When modifying the file browser UI:
1. Run tests to see failures
2. Review the snapshot report HTML
3. If changes are intentional, update snapshots
4. Commit both code changes and updated SVG files
