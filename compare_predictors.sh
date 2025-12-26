#!/bin/bash

# Compare Baseline, CacheBP, and Oracle Branch Predictors
# Usage: ./compare_predictors.sh [benchmark1] [benchmark2] ...

set -e

# Directories
BASELINE_DIR="results/baseline"
CACHEBP_DIR="results/cachebp"
ORACLE_DIR="results/oracle"
OUTPUT_FILE="predictor_comparison.txt"

# Benchmarks to compare (default: all graph benchmarks)
if [ $# -eq 0 ]; then
    BENCHMARKS=(bfs pr bc cc cc_sv sssp tc)
else
    BENCHMARKS=("$@")
fi

# Graphs to compare
GRAPHS=(g13 g19)

# CacheBP configurations
CACHEBP_CONFIGS=("64x4" "128x4" "256x4" "1024x4" "2048x4" "4096x4" "8192x4" "86636x4" "1048576x4")

echo "========================================="
echo "Branch Predictor Comparison"
echo "========================================="
echo "Comparing: Baseline vs CacheBP vs Oracle"
echo "Benchmarks: ${BENCHMARKS[@]}"
echo "Graphs: ${GRAPHS[@]}"
echo "Output: $OUTPUT_FILE"
echo ""

# Function to extract metric from log file
extract_metric() {
    local log_file=$1
    local metric=$2
    
    if [ ! -f "$log_file" ]; then
        echo "N/A"
        return
    fi
    
    case $metric in
        "ipc")
            grep "cumulative IPC:" "$log_file" | tail -1 | awk '{print $7}' || echo "N/A"
            ;;
        "mpki")
            grep "Branch Prediction Accuracy:" "$log_file" | head -1 | awk '{print $5}' || echo "N/A"
            ;;
        "accuracy")
            grep "Branch Prediction Accuracy:" "$log_file" | head -1 | awk '{gsub(/%/,""); print $4}' || echo "N/A"
            ;;
        "bdt_hit")
            grep "BDT hit rate:" "$log_file" | tail -1 | awk '{gsub(/%/,""); print $4}' || echo "N/A"
            ;;
        "oc_accuracy")
            grep "Outcome Cache accuracy:" "$log_file" | tail -1 | awk '{gsub(/%/,""); print $4}' || echo "N/A"
            ;;
        "oracle_predictions")
            grep "Oracle predictions:" "$log_file" | tail -1 | awk '{print $4}' || echo "N/A"
            ;;
        "oracle_accuracy")
            grep "Oracle accuracy:" "$log_file" | tail -1 | awk '{gsub(/%/,""); print $3}' || echo "N/A"
            ;;
    esac
}

# Function to calculate improvement percentage
calc_improvement() {
    local baseline=$1
    local improved=$2
    
    if [ "$baseline" == "N/A" ] || [ "$improved" == "N/A" ]; then
        echo "N/A"
        return
    fi
    
    # Use bc for floating point arithmetic
    echo "scale=2; (($improved - $baseline) / $baseline) * 100" | bc 2>/dev/null || echo "N/A"
}

