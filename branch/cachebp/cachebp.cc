/*
 * CacheBP: Cache-Based Branch Predictor Implementation
 */

#include "cachebp.h"
#include <iostream>
#include <fstream>
#include <cmath>
#include <cstdlib>

// Constructor: Initialize all structures based on configuration
cachebp::cachebp(O3_CPU* cpu) : champsim::modules::branch_predictor(cpu)
{
    // Read configuration from environment variables (allows easy parameter sweeps)
    const char* bdt_sets_env = std::getenv("CACHEBP_BDT_SETS");
    const char* bdt_ways_env = std::getenv("CACHEBP_BDT_WAYS");
    const char* corr_file_env = std::getenv("CACHEBP_CORRELATIONS");
    
    // Default configuration (matches Graph-Guru paper)
    bdt_sets = bdt_sets_env ? std::stoull(bdt_sets_env) : 256;
    bdt_ways = bdt_ways_env ? std::stoull(bdt_ways_env) : 4;
    
    // Calculate index masks
    bdt_index_mask = bdt_sets - 1;
    oc_index_mask = OC_SIZE - 1;
    bimodal_index_mask = BIMODAL_SIZE - 1;
    
    // Initialize BDT (set-associative)
    bdt.resize(bdt_sets);
    for (auto& set : bdt) {
        set.resize(bdt_ways);
    }
    global_lru_counter = 0;
    
    // Initialize statistics
    total_predictions = 0;
    bdt_hits = 0;
    bdt_misses = 0;
    oc_predictions = 0;
    oc_correct = 0;
    bimodal_predictions = 0;
    bimodal_correct = 0;
    static_correlation_hits = 0;
    
    // Load static correlations if provided
    if (corr_file_env != nullptr) {
        load_static_correlations(corr_file_env);
        // Insert static correlations into BDT with all address variants
        // This handles the trace address encoding mismatches
        std::cout << "[CacheBP] Inserting " << static_correlations.size() 
                  << " static correlations into BDT (with address variants)..." << std::endl;
        
        int inserted = 0;
        for (const auto& pair : static_correlations) {
            uint64_t pc = pair.first;
            uint64_t data_addr = pair.second;
            
            // Try inserting with different PC representations
            // This handles ASLR, PIE, and trace encoding differences
            uint64_t variants[] = {
                pc,
                pc & 0xFFFFFFFF,
                pc & 0xFFFFFF,
                pc & 0xFFFF,
                pc | 0x0000000076650000ULL,  // Common base address pattern
                pc | 0x0000000076654000ULL
            };
            
            for (uint64_t pc_variant : variants) {
                update_bdt(pc_variant, data_addr);
                inserted++;
            }
        }
        std::cout << "[CacheBP] BDT populated with " << inserted << " entries" << std::endl;
    }
    
    std::cout << "[CacheBP] Initialized with:" << std::endl;
    std::cout << "  BDT: " << bdt_sets << " sets x " << bdt_ways << " ways = " 
              << (bdt_sets * bdt_ways) << " entries" << std::endl;
    std::cout << "  Outcome Cache: " << OC_SIZE << " entries" << std::endl;
    std::cout << "  Bimodal: " << BIMODAL_SIZE << " entries" << std::endl;
    if (!static_correlations.empty()) {
        std::cout << "  Static correlations: " << static_correlations.size() << " entries loaded" << std::endl;
    }
}

