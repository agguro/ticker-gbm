#!/bin/bash
set -e

echo "============================================================"
echo "PRODUCTION PORTFOLIO INTEGRATION SUITE (90d / 1d)"
echo "============================================================"

# Ensure output structures exist
mkdir -p data
mkdir -p bin/x86_64

# Verify required executables are present
for binary in fetch_ticker gbm_ticker; do
    if [ ! -f "./bin/x86_64/$binary" ]; then
        echo ">>> ERROR: ./bin/x86_64/$binary not found. Please compile your binaries first."
        exit 1
    fi
done

# Define your target portfolio "chickens"
TICKERS=("MAIN" "O" "PSEC" "ARCC" "JEQP")

echo "Starting data ingestion and simulation pipeline..."
echo "------------------------------------------------------------"

for TICKER in "${TICKERS[@]}"
do
    echo -e "\n[PIPELINE] Processing: $TICKER"
    
    # 1. Network Fetch Phase (using your standard 3-arg syntax)
    echo "  >> Fetching 90 days of historical data..."
    ./bin/x86_64/fetch_ticker "$TICKER" "90d" "1d"
    
    # Check if fetch_ticker placed the output file correctly
    # If fetch_ticker outputs to a fixed path like data/$TICKER.ticker, we verify it here:
    TARGET_FILE="data/${TICKER}.ticker"
    
    if [ ! -s "$TARGET_FILE" ]; then
        echo "  >> ERROR: Ingestion failed. $TARGET_FILE is empty or missing."
        exit 1
    fi
    
    # 2. GPU Simulation Phase (30-Day Forecast Horizon, 5M Trajectories)
    echo "  >> Launching GPU Monte Carlo (30-day horizon, 5,000,000 paths)..."
    ./bin/x86_64/monte_carlo "$TARGET_FILE" 0 5000000 30
    
    echo "------------------------------------------------------------"
done

echo ">>> SUCCESS: All portfolio assets successfully mapped, ingested, and simulated."
exit 0
