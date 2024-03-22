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

PIN_ROOT="/home/asamara/code/GraphLeto/tracer/pin/pin-3.22-98547-g7a303a835-gcc-linux"
input_graph_location="/home/asamara/code/SNIPER-graphs/real_graphs"
benchmarks=["bc",  "bfs", "cc_sv", "pr_spmv", "pr", "sssp", "pr"]
inputs=["g13.1.1.sg", "g19.1.1.sg"]

# if PIN_ROOT not set, error and exit.


for benchmark in benchmarks:
    for input_graph in inputs:
        command_template = f"{PIN_ROOT}/pin -t obj-intel64/champsim_tracer.so -- ./gapbs/{benchmark} -f {input_graph_location}/{input_graph} -n 1"
        print(command_template)
        bcmd(command_template)