# Start output file
{
    echo "========================================================================"
    echo "Branch Predictor Comparison Report"
    echo "Generated: $(date)"
    echo "========================================================================"
    echo ""
    
    for BENCHMARK in "${BENCHMARKS[@]}"; do
        for GRAPH in "${GRAPHS[@]}"; do
            echo "========================================================================"
            echo "Benchmark: $BENCHMARK, Graph: $GRAPH"
            echo "========================================================================"
            echo ""
            
            BASELINE_LOG="${BASELINE_DIR}/${BENCHMARK}_${GRAPH}.log"
            ORACLE_LOG="${ORACLE_DIR}/${BENCHMARK}_${GRAPH}.log"
            
            # Check if baseline exists
            if [ ! -f "$BASELINE_LOG" ]; then
                echo "  Warning: Baseline log not found: $BASELINE_LOG"
                echo ""
                continue
            fi
            
            # Extract baseline metrics
            BASELINE_IPC=$(extract_metric "$BASELINE_LOG" "ipc")
            BASELINE_MPKI=$(extract_metric "$BASELINE_LOG" "mpki")
            BASELINE_ACC=$(extract_metric "$BASELINE_LOG" "accuracy")
            
            # Extract oracle metrics
            ORACLE_IPC=$(extract_metric "$ORACLE_LOG" "ipc")
            ORACLE_MPKI=$(extract_metric "$ORACLE_LOG" "mpki")
            ORACLE_ACC=$(extract_metric "$ORACLE_LOG" "accuracy")
            ORACLE_PRED=$(extract_metric "$ORACLE_LOG" "oracle_predictions")
            ORACLE_ORAC_ACC=$(extract_metric "$ORACLE_LOG" "oracle_accuracy")
            
            # Print baseline
            echo "BASELINE (Bimodal):"
            echo "  IPC:              $BASELINE_IPC"
            echo "  Branch Accuracy:  ${BASELINE_ACC}%"
            echo "  MPKI:             $BASELINE_MPKI"
            echo ""
            
            # Print CacheBP results for each configuration
            for CONFIG in "${CACHEBP_CONFIGS[@]}"; do
                CACHEBP_LOG="${CACHEBP_DIR}/${BENCHMARK}_${GRAPH}_${CONFIG}.log"
                
                if [ ! -f "$CACHEBP_LOG" ]; then
                    echo "CACHEBP ($CONFIG): Log not found"
                    echo ""
                    continue
                fi
                
                CACHEBP_IPC=$(extract_metric "$CACHEBP_LOG" "ipc")
                CACHEBP_MPKI=$(extract_metric "$CACHEBP_LOG" "mpki")
                CACHEBP_ACC=$(extract_metric "$CACHEBP_LOG" "accuracy")
                CACHEBP_BDT=$(extract_metric "$CACHEBP_LOG" "bdt_hit")
                CACHEBP_OC=$(extract_metric "$CACHEBP_LOG" "oc_accuracy")
                
                IPC_IMP=$(calc_improvement "$BASELINE_IPC" "$CACHEBP_IPC")
                ACC_IMP=$(calc_improvement "$BASELINE_ACC" "$CACHEBP_ACC")
                
                echo "CACHEBP ($CONFIG):"
                echo "  IPC:              $CACHEBP_IPC (${IPC_IMP}% vs baseline)"
                echo "  Branch Accuracy:  ${CACHEBP_ACC}% (${ACC_IMP}% vs baseline)"
                echo "  MPKI:             $CACHEBP_MPKI"
                echo "  BDT Hit Rate:     ${CACHEBP_BDT}%"
                echo "  OC Accuracy:      ${CACHEBP_OC}%"
                echo ""
            done
            
            # Print oracle
            if [ -f "$ORACLE_LOG" ]; then
                ORACLE_IPC_IMP=$(calc_improvement "$BASELINE_IPC" "$ORACLE_IPC")
                ORACLE_ACC_IMP=$(calc_improvement "$BASELINE_ACC" "$ORACLE_ACC")
                
                echo "ORACLE (Perfect Prediction on Select Branches):"
                echo "  IPC:              $ORACLE_IPC (${ORACLE_IPC_IMP}% vs baseline)"
                echo "  Branch Accuracy:  ${ORACLE_ACC}% (${ORACLE_ACC_IMP}% vs baseline)"
                echo "  MPKI:             $ORACLE_MPKI"
                echo "  Oracle Branches:  $ORACLE_PRED predictions"
                echo "  Oracle Accuracy:  ${ORACLE_ORAC_ACC}%"
            else
                echo "ORACLE: Log not found"
            fi
            
            echo ""
            echo "------------------------------------------------------------------------"
            echo ""
        done
    done
    
    echo "========================================================================"
    echo "Summary Statistics"
    echo "========================================================================"
    echo ""
    
    # Calculate average improvements across all benchmarks
    echo "Average IPC Improvements (vs Baseline):"
    echo ""
    
    for CONFIG in "${CACHEBP_CONFIGS[@]}"; do
        total_imp=0
        count=0
        
        for BENCHMARK in "${BENCHMARKS[@]}"; do
            for GRAPH in "${GRAPHS[@]}"; do
                BASELINE_LOG="${BASELINE_DIR}/${BENCHMARK}_${GRAPH}.log"
                CACHEBP_LOG="${CACHEBP_DIR}/${BENCHMARK}_${GRAPH}_${CONFIG}.log"
                
                if [ -f "$BASELINE_LOG" ] && [ -f "$CACHEBP_LOG" ]; then
                    BASELINE_IPC=$(extract_metric "$BASELINE_LOG" "ipc")
                    CACHEBP_IPC=$(extract_metric "$CACHEBP_LOG" "ipc")
                    IMP=$(calc_improvement "$BASELINE_IPC" "$CACHEBP_IPC")
                    
                    if [ "$IMP" != "N/A" ]; then
                        total_imp=$(echo "$total_imp + $IMP" | bc)
                        count=$((count + 1))
                    fi
                fi
            done
        done
        
        if [ $count -gt 0 ]; then
            avg=$(echo "scale=2; $total_imp / $count" | bc)
            echo "  CacheBP ($CONFIG): ${avg}% (across $count runs)"
        fi
    done
    
    # Oracle average
    total_imp=0
    count=0
    
    for BENCHMARK in "${BENCHMARKS[@]}"; do
        for GRAPH in "${GRAPHS[@]}"; do
            BASELINE_LOG="${BASELINE_DIR}/${BENCHMARK}_${GRAPH}.log"
            ORACLE_LOG="${ORACLE_DIR}/${BENCHMARK}_${GRAPH}.log"
            
            if [ -f "$BASELINE_LOG" ] && [ -f "$ORACLE_LOG" ]; then
                BASELINE_IPC=$(extract_metric "$BASELINE_LOG" "ipc")
                ORACLE_IPC=$(extract_metric "$ORACLE_LOG" "ipc")
                IMP=$(calc_improvement "$BASELINE_IPC" "$ORACLE_IPC")
                
                if [ "$IMP" != "N/A" ]; then
                    total_imp=$(echo "$total_imp + $IMP" | bc)
                    count=$((count + 1))
                fi
            fi
        done
    done
    
    if [ $count -gt 0 ]; then
        avg=$(echo "scale=2; $total_imp / $count" | bc)
        echo "  Oracle:           ${avg}% (across $count runs)"
    fi
    
    echo ""
    echo "========================================================================"
    echo "Best Configuration Analysis"
    echo "========================================================================"
    echo ""
    
    # Find best CacheBP configuration for each benchmark
    for BENCHMARK in "${BENCHMARKS[@]}"; do
        for GRAPH in "${GRAPHS[@]}"; do
            BASELINE_LOG="${BASELINE_DIR}/${BENCHMARK}_${GRAPH}.log"
            
            if [ ! -f "$BASELINE_LOG" ]; then
                continue
            fi
            
            BASELINE_IPC=$(extract_metric "$BASELINE_LOG" "ipc")
            best_config="None"
            best_ipc="0"
            best_imp="0"
            
            for CONFIG in "${CACHEBP_CONFIGS[@]}"; do
                CACHEBP_LOG="${CACHEBP_DIR}/${BENCHMARK}_${GRAPH}_${CONFIG}.log"
                
                if [ -f "$CACHEBP_LOG" ]; then
                    CACHEBP_IPC=$(extract_metric "$CACHEBP_LOG" "ipc")
                    
                    if [ "$CACHEBP_IPC" != "N/A" ]; then
                        # Compare using bc
                        if [ $(echo "$CACHEBP_IPC > $best_ipc" | bc) -eq 1 ]; then
                            best_ipc="$CACHEBP_IPC"
                            best_config="$CONFIG"
                            best_imp=$(calc_improvement "$BASELINE_IPC" "$CACHEBP_IPC")
                        fi
                    fi
                fi
            done
            
            if [ "$best_config" != "None" ]; then
                echo "${BENCHMARK}_${GRAPH}: Best = $best_config (IPC=$best_ipc, +${best_imp}%)"
            fi
        done
    done
    
    echo ""
    echo "========================================================================"
    echo "End of Report"
    echo "========================================================================"
    
} | tee "$OUTPUT_FILE"

echo ""
echo "Comparison complete! Results saved to: $OUTPUT_FILE"
echo ""
echo "Quick view commands:"
echo "  less $OUTPUT_FILE"
echo "  grep 'IPC:' $OUTPUT_FILE"
echo "  grep 'Best =' $OUTPUT_FILE"
