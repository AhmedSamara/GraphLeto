#!/bin/bash

# Script to run baseline ChampSim simulations for all traces
# Usage: ./run_baseline_simulations.sh

set -e  # Exit on first error

# Configuration
CHAMPSIM_BIN="/home/asamara/code/SNIPER-graphs/GraphLeto/bin/champsim"
TRACE_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/traces"
RESULTS_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/results/baseline"

# Simulation parameters
WARMUP_INSTRUCTIONS=100000        # 100K warmup  
SIMULATION_INSTRUCTIONS=1000000   # 1M simulation (short to avoid deadlocks)

# Check if champsim binary exists
if [ ! -f "$CHAMPSIM_BIN" ]; then
    echo "Error: ChampSim binary not found at $CHAMPSIM_BIN"
    exit 1
fi

# Create results directory
mkdir -p "$RESULTS_DIR"

# Function to run a single simulation
run_simulation() {
    local TRACE_FILE=$1
    local TRACE_NAME=$(basename "$TRACE_FILE" .champsimtrace.xz)
    local LOG_FILE="${RESULTS_DIR}/${TRACE_NAME}.log"
    
    # Skip if results already exist and contain completion data
    if [ -f "$LOG_FILE" ] && grep -q "cumulative IPC" "$LOG_FILE"; then
        echo "Valid results already exist: $LOG_FILE (skipping)"
        return 0
    fi
    
    # Remove old log if it exists (may be from failed run)
    rm -f "$LOG_FILE"
    
    echo ""
    echo "=========================================="
    echo "Running baseline simulation"
    echo "=========================================="
    echo "Trace: $TRACE_NAME"
    echo "Output: $LOG_FILE"
    echo "Warmup: $WARMUP_INSTRUCTIONS instructions"
    echo "Simulation: $SIMULATION_INSTRUCTIONS instructions"
    echo "=========================================="
    echo
    
    # Run simulation with timeout to prevent hanging
    timeout 600 $CHAMPSIM_BIN \
        --warmup-instructions $WARMUP_INSTRUCTIONS \
        --simulation-instructions $SIMULATION_INSTRUCTIONS \
        "$TRACE_FILE" 2>&1 | tee "$LOG_FILE"
    
    if [ ${PIPESTATUS[0]} -eq 124 ]; then
        echo "Error: Simulation timed out after 600 seconds for $TRACE_NAME"
        return 1
    elif [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "Error: Simulation failed for $TRACE_NAME"
        return 1
    fi
    
    # Extract key metrics
    echo ""
    echo "Key metrics for $TRACE_NAME:"
    grep "CPU 0 cumulative IPC" "$LOG_FILE" || echo "IPC not found"
    grep "CPU 0 Branch Prediction Accuracy" "$LOG_FILE" || echo "Branch accuracy not found"
    
    return 0
}

# Get all trace files
TRACES=("$TRACE_DIR"/bfs_g13.champsimtrace.xz)
        # "$TRACE_DIR"/bfs_g19.champsimtrace.xz \
        # "$TRACE_DIR"/pr_g13.champsimtrace.xz \
        # "$TRACE_DIR"/pr_g19.champsimtrace.xz)

TOTAL=${#TRACES[@]}
CURRENT=0
FAILED=0

echo "=========================================="
echo "Running baseline simulations for all traces"
echo "Total traces: $TOTAL"
echo "=========================================="

for TRACE_FILE in "${TRACES[@]}"; do
    if [ ! -f "$TRACE_FILE" ]; then
        echo "Warning: Trace file not found: $TRACE_FILE"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    CURRENT=$((CURRENT + 1))
    echo ""
    echo "Progress: $CURRENT/$TOTAL"
    
    if ! run_simulation "$TRACE_FILE"; then
        FAILED=$((FAILED + 1))
        echo "WARNING: Simulation failed for $(basename $TRACE_FILE)"
    fi
done

echo ""
echo "=========================================="
echo "All simulations complete!"
echo "Success: $((TOTAL - FAILED))/$TOTAL"
if [ $FAILED -gt 0 ]; then
    echo "Failed: $FAILED"
fi
echo "=========================================="
echo ""
echo "Results directory: $RESULTS_DIR"
echo ""
echo "Summary of results:"
for LOG_FILE in "$RESULTS_DIR"/*.log; do
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "$(basename $LOG_FILE .log):"
        grep "CPU 0 cumulative IPC" "$LOG_FILE" 2>/dev/null || echo "  IPC: Not found"
        grep "CPU 0 Branch Prediction Accuracy" "$LOG_FILE" 2>/dev/null || echo "  Branch Accuracy: Not found"
    fi
done
