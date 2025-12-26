#!/usr/bin/env python3
"""
Extract branch addresses from ChampSim trace files.
This gives us the actual runtime addresses that the oracle predictor will see.
"""

import sys
import struct
import lzma
from collections import Counter

def read_trace(trace_file):
    """Read ChampSim trace and extract branch addresses."""
    
    branches = []
    
    try:
        # Open trace file (handle .xz compression)
        if trace_file.endswith('.xz'):
            f = lzma.open(trace_file, 'rb')
        else:
            f = open(trace_file, 'rb')
        
        print(f"Reading trace: {trace_file}", file=sys.stderr)
        
        # ChampSim trace format (per instruction):
        # - 1 byte: instruction_valid (0 or 1)
        # - 8 bytes: ip (instruction pointer)
        # - 1 byte: is_branch
        # - 1 byte: branch_taken
        # - 8 bytes: destination_registers
        # - 8 bytes: source_registers  
        # - 8 bytes: destination_memory
        # - 8 bytes: source_memory
        
        instruction_count = 0
        branch_count = 0
        
        while True:
            # Read one instruction
            data = f.read(35)  # Total size per instruction
            if len(data) < 35:
                break
                
            instruction_count += 1
            
            # Unpack the data
            valid = struct.unpack('B', data[0:1])[0]
            if valid == 0:
                continue
                
            ip = struct.unpack('Q', data[1:9])[0]
            is_branch = struct.unpack('B', data[9:10])[0]
            branch_taken = struct.unpack('B', data[10:11])[0]
            
            # Collect branch addresses
            if is_branch:
                branches.append(ip)
                branch_count += 1
                
            # Progress indicator
            if instruction_count % 1000000 == 0:
                print(f"  Processed {instruction_count/1000000:.1f}M instructions, {branch_count} branches", file=sys.stderr)
        
        f.close()
        
        print(f"Total: {instruction_count} instructions, {branch_count} branches", file=sys.stderr)
        return branches
        
    except Exception as e:
        print(f"Error reading trace: {e}", file=sys.stderr)
        return []

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 extract_branch_addresses_from_trace.py <trace_file> [top_n]")
        print("")
        print("Extracts branch addresses from ChampSim trace and outputs the most")
        print("frequently executed branches (candidates for oracle prediction).")
        print("")
        print("Arguments:")
        print("  trace_file  : ChampSim trace file (.champsimtrace or .champsimtrace.xz)")
        print("  top_n       : Number of top branches to output (default: 100)")
        sys.exit(1)
    
    trace_file = sys.argv[1]
    top_n = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    
    # Extract branches
    branches = read_trace(trace_file)
    
    if not branches:
        print("No branches found in trace!", file=sys.stderr)
        sys.exit(1)
    
    # Count frequency
    branch_counts = Counter(branches)
    
    print(f"\nFound {len(branch_counts)} unique branch addresses", file=sys.stderr)
    print(f"Outputting top {top_n} most frequent branches:", file=sys.stderr)
    print("", file=sys.stderr)
    
    # Output top N branches
    for ip, count in branch_counts.most_common(top_n):
        print(f"0x{ip:x}")
    
    # Statistics
    total_branches = len(branches)
    top_n_coverage = sum(count for _, count in branch_counts.most_common(top_n))
    coverage_pct = 100.0 * top_n_coverage / total_branches
    
    print("", file=sys.stderr)
    print(f"Top {top_n} branches cover {top_n_coverage}/{total_branches} ({coverage_pct:.1f}%) of all branch executions", file=sys.stderr)

if __name__ == "__main__":
    main()
