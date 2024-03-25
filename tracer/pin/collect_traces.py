#!/usr/bin/python

import sys
import os
import subprocess

# executes the sent command as argument and sends back result.
def bcmd(cmd, printout=True):
    print(cmd)
    out = os.popen(cmd).read()
    print(out)
    return out

PIN_ROOT="/home/asamara/GraphLeto/tracer/pin/pin-3.22-98547-g7a303a835-gcc-linux"
input_graph_location="/home/asamara/SNIPER-graphs/real_graphs/"
benchmarks=["bc",  "bfs", "cc_sv", "pr_spmv", "pr", "sssp", "pr"]
# inputs=["g13.1.1.sg", "g19.1.1.sg"]
inputs=["LiveJournal.4847571.68993773.sg", "orkut.3072441.117185083.sg",
        "roadsCA.1965206.2766607.sg"]

# if PIN_ROOT not set, error and exit.


for benchmark in benchmarks:
    for input_graph in inputs:
        # remove the file extension from input_graph before adding to output file name.
        output_file=f"{benchmark}.{input_graph}.trace"
        command_template = f"{PIN_ROOT}/pin -t obj-intel64/champsim_tracer.so -o {output_file} -- ./gapbs/{benchmark} -f {input_graph_location}/{input_graph} -n 1"
        print(command_template)
        bcmd(command_template)
