#!/bin/bash

# Run CacheBP simulations with different configurations
# Usage: ./run_cachebp_simulations.sh [benchmark1] [benchmark2] ...

set -e

# Configuration
TRACE_DIR="traces"
RESULTS_DIR="results/cachebp"
CORRELATIONS_DIR="correlations"
WARMUP_INSTRUCTIONS=100000
SIMULATION_INSTRUCTIONS=1000000

# Benchmarks to run (default: all graph benchmarks)
if [ $# -eq 0 ]; then
    BENCHMARKS=(bfs pr bc cc cc_sv sssp tc)
else
    BENCHMARKS=("$@")
fi

# Graphs to test
GRAPHS=(g13 g19)

# CacheBP configurations to sweep
# Format: "binary_name:bdt_sets:bdt_ways:description"
CONFIGS=(
    "champsim_cachebp_256x4_oc1024:256:4:256x4"
    "champsim_cachebp_512x4_oc2048:512:4:512x4"
    "champsim_cachebp_1024x8_oc4096:1024:8:1024x8"
)

# Create results directory
mkdir -p "$RESULTS_DIR"
mkdir -p "$CORRELATIONS_DIR"

echo "========================================="
echo "CacheBP Simulation Suite"
echo "========================================="
echo "Benchmarks: ${BENCHMARKS[@]}"
echo "Graphs: ${GRAPHS[@]}"
echo "Configurations: ${#CONFIGS[@]}"
echo "Warmup: ${WARMUP_INSTRUCTIONS} instructions"
echo "Simulation: ${SIMULATION_INSTRUCTIONS} instructions"
echo ""

# Extract branch-data correlations if needed
extract_correlations() {
    local benchmark=$1
    local graph=$2
    local trace_file="${TRACE_DIR}/${benchmark}_${graph}.champsimtrace.xz"
    local corr_file="${CORRELATIONS_DIR}/${benchmark}_${graph}.csv"
    
    if [ ! -f "$corr_file" ]; then
        echo "  [Extracting correlations for ${benchmark}_${graph}...]"
        # Use a limited number of instructions for correlation extraction (faster)
        python3 extract_branch_data_correlations.py "$trace_file" 5000000 10 > "$corr_file" 2>&1 || {
            echo "    Warning: Correlation extraction failed, will run without correlations"
            rm -f "$corr_file"
        }
        
        if [ -f "$corr_file" ]; then
            local num_corr=$(grep -v "^#" "$corr_file" | wc -l)
            echo "    Extracted $num_corr correlations"
        fi
    else
        local num_corr=$(grep -v "^#" "$corr_file" | wc -l)
        echo "  [Using existing correlations: $num_corr entries]"
    fi
}

# Run simulations
total_runs=$((${#BENCHMARKS[@]} * ${#GRAPHS[@]} * ${#CONFIGS[@]}))
current_run=0

for BENCHMARK in "${BENCHMARKS[@]}"; do
    for GRAPH in "${GRAPHS[@]}"; do
        TRACE_FILE="$TRACE_DIR/${BENCHMARK}_${GRAPH}.champsimtrace.xz"
        
        # Check if trace exists
        if [ ! -f "$TRACE_FILE" ]; then
            echo "Warning: Trace not found: $TRACE_FILE"
            continue
        fi
        
        # Extract correlations for this benchmark+graph
        CORR_FILE="$CORRELATIONS_DIR/${BENCHMARK}_${GRAPH}.csv"
        extract_correlations "$BENCHMARK" "$GRAPH"
        
        for CONFIG in "${CONFIGS[@]}"; do
            current_run=$((current_run + 1))
            
            # Parse configuration
            IFS=':' read -r BINARY BDT_SETS BDT_WAYS CONFIG_NAME <<< "$CONFIG"
            
            CHAMPSIM_BIN="bin/$BINARY"
            
            if [ ! -f "$CHAMPSIM_BIN" ]; then
                echo "[$current_run/$total_runs] Warning: Binary not found: $CHAMPSIM_BIN"
                echo "  Run: ./config.sh champsim_config_cachebp_${CONFIG_NAME}_oc*.json && make"
                continue
            fi
            
            LOG_FILE="$RESULTS_DIR/${BENCHMARK}_${GRAPH}_${CONFIG_NAME}.log"
            
            echo "[$current_run/$total_runs] Running: $BENCHMARK $GRAPH (Config: $CONFIG_NAME)"
            echo "  Binary: $CHAMPSIM_BIN"
            echo "  BDT: ${BDT_SETS} sets x ${BDT_WAYS} ways"
            if [ -f "$CORR_FILE" ]; then
                echo "  Correlations: $CORR_FILE"
            else
                echo "  Correlations: None (will use dynamic BDT only)"
            fi
            echo "  Log: $LOG_FILE"
            
            # Set environment variables for CacheBP configuration
            export CACHEBP_BDT_SETS=$BDT_SETS
            export CACHEBP_BDT_WAYS=$BDT_WAYS
            if [ -f "$CORR_FILE" ]; then
                export CACHEBP_CORRELATIONS="$CORR_FILE"
            else
                unset CACHEBP_CORRELATIONS
            fi
            
            # Run simulation with timeout
            timeout 600 $CHAMPSIM_BIN \
                --warmup-instructions $WARMUP_INSTRUCTIONS \
                --simulation-instructions $SIMULATION_INSTRUCTIONS \
                "$TRACE_FILE" 2>&1 | tee "$LOG_FILE"
            
            exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "  WARNING: Simulation timed out (600s)"
            elif [ $exit_code -ne 0 ]; then
                echo "  WARNING: Simulation failed with exit code $exit_code"
            else
                # Extract key metrics
                IPC=$(grep "cumulative IPC:" "$LOG_FILE" | tail -1 | awk '{print $7}')
                MPKI=$(grep "MPKI:" "$LOG_FILE" | head -1 | awk '{print $5}')
                ACCURACY=$(grep "Branch Prediction Accuracy:" "$LOG_FILE" | awk '{print $5}')
                BDT_HIT=$(grep "BDT hit rate:" "$LOG_FILE" | tail -1 | awk '{print $4}')
                
                echo "  Results: IPC=$IPC MPKI=$MPKI Accuracy=$ACCURACY BDT_Hit=$BDT_HIT"
            fi
            
            echo ""
        done
    done
done

echo "========================================="
echo "CacheBP simulations complete!"
echo "Results saved in: $RESULTS_DIR/"
echo "========================================="
echo ""
echo "To compare results:"
echo "  grep 'cumulative IPC:' results/cachebp/*.log"
echo "  grep 'BDT hit rate:' results/cachebp/*.log"
echo "  grep 'Outcome Cache accuracy:' results/cachebp/*.log"
