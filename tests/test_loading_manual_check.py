#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Manual test to check loading indicators are working."""

import tempfile
import asyncio
from pathlib import Path
from selectfilecli.file_browser_app import FileBrowserApp, CustomDirectoryTree
from textual.pilot import Pilot


async def test_loading_indicator_manual():
    """Manually test if loading indicators appear."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_dir = Path(tmpdir)
        
        # Create test structure
        for i in range(3):
            folder = test_dir / f"folder_{i}"
            folder.mkdir()
            for j in range(5):
                (folder / f"file_{j}.txt").write_text(f"Content {j}")
            
            sub = folder / "subfolder"
            sub.mkdir()
            (sub / "nested.txt").write_text("Nested")
        
        app = FileBrowserApp(str(test_dir))
        
        async with app.run_test() as pilot:
            # Test 1: Navigation loading
            print("\n=== Testing Navigation Loading ===")
            await pilot.press("down")
            await pilot.press("enter")
            
            # Check if loading is active
            container = app.query_one("#tree-container")
            print(f"Container loading state: {container.loading}")
            
            # Wait a bit
            await asyncio.sleep(0.5)
            
            # Test 2: Directory expansion loading
            print("\n=== Testing Directory Expansion Loading ===")
            tree = app.query_one("#directory-tree", CustomDirectoryTree)
            
            # Navigate back first
            await pilot.press("p")
            await asyncio.sleep(0.5)
            
            # Find expandable node
            root = tree.root
            if root and root.children:
                for node in root.children:
                    if node.allow_expand:
                        print(f"Expanding node: {node.label}")
                        
                        # Check before expansion
                        print(f"Node children before: {len(node.children)}")
                        
                        # Expand
                        node.expand()
                        
                        # Check immediately after
                        print(f"Node children after expand: {len(node.children)}")
                        if hasattr(node, '_loading_placeholder'):
                            print(f"Loading placeholder exists: {node._loading_placeholder}")
                        
                        # Let it populate
                        await asyncio.sleep(0.5)
                        print(f"Node children after wait: {len(node.children)}")
                        
                        break
            
            print("\n=== Test Complete ===")


if __name__ == "__main__":
    asyncio.run(test_loading_indicator_manual())