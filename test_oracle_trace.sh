#!/bin/bash

# Quick test script to verify oracle predictor works with annotated binary traces

set -e

echo "=========================================="
echo "Testing Oracle Predictor with BFS G13"
echo "=========================================="
echo ""

# Check if trace exists
TRACE="/home/asamara/code/SNIPER-graphs/GraphLeto/traces/bfs_g13.champsimtrace.xz"
if [ ! -f "$TRACE" ]; then
    echo "Error: Trace not found: $TRACE"
    echo "Generate it with: ./generate_gapbs_traces.sh g13 bfs"
    exit 1
fi

# Check if oracle addresses exist
ORACLE_FILE="/home/asamara/code/SNIPER-graphs/GraphLeto/GABPS-branch-analysis/oracle_addresses/bfs.txt"
if [ ! -f "$ORACLE_FILE" ]; then
    echo "Error: Oracle addresses not found: $ORACLE_FILE"
    exit 1
fi

echo "Trace file: $TRACE"
echo "Oracle addresses: $ORACLE_FILE ($(wc -l < $ORACLE_FILE) addresses)"
echo ""
echo "Running short simulation with oracle predictor..."
echo ""

# Run short simulation with oracle predictor
timeout 120 env CHAMPSIM_ORACLE_FILE="$ORACLE_FILE" \
    ./bin/champsim \
    --warmup-instructions 100000 \
    --simulation-instructions 1000000 \
    "$TRACE" 2>&1 | grep -E "(Oracle|Branch Prediction Accuracy|cumulative IPC)"

echo ""
echo "=========================================="
echo "Test complete!"
echo "=========================================="
