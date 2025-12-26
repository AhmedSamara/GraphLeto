#!/usr/bin/env python3
"""
Extract branch-data correlations from ChampSim traces.

This script analyzes traces to find which data addresses are accessed
immediately before branch instructions. These correlations are used by
the CacheBP predictor to associate branches with cache line addresses.

Output format: branch_pc,data_addr (one per line, hex with 0x prefix)
"""

import sys
import struct
import lzma
from collections import defaultdict, Counter

def read_trace_with_correlations(trace_file, max_instructions=None):
    """
    Read ChampSim trace and extract branch-data correlations.
    
    Strategy: Track the most recent data address accessed before each branch.
    This simulates the hardware tracking of load addresses that feed into branches.
    """
    
    correlations = defaultdict(list)  # branch_pc -> [data_addresses]
    last_data_addr = 0  # Most recent data address seen
    
    try:
        # Open trace file (handle .xz compression)
        if trace_file.endswith('.xz'):
            f = lzma.open(trace_file, 'rb')
        else:
            f = open(trace_file, 'rb')
        
        print(f"Reading trace: {trace_file}", file=sys.stderr)
        
        instruction_count = 0
        branch_count = 0
        correlation_count = 0
        
        while True:
            if max_instructions and instruction_count >= max_instructions:
                break
                
            # Read one instruction (35 bytes per instruction in ChampSim format)
            data = f.read(35)
            if len(data) < 35:
                break
                
            instruction_count += 1
            
            # Unpack the instruction data
            valid = struct.unpack('B', data[0:1])[0]
            if valid == 0:
                continue
                
            ip = struct.unpack('Q', data[1:9])[0]
            is_branch = struct.unpack('B', data[9:10])[0]
            branch_taken = struct.unpack('B', data[10:11])[0]
            dest_registers = struct.unpack('Q', data[11:19])[0]
            source_registers = struct.unpack('Q', data[19:27])[0]
            dest_memory = struct.unpack('Q', data[27:35])[0]
            source_memory = struct.unpack('Q', data[27:35])[0]  # Note: overlaps with dest
            
            # Track memory accesses (loads/stores update last_data_addr)
            if source_memory != 0:
                last_data_addr = source_memory
            elif dest_memory != 0:
                last_data_addr = dest_memory
            
            # When we see a branch, record the correlation with last data address
            if is_branch and last_data_addr != 0:
                correlations[ip].append(last_data_addr)
                branch_count += 1
                correlation_count += 1
            
            # Progress indicator
            if instruction_count % 1000000 == 0:
                print(f"  Processed {instruction_count/1000000:.1f}M instructions, "
                      f"{branch_count} branches with correlations", file=sys.stderr)
        
        f.close()
        
        print(f"\nTotal: {instruction_count} instructions", file=sys.stderr)
        print(f"Branches with data correlations: {len(correlations)}", file=sys.stderr)
        print(f"Total correlations recorded: {correlation_count}", file=sys.stderr)
        
        return correlations
        
    except Exception as e:
        print(f"Error reading trace: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return {}

def find_dominant_correlations(correlations, min_frequency=10):
    """
    For each branch, find the most frequently associated data address.
    Only keep correlations that appear frequently (stable correlations).
    """
    
    dominant = {}
    
    for branch_pc, data_addrs in correlations.items():
        if len(data_addrs) < min_frequency:
            continue  # Not enough samples
        
        # Find most common data address for this branch
        counter = Counter(data_addrs)
        most_common_addr, count = counter.most_common(1)[0]
        
        # Only keep if this address appears in at least 50% of instances
        frequency = count / len(data_addrs)
        if frequency >= 0.5:
            dominant[branch_pc] = most_common_addr
    
    return dominant

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 extract_branch_data_correlations.py <trace_file> [max_instructions] [min_frequency]")
        print("")
        print("Extracts branch-data correlations from ChampSim trace for CacheBP predictor.")
        print("")
        print("Arguments:")
        print("  trace_file        : ChampSim trace file (.champsimtrace or .champsimtrace.xz)")
        print("  max_instructions  : Maximum instructions to process (default: all)")
        print("  min_frequency     : Minimum occurrences for stable correlation (default: 10)")
        print("")
        print("Output: CSV format with 'branch_pc,data_addr' (hex with 0x prefix)")
        sys.exit(1)
    
    trace_file = sys.argv[1]
    max_instructions = int(sys.argv[2]) if len(sys.argv) > 2 else None
    min_frequency = int(sys.argv[3]) if len(sys.argv) > 3 else 10
    
    # Extract correlations
    correlations = read_trace_with_correlations(trace_file, max_instructions)
    
    if not correlations:
        print("No correlations found in trace!", file=sys.stderr)
        sys.exit(1)
    
    # Find dominant (stable) correlations
    dominant = find_dominant_correlations(correlations, min_frequency)
    
    print(f"\nStable correlations (>50% frequency, >{min_frequency} samples): {len(dominant)}", 
          file=sys.stderr)
    
    # Output correlations in CSV format
    print("# branch_pc,data_addr")
    for branch_pc in sorted(dominant.keys()):
        data_addr = dominant[branch_pc]
        print(f"0x{branch_pc:x},0x{data_addr:x}")
    
    # Statistics
    if dominant:
        total_instances = sum(len(addrs) for addrs in correlations.values())
        covered_instances = sum(len(correlations[pc]) for pc in dominant.keys())
        coverage = 100.0 * covered_instances / total_instances if total_instances > 0 else 0
        
        print(f"\nCoverage: {covered_instances}/{total_instances} ({coverage:.1f}%) branch instances", 
              file=sys.stderr)

if __name__ == "__main__":
    main()
