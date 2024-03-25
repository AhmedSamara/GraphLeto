#!/usr/bin/python3

import os
import subprocess
import json

# Configuration JSON template file path.
config_template_path = 'champsim_config.json'

# List of prefetchers. Fill in with actual names.
# prefetchers = ['ip_stride', 'next_line', 'next_line_instr', 'no', 'no_instr', 'spp_dev', 'va_ampm_lite']
prefetchers = ['ip_stride']

# branch_predictors = ['bimodal', 'gshare', 'hashed_perceptron', 'perceptron']
branch_predictors = ['bimodal']

# Directory containing trace files.
trace_dir = 'traces/'

# Ensure there is a directory to store the outputs
output_dir = 'simulation_outputs/'
if not os.path.exists(output_dir):
    os.makedirs(output_dir)

def modify_and_save_config(prefetcher, branch_predictor, output_file_name):
    # Load the template configuration JSON.
    with open(config_template_path, 'r') as file:
        config = json.load(file)
    
    # Modify the configuration with the current prefetcher and branch predictor.
    config['L2C']['prefetcher'] = prefetcher
    config['ooo_cpu'][0]['branch_predictor'] = branch_predictor
    
    # Save the modified configuration JSON.
    modified_config_path = f"{output_file_name}.json"
    with open(modified_config_path, 'w') as file:
        json.dump(config, file, indent=4)
    
    return modified_config_path

# Function to run the simulator for a single combination of trace, prefetcher, and branch predictor.
def run_simulation(trace,  prefetcher, branch_predictor):
    # Extracting trace file name without extension for use in naming output file.
    trace_name = os.path.splitext(os.path.basename(trace))[0]
    
    # Construct the output file name based on the simulation configuration.
    output_file_name = f"{output_dir}/{trace_name}.{prefetcher}.{branch_predictor}"
    
    # Modify the config JSON and save it.
    config_path = modify_and_save_config(prefetcher, branch_predictor, output_file_name)
    
    # Config command with output redirection
    config_command = f"./config.sh {config_path} >> {output_file_name}.log 2>&1"
    make_command = "make > {output_file_name}.log 2>&1"
    sim_command = f"./bin/champsim --warmup_instructions 200000000 --simulation_instructions 500000000 {trace} --json {output_file_name}.json >> {output_file_name}.log 2>&1"
    
    # Execute config command
    subprocess.run(config_command, shell=True)
    
    subprocess.run(make_command.format(output_file_name=output_file_name), shell=True)
    
    # Execute simulation command
    subprocess.run(sim_command, shell=True)

# Iterate over each trace file in the traces directory.
for trace in os.listdir(trace_dir):
    trace_path = os.path.join(trace_dir, trace)
    
    # Iterate over each combination of prefetcher and branch predictor.
    for prefetcher in prefetchers:
        for branch_predictor in branch_predictors:
            # Call the function to run the simulation.
            run_simulation(trace_path, prefetcher, branch_predictor)