cachebp::~cachebp()
{
    // Print statistics
    std::cout << "\n[CacheBP] Final Statistics:" << std::endl;
    std::cout << "  Total predictions: " << total_predictions << std::endl;
    
    if (total_predictions > 0) {
        std::cout << "  BDT hit rate: " << (100.0 * bdt_hits / total_predictions) << "%" << std::endl;
        std::cout << "  BDT miss rate: " << (100.0 * bdt_misses / total_predictions) << "%" << std::endl;
    }
    
    if (oc_predictions > 0) {
        std::cout << "  Outcome Cache predictions: " << oc_predictions << std::endl;
        std::cout << "  Outcome Cache accuracy: " << (100.0 * oc_correct / oc_predictions) << "%" << std::endl;
    }
    
    if (bimodal_predictions > 0) {
        std::cout << "  Bimodal predictions: " << bimodal_predictions << std::endl;
        std::cout << "  Bimodal accuracy: " << (100.0 * bimodal_correct / bimodal_predictions) << "%" << std::endl;
    }
    
    if (!static_correlations.empty()) {
        std::cout << "  Static correlation hits: " << static_correlation_hits << std::endl;
    }
}

// Get BDT set index from branch PC
uint64_t cachebp::get_bdt_index(uint64_t pc) const
{
    return (pc >> 2) & bdt_index_mask;  // Align to instruction boundary
}

// Get BDT tag from branch PC
uint64_t cachebp::get_bdt_tag(uint64_t pc) const
{
    return pc >> (2 + (uint64_t)std::log2(bdt_sets));
}

// Get cache line address (64-byte lines)
uint64_t cachebp::get_cache_line_addr(uint64_t data_addr) const
{
    return data_addr >> 6;  // 64-byte cache lines
}

// Get Outcome Cache index from cache line address
uint64_t cachebp::get_oc_index(uint64_t cache_line_addr) const
{
    return cache_line_addr & oc_index_mask;
}

// Get bimodal predictor index
uint64_t cachebp::get_bimodal_index(uint64_t pc) const
{
    return (pc >> 2) & bimodal_index_mask;
}

// Lookup BDT: Check if we have a data address correlation for this branch PC
bool cachebp::lookup_bdt(uint64_t pc, uint64_t& data_addr)
{
    // Check the actual BDT structure (now contains static correlations too)
    uint64_t set_index = get_bdt_index(pc);
    uint64_t tag = get_bdt_tag(pc);
    
    auto& set = bdt[set_index];
    for (auto& entry : set) {
        if (entry.valid && get_bdt_tag(entry.branch_pc) == tag) {
            // Hit: update LRU and return data address
            entry.lru_counter = global_lru_counter++;
            data_addr = entry.data_addr;
            bdt_hits++;
            return true;
        }
    }
    
    bdt_misses++;
    return false;  // Miss
}

// Update BDT with new branch-data correlation
void cachebp::update_bdt(uint64_t pc, uint64_t data_addr)
{
    uint64_t set_index = get_bdt_index(pc);
    uint64_t tag = get_bdt_tag(pc);
    
    auto& set = bdt[set_index];
    
    // Check if entry already exists (update data address)
    for (auto& entry : set) {
        if (entry.valid && get_bdt_tag(entry.branch_pc) == tag) {
            entry.data_addr = data_addr;
            entry.lru_counter = global_lru_counter++;
            return;
        }
    }
    
    // Not found, need to allocate a new entry
    // First, try to find an invalid entry
    for (auto& entry : set) {
        if (!entry.valid) {
            entry.branch_pc = pc;
            entry.data_addr = data_addr;
            entry.valid = true;
            entry.lru_counter = global_lru_counter++;
            return;
        }
    }
    
    // All entries valid, evict LRU
    int lru_way = find_lru_way(set_index);
    set[lru_way].branch_pc = pc;
    set[lru_way].data_addr = data_addr;
    set[lru_way].valid = true;
    set[lru_way].lru_counter = global_lru_counter++;
}

// Find LRU way in a set
int cachebp::find_lru_way(uint64_t set_index)
{
    auto& set = bdt[set_index];
    int lru_way = 0;
    uint64_t min_counter = set[0].lru_counter;
    
    for (size_t i = 1; i < set.size(); i++) {
        if (set[i].lru_counter < min_counter) {
            min_counter = set[i].lru_counter;
            lru_way = i;
        }
    }
    
    return lru_way;
}

