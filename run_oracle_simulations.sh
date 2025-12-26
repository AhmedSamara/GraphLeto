#!/bin/bash

# Script to run oracle ChampSim simulations for multiple benchmarks
# Usage: ./run_oracle_simulations.sh <oracle_addresses_dir> [benchmark1] [benchmark2] ...
# 
# Example:
#   ./run_oracle_simulations.sh GABPS-branch-analysis/oracle_addresses bfs pr
#   ./run_oracle_simulations.sh GABPS-branch-analysis/oracle_addresses bfs  # Just bfs
#   ./run_oracle_simulations.sh GABPS-branch-analysis/oracle_addresses      # All benchmarks

# Configuration
CHAMPSIM_BIN="/home/asamara/code/SNIPER-graphs/GraphLeto/bin/champsim"
TRACE_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/traces"
RESULTS_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/results/oracle"
ORACLE_DIR="${1:-}"

# Simulation parameters
WARMUP_INSTRUCTIONS=100000        # 100K warmup  
SIMULATION_INSTRUCTIONS=1000000   # 1M simulation (short to avoid deadlocks)

# Check if oracle directory is provided
if [ -z "$ORACLE_DIR" ]; then
    echo "Error: Oracle addresses directory not provided"
    echo "Usage: $0 <oracle_addresses_dir> [benchmark1] [benchmark2] ..."
    echo ""
    echo "Example:"
    echo "  $0 GABPS-branch-analysis/oracle_addresses bfs pr"
    echo "  $0 GABPS-branch-analysis/oracle_addresses bfs"
    echo "  $0 GABPS-branch-analysis/oracle_addresses  # All benchmarks"
    exit 1
fi

if [ ! -d "$ORACLE_DIR" ]; then
    echo "Error: Oracle addresses directory not found: $ORACLE_DIR"
    exit 1
fi

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
    local ORACLE_FILE=$2
    local TRACE_NAME=$(basename "$TRACE_FILE" .champsimtrace.xz)
    local LOG_FILE="$RESULTS_DIR/${TRACE_NAME}.log"
    
    # Check if valid results already exist
    if [ -f "$LOG_FILE" ] && grep -q "cumulative IPC" "$LOG_FILE"; then
        echo "Valid results already exist: $LOG_FILE (skipping)"
        return 0
    fi
    
    # Check if oracle file exists
    if [ ! -f "$ORACLE_FILE" ]; then
        echo "Warning: Oracle file not found: $ORACLE_FILE (skipping)"
        return 1
    fi
    
    ORACLE_COUNT=$(grep -v "^#" "$ORACLE_FILE" | grep -v "^$" | wc -l)
    
    # Remove old log if it exists (may be from failed run)
    rm -f "$LOG_FILE"
    
    echo ""
    echo "=========================================="
    echo "Running oracle simulation"
    echo "=========================================="
    echo "Trace: $TRACE_NAME"
    echo "Oracle file: $ORACLE_FILE ($ORACLE_COUNT addresses)"
    echo "Output: $LOG_FILE"
    echo "Warmup: $WARMUP_INSTRUCTIONS instructions"
    echo "Simulation: $SIMULATION_INSTRUCTIONS instructions"
    echo "=========================================="
    echo
    
    # Run simulation with oracle addresses via environment variable
    # The oracle predictor will load these addresses and use perfect prediction
    timeout 600 env CHAMPSIM_ORACLE_FILE="$ORACLE_FILE" $CHAMPSIM_BIN \
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
    grep "CPU 0 cumulative IPC" "$LOG_FILE" || echo "  IPC not found"
    grep "CPU 0 Branch Prediction Accuracy" "$LOG_FILE" || echo "  Branch accuracy not found"
    grep "\[Oracle BP\]" "$LOG_FILE" || echo "  Oracle statistics not found"
    
    return 0
}

# Get list of benchmarks to run
shift  # Remove oracle_dir argument

if [ $# -eq 0 ]; then
    # No benchmarks specified - run all available
    BENCHMARKS=(bfs pr bc cc cc_sv sssp tc)
    echo "No benchmarks specified - will run all available: ${BENCHMARKS[@]}"
else
    # Use specified benchmarks
    BENCHMARKS=("$@")
    echo "Running specified benchmarks: ${BENCHMARKS[@]}"
fi

# Graph inputs to process
GRAPHS=(g13 g19)

echo ""
echo "=========================================="
echo "Oracle Simulation Configuration"
echo "=========================================="
echo "Oracle directory: $ORACLE_DIR"
echo "Benchmarks: ${BENCHMARKS[@]}"
echo "Graphs: ${GRAPHS[@]}"
echo "Total simulations: $((${#BENCHMARKS[@]} * ${#GRAPHS[@]}))"
echo "=========================================="

TOTAL=0
CURRENT=0
FAILED=0
SKIPPED=0

# Count total simulations
for BENCHMARK in "${BENCHMARKS[@]}"; do
    for GRAPH in "${GRAPHS[@]}"; do
        TRACE_FILE="$TRACE_DIR/${BENCHMARK}_${GRAPH}.champsimtrace.xz"
        ORACLE_FILE="$ORACLE_DIR/${BENCHMARK}.txt"
        if [ -f "$TRACE_FILE" ] && [ -f "$ORACLE_FILE" ]; then
            TOTAL=$((TOTAL + 1))
        fi
    done
done

echo ""
echo "Found $TOTAL trace+oracle pairs to simulate"
echo ""

# Run simulations
for BENCHMARK in "${BENCHMARKS[@]}"; do
    ORACLE_FILE="$ORACLE_DIR/${BENCHMARK}.txt"
    
    if [ ! -f "$ORACLE_FILE" ]; then
        echo "Warning: Oracle file not found for $BENCHMARK: $ORACLE_FILE (skipping all)"
        continue
    fi
    
    for GRAPH in "${GRAPHS[@]}"; do
        TRACE_FILE="$TRACE_DIR/${BENCHMARK}_${GRAPH}.champsimtrace.xz"
        
        if [ ! -f "$TRACE_FILE" ]; then
            echo "Warning: Trace file not found: $TRACE_FILE (skipping)"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        
        CURRENT=$((CURRENT + 1))
        echo ""
        echo "Progress: $CURRENT/$TOTAL"
        
        if ! run_simulation "$TRACE_FILE" "$ORACLE_FILE"; then
            FAILED=$((FAILED + 1))
            echo "WARNING: Simulation failed for ${BENCHMARK}_${GRAPH}"
        fi
    done
done

echo ""
echo "=========================================="
echo "All simulations complete!"
echo "=========================================="
echo "Total attempted: $TOTAL"
echo "Success: $((TOTAL - FAILED - SKIPPED))"
if [ $FAILED -gt 0 ]; then
    echo "Failed: $FAILED"
fi
if [ $SKIPPED -gt 0 ]; then
    echo "Skipped: $SKIPPED"
fi
echo "=========================================="

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
done

echo ""
echo "Results saved to: $RESULTS_DIR"
echo ""
