#!/usr/bin/env bash
# test-bash-compatibility.sh - Test script for bash 3.2 compatibility
#
# This script tests features used in our scripts to ensure they work
# with bash 3.2 (default on macOS)
#
set -euo pipefail

echo "Testing bash compatibility..."
echo "Bash version: $BASH_VERSION"

# Test 1: Indirect array expansion (used in wait_all.sh)
echo -n "Test 1 - Indirect array expansion: "
test_array=(one two three)
array_name="test_array"
array_ref="${array_name}[@]"
expanded=("${!array_ref}")
if [ "${expanded[1]}" = "two" ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 2: Indirect variable expansion
echo -n "Test 2 - Indirect variable expansion: "
test_var="hello"
var_name="test_var"
indirect_value="${!var_name}"
if [ "$indirect_value" = "hello" ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 3: Array element access via indirect expansion
echo -n "Test 3 - Array element indirect access: "
test_array2=(alpha beta gamma)
array_elem="test_array2[1]"
elem_value="${!array_elem}"
if [ "$elem_value" = "beta" ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 4: Process substitution (used in various scripts)
echo -n "Test 4 - Process substitution: "
if diff <(echo "test") <(echo "test") >/dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL (process substitution not supported)"
fi

# Test 5: $BASH_VERSION parsing
echo -n "Test 5 - Bash version parsing: "
major="${BASH_VERSION%%.*}"
minor_full="${BASH_VERSION#*.}"
minor="${minor_full%%.*}"
if [ "$major" -ge 3 ]; then
    echo "PASS (version $major.$minor)"
else
    echo "FAIL"
    exit 1
fi

# Test 6: Portable tac replacement
echo -n "Test 6 - Portable tac replacement: "
portable_tac() {
    awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--]}'
}
result=$(echo -e "1\n2\n3" | portable_tac)
expected=$(echo -e "3\n2\n1")
if [ "$result" = "$expected" ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 7: Command existence check
echo -n "Test 7 - Command existence check: "
if command -v bash >/dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 8: Local variables in functions
echo -n "Test 8 - Local variables in functions: "
test_locals() {
    local var1="local1"
    local var2="local2"
    echo "$var1 $var2"
}
if [ "$(test_locals)" = "local1 local2" ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 9: Arrays and loops
echo -n "Test 9 - Arrays and loops: "
test_array3=()
for i in 1 2 3; do
    test_array3+=("item$i")
done
if [ "${#test_array3[@]}" -eq 3 ] && [ "${test_array3[2]}" = "item3" ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 10: Arithmetic operations
echo -n "Test 10 - Arithmetic operations: "
result=$((5 + 3 * 2))
if [ "$result" -eq 11 ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo
echo "All bash 3.2 compatibility tests passed!"
echo
echo "Note: These scripts are designed to work with bash 3.2+"
echo "which is the default version on macOS."
