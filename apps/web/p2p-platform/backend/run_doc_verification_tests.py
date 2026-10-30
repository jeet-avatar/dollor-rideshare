#!/usr/bin/env python
"""
Test runner for document verification service tests.
Run with: python run_doc_verification_tests.py
"""

import os
import subprocess
import sys

def main():
    """Run the document verification tests"""
    print("=" * 80)
    print("Running Document Verification Service Unit Tests")
    print("=" * 80)
    print()

    # Run pytest with verbose output
    result = subprocess.run(
        [
            sys.executable, "-m", "pytest",
            "tests/unit/test_document_verification.py",
            "-v",
            "--tb=short",
            "-ra"
        ],
        cwd=os.path.dirname(os.path.abspath(__file__))
    )

    print()
    print("=" * 80)
    if result.returncode == 0:
        print("All tests passed!")
    else:
        print(f"Tests failed with exit code: {result.returncode}")
    print("=" * 80)

    return result.returncode

if __name__ == "__main__":
    sys.exit(main())
