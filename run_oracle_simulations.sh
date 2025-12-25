#!/bin/bash

# Script to run oracle ChampSim simulations for all traces
# Usage: ./run_oracle_simulations.sh <oracle_addresses_file>
# 
# The oracle addresses file should contain one PC (program counter) per line
# in hex format (0x...) or decimal format.

# Note: Removed 'set -e' to allow script to continue if one simulation fails

# Configuration
CHAMPSIM_BIN="/home/asamara/code/SNIPER-graphs/GraphLeto/bin/champsim"
TRACE_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/traces"
RESULTS_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/results/oracle"
ORACLE_FILE="${1:-}"

# Simulation parameters
WARMUP_INSTRUCTIONS=100000        # 100K warmup  
SIMULATION_INSTRUCTIONS=1000000   # 1M simulation (short to avoid deadlocks)

# Check if oracle file is provided
if [ -z "$ORACLE_FILE" ]; then
    echo "Error: Oracle addresses file not provided"
    echo "Usage: $0 <oracle_addresses_file>"
    echo ""
    echo "The oracle addresses file should contain one PC per line (hex or decimal)."
    echo "Example:"
    echo "  0x400abc"
    echo "  0x400def"
    echo "  4195068"
    exit 1
fi

if [ ! -f "$ORACLE_FILE" ]; then
    echo "Error: Oracle addresses file not found: $ORACLE_FILE"
    exit 1
fi

# Check if champsim binary exists
if [ ! -f "$CHAMPSIM_BIN" ]; then
    echo "Error: ChampSim binary not found at $CHAMPSIM_BIN"
    exit 1
fi

    echo ""
    echo "=========================================="
    echo "Running oracle simulation"
    echo "=========================================="
    echo "Trace: $TRACE_NAME"
    echo "Output: $LOG_FILE"
    echo "Oracle file: $ORACLE_FILE"
    echo "Warmup: $WARMUP_INSTRUCTIONS instructions"
    echo "Simulation: $SIMULATION_INSTRUCTIONS instructions"
    echo "=========================================="
    echo
    
    # Run simulation with oracle addresses via environment variable
    # The oracle predictor will load these addresses and use perfect prediction
    timeout 600 env CHAMPSIM_ORACLE_FILE="$ORACLE_FILE" $CHAMPSIM_BIN \
        --warmup-instructions $WARMUP_INSTRUCTIONS \
        --simulation-instructions $SIMULATION_INSTRUCTIONS \
        "$TRACE_FILE" 2>&1 | tee "$LOG_FILE"LOG_FILE (skipping)"
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
    # Extract key metrics
    echo ""
    echo "Key metrics for $TRACE_NAME:"
    grep "CPU 0 cumulative IPC" "$LOG_FILE" || echo "  IPC not found"
    grep "CPU 0 Branch Prediction Accuracy" "$LOG_FILE" || echo "  Branch accuracy not found"
    grep "\[Oracle BP\]" "$LOG_FILE" || echo "  Oracle statistics not found"
    grep "CPU 0 cumulative IPC" "$LOG_FILE" || echo "IPC not found"
    grep "CPU 0 Branch Prediction Accuracy" "$LOG_FILE" || echo "Branch accuracy not found"
    
# Get all trace files
TRACES=("$TRACE_DIR"/bfs_g13.champsimtrace.xz \
        "$TRACE_DIR"/bfs_g19.champsimtrace.xz \
        "$TRACE_DIR"/pr_g13.champsimtrace.xz \
        "$TRACE_DIR"/pr_g19.champsimtrace.xz)

TOTAL=${#TRACES[@]}
CURRENT=0
FAILED=0

echo ""
echo "=========================================="
echo "Running oracle simulations for all traces"
echo "Total traces: $TOTAL"
echo "Oracle file: $ORACLE_FILE ($ORACLE_COUNT addresses)"
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
echo ""
echo "Summary of results:"
echo ""
for LOG_FILE in "$RESULTS_DIR"/*.log; do
    if [ -f "$LOG_FILE" ]; then
        echo "=== $(basename $LOG_FILE .log) ==="
        grep "CPU 0 cumulative IPC" "$LOG_FILE" 2>/dev/null || echo "  IPC: Not found"
        grep "CPU 0 Branch Prediction Accuracy" "$LOG_FILE" 2>/dev/null || echo "  Branch Accuracy: Not found"
        echo "  Oracle stats:"
        grep "\[Oracle BP\]" "$LOG_FILE" 2>/dev/null | sed 's/^/    /' || echo "    Oracle statistics not found"
        echo ""
    fi
done    echo ""
        echo "$(basename $LOG_FILE .log):"
        grep "CPU 0 cumulative IPC" "$LOG_FILE" 2>/dev/null || echo "  IPC: Not found"
        grep "CPU 0 Branch Prediction Accuracy" "$LOG_FILE" 2>/dev/null || echo "  Branch Accuracy: Not found"
    fi
done
