#!/bin/bash
set -e

echo "============================================================"
echo "PRODUCTION PORTFOLIO INTEGRATION SUITE (90d / 1d)"
echo "============================================================"

# Kogelvrije project-root detectie
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Build-modus
MODE="debug"

# Absolute paden
BASE_BIN_DIR="${PROJECT_ROOT}/bin/${MODE}/x86_64"
DATA_DIR="${PROJECT_ROOT}/data"

# Zorg dat de centrale data-map in de project-root bestaat
mkdir -p "$DATA_DIR"

# Volledige paden naar de executables
FETCH_TICKER_BIN="${BASE_BIN_DIR}/fetch-ticker/fetch-ticker"
TICKER_GBM_BIN="${BASE_BIN_DIR}/ticker-gbm/ticker-gbm"

# Verificatie van de binaries
if [ ! -f "$FETCH_TICKER_BIN" ]; then
    echo ">>> ERROR: $FETCH_TICKER_BIN not found. Please compile your project first."
    exit 1
fi

if [ ! -f "$TICKER_GBM_BIN" ]; then
    echo ">>> ERROR: $TICKER_GBM_BIN not found. Please compile your project first."
    exit 1
fi

# Target portfolio "chickens"
TICKERS=("MAIN" "O" "PSEC" "ARCC" "JEPQ")

echo "Starting data ingestion and simulation pipeline [Mode: ${MODE}]..."
echo "------------------------------------------------------------"

for TICKER in "${TICKERS[@]}"
do
    echo -e "\n[PIPELINE] Processing: $TICKER"
    
    # 1. Network Fetch Phase
    echo "  >> Fetching 90 days of historical data..."
    
    # Onthoud waar we stonden, spring naar de centrale data-map en voer de fetch uit
    pushd "$DATA_DIR" > /dev/null
    "$FETCH_TICKER_BIN" "$TICKER" "90d" "1d"
    popd > /dev/null # Spring direct weer terug naar de test-map
    
    # Definieer het verwachte bestand in de centrale map
    TARGET_FILE="${DATA_DIR}/${TICKER}.ticker"
    
    if [ ! -s "$TARGET_FILE" ]; then
        echo "  >> ERROR: Ingestion failed. $TARGET_FILE is empty or missing."
        exit 1
    fi
    
    # 2. GPU Simulation Phase
    echo "  >> Launching GPU Monte Carlo (30-day horizon, 5,000,000 paths)..."
    "$TICKER_GBM_BIN" "$TARGET_FILE" 0 5000000 30
    
    echo "------------------------------------------------------------"
done

echo ">>> SUCCESS: All portfolio assets successfully mapped, ingested, and simulated."
exit 0
