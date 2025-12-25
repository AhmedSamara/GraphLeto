#!/bin/bash

# Script to generate ChampSim traces for GAPBS benchmarks
# Usage: ./generate_GABPS-branch-analysis_traces.sh [graph_num] [algorithm]
#   If no arguments provided, generates all traces for BFS/PR on g13/g19

set -e

# Configuration
PIN_ROOT="/home/asamara/code/GraphLeto/tracer/pin/pin-3.22-98547-g7a303a835-gcc-linux"
TRACER_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/tracer/pin"
TRACER="${TRACER_DIR}/obj-intel64/champsim_tracer.so"
GAPBS_BIN_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/GABPS-branch-analysis"  # Use annotated binaries for exact PC matching
TRACE_OUTPUT_DIR="/home/asamara/code/SNIPER-graphs/GraphLeto/traces"
GRAPH_DIR="/home/asamara/code/SNIPER-graphs/real_graphs"

# Tracing parameters
SKIP_INSTRUCTIONS=1000000       # Skip first 1M instructions (initialization)
TRACE_INSTRUCTIONS=50000000     # Trace 50M instructions (reasonable size for analysis)

# Graph configurations - using .sg files
declare -A GRAPH_ARGS
GRAPH_ARGS["g13"]="-sf ${GRAPH_DIR}/g13.sg -n 1"
GRAPH_ARGS["g19"]="-sf ${GRAPH_DIR}/g19.sg -n 1"
GRAPH_ARGS["roadsCA"]="-sf ${GRAPH_DIR}/roadsCA.1965206.2766607.sg -n 1"
GRAPH_ARGS["orkut"]="-sf ${GRAPH_DIR}/orkut.3072441.117185083.sg -n 1"

# Check if tracer exists
if [ ! -f "$TRACER" ]; then
    echo "Error: Tracer not found at $TRACER"
    echo "Please build the tracer first: cd $TRACER_DIR && make"
    exit 1
fi

# Create output directory
mkdir -p "$TRACE_OUTPUT_DIR"

# Function to generate a single trace
generate_trace() {
    local ALGORITHM=$1
    local GRAPH_NUM=$2
    
    BINARY="${GAPBS_BIN_DIR}/${ALGORITHM}"
    if [ ! -f "$BINARY" ]; then
        echo "Error: Binary not found: $BINARY"
        return 1
    fi
    
    # Generate trace filename
    TRACE_FILE="${TRACE_OUTPUT_DIR}/${ALGORITHM}_${GRAPH_NUM}.champsimtrace"
    TRACE_FILE_XZ="${TRACE_FILE}.xz"
    
    # Skip if trace already exists
    if [ -f "$TRACE_FILE_XZ" ]; then
        echo "Trace already exists: $TRACE_FILE_XZ (skipping)"
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "Generating ChampSim trace for GAPBS"
    echo "=========================================="
    echo "Algorithm: $ALGORITHM"
    echo "Graph: $GRAPH_NUM"
    echo "Binary: $BINARY"
    echo "Arguments: ${GRAPH_ARGS[$GRAPH_NUM]}"
    echo "Trace output: $TRACE_FILE_XZ"
    echo "Skip instructions: $SKIP_INSTRUCTIONS"
    echo "Trace instructions: $TRACE_INSTRUCTIONS"
    echo "=========================================="
    echo
    
    # Run PIN tracer
    echo "Running PIN tracer (this may take a while)..."
    $PIN_ROOT/pin -t $TRACER \
        -o $TRACE_FILE \
        -s $SKIP_INSTRUCTIONS \
        -t $TRACE_INSTRUCTIONS \
        -- $BINARY ${GRAPH_ARGS[$GRAPH_NUM]} 2>&1 | grep -v "Tool (or Pin) caused signal"
    
    # PIN may segfault on exit with OpenMP binaries, but trace is usually complete
    # Check if trace file was created successfully instead of checking exit code
    if [ ! -f "$TRACE_FILE" ] || [ ! -s "$TRACE_FILE" ]; then
        echo "Error: Trace file not created or empty: ${TRACE_FILE}"
        return 1
    fi
    
    echo "Trace file created successfully ($(du -h "$TRACE_FILE" | cut -f1))"
    
    # Compress the trace
    echo
    echo "Compressing trace with xz..."
    xz -z -9 -T0 $TRACE_FILE
    
    if [ $? -ne 0 ]; then
        echo "Error: Compression failed for ${ALGORITHM}_${GRAPH_NUM}"
        return 1
    fi
    
    echo
    echo "=========================================="
    echo "Trace generation complete!"
    echo "Output: $TRACE_FILE_XZ"
    TRACE_SIZE=$(du -h "$TRACE_FILE_XZ" | cut -f1)
    echo "Size: $TRACE_SIZE"
    echo "=========================================="
    
    return 0
}

# If arguments provided, generate single trace
if [ $# -ge 1 ]; then
    GRAPH_NUM=${1}
    ALGORITHM=${2:-"bfs"}
    
    # Validate inputs
    if [ ! -v "GRAPH_ARGS[$GRAPH_NUM]" ]; then
        echo "Error: Unknown graph '$GRAPH_NUM'"
        echo "Available graphs: ${!GRAPH_ARGS[@]}"
        exit 1
    fi
    
    generate_trace "$ALGORITHM" "$GRAPH_NUM"
    
    echo ""
    echo "To run simulation:"
    echo "  cd /home/asamara/code/SNIPER-graphs/GraphLeto"
    echo "  bin/champsim --warmup_instructions 10000000 --simulation_instructions 50000000 traces/${ALGORITHM}_${GRAPH_NUM}.champsimtrace.xz"
else
    # Generate all traces for BFS and PR on g13 and g19
    echo "=========================================="
    echo "Generating all traces for BFS/PR on g13/g19"
    echo "=========================================="
    
    ALGORITHMS=("bfs" "pr")
    GRAPHS=("g13" "g19")
    
    TOTAL=$((${#ALGORITHMS[@]} * ${#GRAPHS[@]}))
    CURRENT=0
    FAILED=0
    
    for ALGORITHM in "${ALGORITHMS[@]}"; do
        for GRAPH_NUM in "${GRAPHS[@]}"; do
            CURRENT=$((CURRENT + 1))
            echo ""
            echo "Progress: $CURRENT/$TOTAL"
            
            if ! generate_trace "$ALGORITHM" "$GRAPH_NUM"; then
                FAILED=$((FAILED + 1))
                echo "WARNING: Failed to generate ${ALGORITHM}_${GRAPH_NUM}"
            fi
        done
    done
    
    echo ""
    echo "=========================================="
    echo "All trace generation complete!"
    echo "Success: $((TOTAL - FAILED))/$TOTAL"
    if [ $FAILED -gt 0 ]; then
        echo "Failed: $FAILED"
    fi
    echo "=========================================="
    echo ""
    echo "Generated traces:"
    ls -lh "${TRACE_OUTPUT_DIR}"/*.champsimtrace.xz 2>/dev/null || echo "No traces found"
fi
