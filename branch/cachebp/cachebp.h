/*
 * CacheBP: Cache-Based Branch Predictor for Graph Workloads
 * 
 * Based on Graph-Guru architecture (ISCA 2020)
 * Uses cache line addresses to predict branch outcomes
 * 
 * Key components:
 * - BDT (Branch-Data Correlation Table): Maps branch PCs to data addresses
 * - Outcome Cache: Stores 2-bit counters indexed by cache line address
 * - Fallback bimodal predictor for non-correlated branches
 */

#ifndef BRANCH_CACHEBP_H
#define BRANCH_CACHEBP_H

#include <vector>
#include <unordered_map>
#include <array>
#include <cstdint>
#include "address.h"
#include "modules.h"
#include "msl/fwcounter.h"

class cachebp : public champsim::modules::branch_predictor
{
private:
    // Branch-Data Correlation Table (BDT) entry
    struct BDTEntry {
        uint64_t branch_pc;
        uint64_t data_addr;
        bool valid;
        uint64_t lru_counter;
        
        BDTEntry() : branch_pc(0), data_addr(0), valid(false), lru_counter(0) {}
    };
    
    // BDT: Set-associative structure
    std::vector<std::vector<BDTEntry>> bdt;
    uint64_t bdt_sets;
    uint64_t bdt_ways;
    uint64_t bdt_index_mask;
    uint64_t global_lru_counter;
    
    // Outcome Cache: 2-bit saturating counters indexed by cache line address
    static constexpr std::size_t OC_SIZE = 1024;
    std::array<champsim::msl::fwcounter<2>, OC_SIZE> outcome_cache;
    uint64_t oc_index_mask;
    
    // Fallback bimodal predictor (for branches without data correlation)
    static constexpr std::size_t BIMODAL_SIZE = 4096;
    std::array<champsim::msl::fwcounter<2>, BIMODAL_SIZE> bimodal_table;
    uint64_t bimodal_index_mask;
    
    // Pre-loaded branch-data correlations (static profiling approach)
    std::unordered_map<uint64_t, uint64_t> static_correlations;
    
    // Statistics
    uint64_t total_predictions;
    uint64_t bdt_hits;
    uint64_t bdt_misses;
    uint64_t oc_predictions;
    uint64_t oc_correct;
    uint64_t bimodal_predictions;
    uint64_t bimodal_correct;
    uint64_t static_correlation_hits;
    
    // Helper functions
    uint64_t get_bdt_index(uint64_t pc) const;
    uint64_t get_bdt_tag(uint64_t pc) const;
    uint64_t get_cache_line_addr(uint64_t data_addr) const;
    uint64_t get_oc_index(uint64_t cache_line_addr) const;
    uint64_t get_bimodal_index(uint64_t pc) const;
    
    bool lookup_bdt(uint64_t pc, uint64_t& data_addr);
    void update_bdt(uint64_t pc, uint64_t data_addr);
    int find_lru_way(uint64_t set_index);
    
    bool predict_from_oc(uint64_t cache_line_addr);
    void update_oc(uint64_t cache_line_addr, bool taken);
    
    bool predict_bimodal(champsim::address pc);
    void update_bimodal(champsim::address pc, bool taken);
    
    void load_static_correlations(const std::string& filename);

public:
    explicit cachebp(O3_CPU* cpu);
    ~cachebp();
    
    bool predict_branch(champsim::address ip);
    void last_branch_result(champsim::address ip, champsim::address branch_target, 
                           bool taken, uint8_t branch_type);
};

#endif // BRANCH_CACHEBP_H