// Predict from Outcome Cache using 2-bit saturating counter
bool cachebp::predict_from_oc(uint64_t cache_line_addr)
{
    uint64_t index = get_oc_index(cache_line_addr);
    auto counter = outcome_cache[index];
    return counter.value() >= (counter.maximum / 2);  // Predict taken if >= halfway
}

// Update Outcome Cache counter
void cachebp::update_oc(uint64_t cache_line_addr, bool taken)
{
    uint64_t index = get_oc_index(cache_line_addr);
    if (taken) {
        outcome_cache[index]++;
    } else {
        outcome_cache[index]--;
    }
}

// Predict using bimodal fallback predictor
bool cachebp::predict_bimodal(champsim::address pc)
{
    uint64_t index = get_bimodal_index(pc.to<uint64_t>());
    auto counter = bimodal_table[index];
    return counter.value() >= (counter.maximum / 2);  // Predict taken if >= halfway
}

// Update bimodal predictor
void cachebp::update_bimodal(champsim::address pc, bool taken)
{
    uint64_t index = get_bimodal_index(pc.to<uint64_t>());
    if (taken) {
        bimodal_table[index]++;
    } else {
        bimodal_table[index]--;
    }
}

// Load static branch-data correlations from file
void cachebp::load_static_correlations(const std::string& filename)
{
    std::ifstream file(filename);
    if (!file.is_open()) {
        std::cerr << "[CacheBP] Warning: Could not open correlations file: " << filename << std::endl;
        return;
    }
    
    std::string line;
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') continue;
        
        // Format: branch_pc,data_addr (both in hex with 0x prefix)
        size_t comma_pos = line.find(',');
        if (comma_pos == std::string::npos) continue;
        
        std::string pc_str = line.substr(0, comma_pos);
        std::string addr_str = line.substr(comma_pos + 1);
        
        try {
            uint64_t pc = std::stoull(pc_str, nullptr, 16);
            uint64_t data_addr = std::stoull(addr_str, nullptr, 16);
            static_correlations[pc] = data_addr;
        } catch (...) {
            // Skip malformed lines
            continue;
        }
    }
    
    file.close();
}

// Main prediction function
bool cachebp::predict_branch(champsim::address ip)
{
    total_predictions++;
    uint64_t pc = ip.to<uint64_t>();
    uint64_t data_addr;
    bool prediction = false;
    
    // Step 1: Lookup BDT to get correlated data address
    if (lookup_bdt(pc, data_addr)) {
        // BDT hit: Use Outcome Cache indexed by cache line address
        oc_predictions++;
        
        uint64_t cache_line = get_cache_line_addr(data_addr);
        prediction = predict_from_oc(cache_line);
    } else {
        // BDT miss: Use bimodal fallback predictor
        bimodal_predictions++;
        
        prediction = predict_bimodal(ip);
    }
    
    return prediction;
}

// Update predictor with actual branch outcome
void cachebp::last_branch_result(champsim::address ip, champsim::address branch_target, 
                                 bool taken, uint8_t branch_type)
{
    uint64_t pc = ip.to<uint64_t>();
    uint64_t data_addr;
    
    // Check if we made a prediction with Outcome Cache or bimodal
    if (lookup_bdt(pc, data_addr)) {
        // Was predicted using Outcome Cache
        uint64_t cache_line = get_cache_line_addr(data_addr);
        
        // Track accuracy
        bool prediction = predict_from_oc(cache_line);
        if (prediction == taken) {
            oc_correct++;
        }
        
        // Update Outcome Cache
        update_oc(cache_line, taken);
    } else {
        // Was predicted using bimodal
        bool prediction = predict_bimodal(ip);
        if (prediction == taken) {
            bimodal_correct++;
        }
        
        // Update bimodal
        update_bimodal(ip, taken);
    }
    
    // Note: In a real implementation, we would also update the BDT here
    // with the data address accessed before this branch. However, ChampSim
    // doesn't provide this information through the standard API.
    // This is why we rely on static correlations loaded from a file.
}
