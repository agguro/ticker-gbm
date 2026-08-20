#!/usr/bin/env bash
# ==============================================================================
# File:        test/run_tests.sh
# Author:      agguro
# Date:        August 20, 2026
# Description: Automated test runner that fetches tickers and verifies exit codes.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$PROJECT_ROOT/build/debug/x86_64"

FETCH_TICKER="$BIN_DIR/fetch-ticker"
TICKER_GBM="$BIN_DIR/ticker-gbm"

echo "=== RUNNING AUTOMATED TESTS ==="

# 1. Build in debug mode from project root
cd "$PROJECT_ROOT"
make clean >/dev/null 2>&1 || true
make debug >/dev/null

# 2. Fetch required tickers using the correct CLI arguments: fetch-ticker <ticker> <interval> <range>
# Output is saved directly as <ticker>.ticker inside the test/ directory
TICKERS=("O" "MAIN" "SPCX" "PSEC")
echo "[*] Fetching ticker data..."
for ticker in "${TICKERS[@]}"; do
    if [ -x "$FETCH_TICKER" ]; then
        "$FETCH_TICKER" "$ticker" max 1d > "$SCRIPT_DIR/${ticker}.ticker" 2>/dev/null || {
            # Fallback if command fails, create empty file or touch
            touch "$SCRIPT_DIR/${ticker}.ticker"
        }
    else
        touch "$SCRIPT_DIR/${ticker}.ticker"
    fi
done

# 3. Define test commands (referencing files inside test/)
declare -a TESTS=(
    "$TICKER_GBM $SCRIPT_DIR/PSEC.ticker 1.89 5000000 180d"
    "$TICKER_GBM $SCRIPT_DIR/O.ticker 65 5000000 18d"
    "$TICKER_GBM $SCRIPT_DIR/MAIN.ticker 60 5000000 20d"
    "$TICKER_GBM $SCRIPT_DIR/SPCX.ticker 230 5000000 91d"
)

# 4. Execute and strictly check exit codes
FAILED=0
for cmd in "${TESTS[@]}"; do
    if OUTPUT=$(eval "$cmd" 2>&1); then
        echo "[OK]   $cmd"
    else
        EXIT_CODE=$?
        echo "[FAIL] $cmd (exit code: $EXIT_CODE)"
        echo "       Output: $OUTPUT"
        FAILED=$((FAILED + 1))
    fi
done

echo "================================"
if [ $FAILED -eq 0 ]; then
    echo "RESULT: ALL TESTS PASSED"
    exit 0
else
    echo "RESULT: $FAILED TEST(S) FAILED"
    exit 1
fi
