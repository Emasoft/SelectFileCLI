#!/bin/bash
# Test script to demonstrate sequential execution

echo "=== Testing Sequential Execution ==="
echo "This will run two commands sequentially through the safe wrapper"
echo

# Test 1: Simple echo command
echo "Test 1: Running echo command..."
./scripts/seq echo "Hello from sequential executor!"
echo

# Test 2: Python version check
echo "Test 2: Running Python version check..."
./scripts/seq python --version
echo

# Test 3: Show that multiple processes wait for each other
echo "Test 3: Running two commands that should execute sequentially..."
echo "Starting first command in background..."
./scripts/seq bash -c "echo 'First command started'; sleep 3; echo 'First command finished'" &

sleep 1

echo "Starting second command (should wait for first)..."
./scripts/seq bash -c "echo 'Second command started'; sleep 2; echo 'Second command finished'"

echo
echo "Waiting for background job to complete..."
wait

echo
echo "=== Test Complete ==="
echo "You should have seen the commands execute one at a time,"
echo "with the second command waiting for the first to complete."
