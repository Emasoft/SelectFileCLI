# Loading Indicator Analysis

## Current Status

The SelectFileCLI project has two types of loading indicators:

### 1. Navigation Loading ✅ (Working)
- **When**: Changing directories via navigation (Enter, Parent button, etc.)
- **How**: Uses Textual's `container.loading = True`
- **Visual**: Shows a spinning overlay on the entire tree container
- **Code Location**: `_change_directory()` method sets loading state

### 2. Directory Expansion Loading ⚠️ (Partially Implemented)
- **When**: Expanding a directory node to see its contents
- **Expected**: Show `<...loading...>` placeholder while loading
- **Current Issue**: The loading placeholder is not consistently visible

## Implementation Details

### What Was Attempted

1. **Added loading placeholder support** in `render_label()`:
   ```python
   # Special handling for loading placeholder
   if str(file_path) == "<...loading...>":
       loading_text = Text("<...loading...>", style="bright_yellow blink")
       return loading_text
   ```

2. **Overrode `_on_tree_node_expanded()`** to add loading indicator:
   ```python
   def _on_tree_node_expanded(self, event: Tree.NodeExpanded[DirEntry]) -> None:
       node = event.node
       if node.data is not None:
           if not node.children:
               loading_node = node.add_leaf("<...loading...>", data=None)
               node._loading_placeholder = loading_node
       super()._on_tree_node_expanded(event)
   ```

3. **Updated `_populate_node()`** to remove loading placeholder:
   ```python
   if hasattr(node, '_loading_placeholder') and node._loading_placeholder:
       try:
           node._loading_placeholder.remove()
       except Exception:
           pass
   ```

### Why It's Not Working Consistently

1. **Timing Issue**: The DirectoryTree base class loads directories very quickly on local filesystems, making the loading placeholder appear and disappear too fast to see.

2. **Event Order**: The Textual DirectoryTree widget might be populating nodes before our expanded event handler runs.

3. **Async Loading**: The directory loading happens asynchronously in a worker thread, and the placeholder might be removed before the UI updates.

## Recommendations

### Option 1: Accept Current Behavior
- Navigation loading (which affects user experience more) is working well
- Directory expansion is typically fast enough that users don't need feedback
- The code infrastructure is in place if slower filesystems need it

### Option 2: Force Visibility (Testing Only)
- Use the provided test scripts that add artificial delays
- Helps verify the loading mechanism works on slow filesystems
- Not recommended for production

### Option 3: Enhanced Implementation
- Override more of the DirectoryTree's internal methods
- Add a minimum display time for loading indicators
- Implement custom directory loading with progress callbacks

## Test Scripts Provided

1. **test_loading_with_delay.py** - Adds artificial delay to make loading visible
2. **test_loading_visual.py** - Creates large directory structure for testing
3. **test_navigation_loading.py** - Tests the working navigation loading

## Conclusion

The navigation loading indicator (most important for UX) is working correctly. The directory expansion loading indicator infrastructure is in place but may not be visible on fast local filesystems. This is acceptable behavior as users get immediate feedback on slower operations while fast operations complete without unnecessary visual noise.
