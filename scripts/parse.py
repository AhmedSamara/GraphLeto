#!/usr/bin/env python3

import os
import json
import csv
import argparse

def calculate_hit_rate(hits, misses):
    """Calculate hit rate from hits and misses."""
    total = hits + misses
    return (hits / total) if total else 0

def calculate_mpki(total_mispredictions, instructions):
    """Calculate MPKI (Mispredictions Per Thousand Instructions)."""
    return (total_mispredictions / instructions) * 1000 if instructions else 0

def process_json_file(filepath):
    """Extract statistics from a JSON file."""
    with open(filepath, 'r') as file:
        data = json.load(file)[0]  # Assuming the relevant data is the first entry

    # Extract core statistics
    cores_data = data['roi']['cores'][0]  # Assuming we're interested in the first core's data
    instructions = cores_data['instructions']
    cycles = cores_data['cycles']
    ipc = instructions / cycles if cycles else 0

    # Extract cache hit rates
    l1d_hits = data['roi']['cpu0_L1D']['LOAD']['hit'][0]
    l1d_misses = data['roi']['cpu0_L1D']['LOAD']['miss'][0]
    l1d_hit_rate = calculate_hit_rate(l1d_hits, l1d_misses)

    l2_hits = data['roi']['cpu0_L2C']['LOAD']['hit'][0]
    l2_misses = data['roi']['cpu0_L2C']['LOAD']['miss'][0]
    l2_hit_rate = calculate_hit_rate(l2_hits, l2_misses)

    # Calculate total mispredictions and MPKI
    total_mispredictions = sum(cores_data['mispredict'].values())
    mpki = calculate_mpki(total_mispredictions, instructions)

    # Extract mispredictions per branch type
    mispredictions_per_type = cores_data['mispredict']

    return {
        'ipc': ipc,
        'l1d_hit_rate': l1d_hit_rate,
        'l2_hit_rate': l2_hit_rate,
        'mpki': mpki,
        **{f"mispredict_{k}": v for k, v in mispredictions_per_type.items()},  # Prefix each key with 'mispredict_'
        'total_mispredictions': total_mispredictions,
    }

def main(directory, output_csv):
    """Process all JSON files in the directory and write results to a CSV."""
    fieldnames = ['benchmark', 'input_graph', 'num_nodes', 'num_edges', 'prefetcher', 'branch_predictor', 'ipc', 'l1d_hit_rate', 'l2_hit_rate', 'mpki', 'total_mispredictions'] + [f"mispredict_{k}" for k in ['BRANCH_CONDITIONAL', 'BRANCH_DIRECT_CALL', 'BRANCH_DIRECT_JUMP', 'BRANCH_INDIRECT', 'BRANCH_INDIRECT_CALL', 'BRANCH_RETURN']]
    with open(output_csv, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for filename in os.listdir(directory):
            if filename.endswith('.json'):
                filepath = os.path.join(directory, filename)
                stats = process_json_file(filepath)

                # Extract configuration from the file name
                config_parts = filename.replace('.json', '').split('.')
                config = dict(zip(fieldnames[:6], config_parts))
                config.update(stats)
                
                writer.writerow(config)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Summarize IPC, cache hit rates, and branch mispredictions from JSON files into a CSV.")
    parser.add_argument("-i", "--input", help="The input directory to read from.", required=True)
    parser.add_argument("-o", "--output", help="The output file to write to.", required=False, default="output.csv")
    
    args = parser.parse_args()
    main(args.input, args.output)
