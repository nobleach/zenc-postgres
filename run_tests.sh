#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export ZENC_PG_TEST_CONNINFO="${ZENC_PG_TEST_CONNINFO:-host=localhost dbname=postgres user=postgres}"

TEST_FILES=(tests/test_*.zc)
PASSED=0
FAILED=0

TMP_OUT="test_out_$$"
for test_file in "${TEST_FILES[@]}"; do
    echo "Running $test_file ..."
    if zc run "$test_file" -o "$TMP_OUT" -w; then
        echo "  passed"
        ((PASSED++)) || true
    else
        echo "  FAILED"
        ((FAILED++)) || true
    fi
    rm -f "$TMP_OUT" "$TMP_OUT.cpp"
done

echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [ $FAILED -ne 0 ]; then
    exit 1
fi
