#!/usr/bin/env bash
# ==============================================================================
# File:        test/run_tests.sh
# Author:      agguro
# Date:        August 20, 2026
# Description: Extended automated test runner for dividend portfolio & equities.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$PROJECT_ROOT/build/debug/x86_64"

FETCH_TICKER="$BIN_DIR/fetch-ticker"
TICKER_GBM="$BIN_DIR/ticker-gbm"

echo "=== RUNNING EXTENDED PORTFOLIO TESTS ==="

# 1. Build in debug mode from project root
cd "$PROJECT_ROOT"
make clean >/dev/null 2>&1 || true
make debug >/dev/null

# 2. Fetch required tickers (met gecorrigeerde Yahoo Finance / beursnoteringen)
declare -A TICKER_MAP=(
    ["O"]="O"
    ["MAIN"]="MAIN"
    ["SPCX"]="SPCX"
    ["PSEC"]="PSEC"
    ["AGS"]="AGS.BR"
    ["SOLB"]="SOLB.BR"
    ["ARCC"]="ARCC"
    ["JEPE"]="JEPY"
    ["JEPQ"]="JEPQ"
    ["JEQP"]="JEQP.L"
    ["KBC"]="KBC.BR"
    ["SMIF"]="SMIF.L"
    ["STAG"]="STAG"
)

echo "[*] Fetching ticker data..."
for local_name in "${!TICKER_MAP[@]}"; do
    remote_sym="${TICKER_MAP[$local_name]}"
    if [ -x "$FETCH_TICKER" ]; then
        "$FETCH_TICKER" "$remote_sym" max 1d >/dev/null 2>&1
        if [ -f "$PROJECT_ROOT/${remote_sym}.ticker" ]; then
            mv "$PROJECT_ROOT/${remote_sym}.ticker" "$SCRIPT_DIR/${local_name}.ticker"
            echo "    fetching ticker $local_name ($remote_sym) - OK"
        elif [ -f "$PROJECT_ROOT/${local_name}.ticker" ]; then
            mv "$PROJECT_ROOT/${local_name}.ticker" "$SCRIPT_DIR/"
            echo "    fetching ticker $local_name - OK"
        else
            echo "    fetching ticker $local_name ($remote_sym) - FAIL"
        fi
    else
        echo "    fetching ticker $local_name - ERROR (fetch-ticker missing)"
    fi
done

echo "[*] Evaluating Monte Carlo simulations..."

# 3. Define realistic test parameters per ticker
declare -a TESTS=(
    "O:$SCRIPT_DIR/O.ticker:62.50:5000000:30d"
    "MAIN:$SCRIPT_DIR/MAIN.ticker:48.20:5000000:30d"
    "SPCX:$SCRIPT_DIR/SPCX.ticker:230.00:5000000:91d"
    "PSEC:$SCRIPT_DIR/PSEC.ticker:1.85:5000000:180d"
    "AGS:$SCRIPT_DIR/AGS.ticker:41.00:5000000:30d"
    "SOLB:$SCRIPT_DIR/SOLB.ticker:34.50:5000000:30d"
    "ARCC:$SCRIPT_DIR/ARCC.ticker:21.10:5000000:30d"
    "JEPE:$SCRIPT_DIR/JEPE.ticker:50.00:5000000:30d"
    "JEPQ:$SCRIPT_DIR/JEPQ.ticker:54.80:5000000:30d"
    "JEQP:$SCRIPT_DIR/JEQP.ticker:45.00:5000000:30d"
    "KBC:$SCRIPT_DIR/KBC.ticker:82.00:5000000:30d"
    "SMIF:$SCRIPT_DIR/SMIF.ticker:1.05:5000000:91d"
    "STAG:$SCRIPT_DIR/STAG.ticker:38.90:5000000:30d"
)

# 4. Execute tests and report per item
FAILED=0
for test_case in "${TESTS[@]}"; do
    IFS=':' read -r name file price paths duration <<< "$test_case"
    cmd="$TICKER_GBM $file $price $paths $duration"
    
    if OUTPUT=$(eval "$cmd" 2>&1); then
        echo "    evaluating $name.ticker $price $paths $duration - OK"
    else
        EXIT_CODE=$?
        echo "    evaluating $name.ticker $price $paths $duration - FAIL (exit code: $EXIT_CODE)"
        if [ -n "$OUTPUT" ]; then
            echo "        Output: $OUTPUT"
        fi
        FAILED=$((FAILED + 1))
    fi
done

echo "========================================"
if [ $FAILED -eq 0 ]; then
    echo "RESULT: ALL PORTFOLIO TESTS PASSED"
    exit 0
else
    echo "RESULT: $FAILED TEST(S) FAILED"
    exit 1
fi
