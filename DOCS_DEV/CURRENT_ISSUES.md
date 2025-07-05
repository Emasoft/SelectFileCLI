# Current Issues to Fix

## UI Layout Issues
1. **Header overlapping button bar** - Move button bar down by 1 character
2. **Header shows only title** - Subtitle is not displayed
3. **Current path not displayed** - Path display is missing/not visible

## Directory Loading Issues
4. **Empty folders show nothing** - Should display `<empty>` label
5. **Slow directory tree loading** - UI becomes unresponsive when loading large folders
   - Need to implement async loading with Workers
   - Show `<...loading...>` placeholder with blinking effect
   - Keep UI responsive during loading
6. **Directory navigation is slow** - Black screen while loading new directory
   - Use Workers for background loading
   - Show directory root immediately with `<...loading...>` placeholder below

## Sort Dialog Issues
7. **Sort dialog problems**:
   - Missing OK and Cancel buttons
   - Enter key doesn't apply sorting
   - Dialog doesn't remember current settings

## Display Formatting Issues
8. **Directory entries not aligned** - Need column alignment for:
   - File name
   - Size
   - Type
   - Date/Time
   - Read-only status
   - Long filenames should wrap to 2-3 lines

## Performance Issues
9. **Quit/Cancel action is slow** - Takes several seconds
   - Should be renamed to "Cancel"
   - Should return tuple with all None values

## API Changes
10. **Add error_message to return tuple**
    - New tuple element for error reporting
    - When error_message is not None, other elements should be ignored
    - Update documentation and docstrings

## Other Issues
11. **Real-time resizing doesn't work** - Window resizing not handled properly
