#include "oracle.h"
#include <iostream>
#include <fstream>
#include <cstdlib>

oracle::oracle(O3_CPU* cpu) : champsim::modules::branch_predictor(cpu) {
    // Load oracle addresses from environment variable if set
    const char* oracle_file = std::getenv("CHAMPSIM_ORACLE_FILE");
    if (oracle_file != nullptr) {
        load_oracle_addresses(oracle_file);
    }
}

oracle::~oracle() {
    // Print statistics
    if (oracle_addresses.size() > 0) {
        std::cout << "[Oracle BP] Total oracle addresses: " << oracle_addresses.size() << std::endl;
        std::cout << "[Oracle BP] Oracle predictions: " << oracle_predictions << std::endl;
        std::cout << "[Oracle BP] Base predictions: " << base_predictions << std::endl;
        if (oracle_total > 0) {
            double accuracy = 100.0 * oracle_correct / oracle_total;
            std::cout << "[Oracle BP] Oracle accuracy: " << accuracy << "% (" 
                      << oracle_correct << "/" << oracle_total << ")" << std::endl;
        }
    }
}

bool oracle::is_oracle_branch(champsim::address ip) const {
    return oracle_addresses.find(ip.to<uint64_t>()) != oracle_addresses.end();
}

bool oracle::predict_branch(champsim::address ip) {
    if (is_oracle_branch(ip)) {
        oracle_predictions++;
        
        // Oracle branch: Use last known outcome (perfect prediction in steady state)
        // First occurrence will use bimodal, but subsequent ones will be perfect
        auto it = oracle_history.find(ip.to<uint64_t>());
        if (it != oracle_history.end()) {
            // We've seen this oracle branch before - use last outcome
            return it->second;
        }
        // First time seeing this oracle branch - fall through to base predictor
    }
    
    // Non-oracle branch or first occurrence: use base predictor
    base_predictions++;
    return predict_bimodal(ip);
}

void oracle::last_branch_result(champsim::address ip, champsim::address branch_target, 
                                bool taken, uint8_t branch_type) {
    if (is_oracle_branch(ip)) {
        // Store the outcome for perfect future predictions
        uint64_t ip_val = ip.to<uint64_t>();
        
        // Track accuracy (after warmup)
        auto it = oracle_history.find(ip_val);
        if (it != oracle_history.end()) {
            oracle_total++;
            if (it->second == taken) {
                oracle_correct++;
            }
        }
        
        // Update oracle history with actual outcome
        oracle_history[ip_val] = taken;
        return;
    }
    
    // Update base predictor for non-oracle branches
    update_bimodal(ip, taken);
}

bool oracle::predict_bimodal(champsim::address ip) {
    auto value = bimodal_table[hash(ip)];
    return value.value() > (value.maximum / 2);
}

void oracle::update_bimodal(champsim::address ip, bool taken) {
    bimodal_table[hash(ip)] += taken ? 1 : -1;
}

void oracle::load_oracle_addresses(const std::string& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        std::cerr << "[Oracle BP] Warning: Could not open oracle address file: " 
                  << filename << std::endl;
        std::cerr << "[Oracle BP] Continuing with base predictor only" << std::endl;
        return;
    }
    
    std::string line;
    uint64_t address;
    size_t count = 0;
    
    while (std::getline(file, line)) {
        // Skip empty lines and comments
        if (line.empty() || line[0] == '#') {
            continue;
        }
        
        // Parse address (hex format: 0x... or decimal)
        if (line.substr(0, 2) == "0x" || line.substr(0, 2) == "0X") {
            address = std::stoull(line, nullptr, 16);
        } else {
            address = std::stoull(line, nullptr, 10);
        }
        
        oracle_addresses.insert(address);
        count++;
    }
    
    file.close();
    std::cout << "[Oracle BP] Loaded " << count << " oracle addresses from " 
              << filename << std::endl;
    
    std::cout << "[Oracle BP] Oracle predictions: " << oracle_predictions << std::endl;
    std::cout << "[Oracle BP] Base predictions: " << base_predictions << std::endl;
    std::cout << "[Oracle BP] Total oracle addresses: " << oracle_addresses.size() << std::endl;
}
