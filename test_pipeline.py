#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Test file to verify the complete pre-commit pipeline."""


def calculate_sum(a: int, b: int) -> int:
    """Calculate the sum of two numbers.

    Args:
        a: First number
        b: Second number

    Returns:
        The sum of a and b
    """
    result = a + b
    print(f"Sum of {a} + {b} = {result}")
    return result


def main() -> None:
    """Main function to test the pipeline."""
    # Test some calculations
    x = 10
    y = 20
    total = calculate_sum(x, y)
    print(f"Total: {total}")

    # Test with different values
    result2 = calculate_sum(5, 15)
    print(f"Another result: {result2}")


if __name__ == "__main__":
    main()
