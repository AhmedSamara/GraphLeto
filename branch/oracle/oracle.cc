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
    uint64_t ip_val = ip.to<uint64_t>();
    
    // Debug: print first few IPs
    static int debug_count = 0;
    if (debug_count++ < 5 && oracle_addresses.size() > 0) {
        uint64_t offset_20bit = ip_val & 0xFFFFF;  // Lower 20 bits (~1MB)
        std::cout << "[Oracle BP Debug] IP: 0x" << std::hex << ip_val 
                  << " offset_20bit: 0x" << offset_20bit << std::dec << std::endl;
    }
    
    // Try direct match first (for non-PIE binaries)
    if (oracle_addresses.find(ip_val) != oracle_addresses.end()) {
        return true;
    }
    
    // For PIE binaries with ASLR, match on lower 20 bits
    // This assumes oracle addresses and runtime addresses share lower bits
    uint64_t offset = ip_val & 0xFFFFF;  // Lower 20 bits (~1MB range)
    return oracle_addresses.find(offset) != oracle_addresses.end();
}

bool oracle::predict_branch(champsim::address ip) {
    // Debug: dump all unique branch IPs to help create oracle address list
    static std::unordered_set<uint64_t> seen_branches;
    static bool dumping_enabled = (std::getenv("CHAMPSIM_DUMP_BRANCHES") != nullptr);
    static std::string dump_file = dumping_enabled ? std::getenv("CHAMPSIM_DUMP_BRANCHES") : "";
    
    if (dumping_enabled) {
        uint64_t ip_val = ip.to<uint64_t>();
        if (seen_branches.find(ip_val) == seen_branches.end()) {
            seen_branches.insert(ip_val);
            // Append to file
            std::ofstream out(dump_file, std::ios::app);
            out << "0x" << std::hex << ip_val << std::dec << "\n";
            out.close();
        }
    }
    
    static bool printed_sample = false;
    if (!printed_sample && oracle_addresses.size() > 0) {
        std::cout << "[Oracle BP] Sample branch IP seen: 0x" << std::hex << ip.to<uint64_t>() << std::dec << std::endl;
        printed_sample = true;
    }
    
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
