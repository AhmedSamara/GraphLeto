#ifndef BRANCH_ORACLE_H
#define BRANCH_ORACLE_H

#include <array>
#include <unordered_set>
#include <unordered_map>
#include <string>

#include "address.h"
#include "modules.h"
#include "msl/fwcounter.h"

// Oracle Branch Predictor
// Perfect prediction for specific "oracle" branch addresses
// Uses last known outcome as prediction (perfect in steady state)
// Falls back to simple bimodal predictor for non-oracle branches

class oracle : public champsim::modules::branch_predictor
{
  // Oracle branch addresses (PCs that get perfect prediction)
  std::unordered_set<uint64_t> oracle_addresses;
  
  // Cache of last outcomes for oracle branches (for "perfect" prediction)
  std::unordered_map<uint64_t, bool> oracle_history;
  
  // Base predictor: simple bimodal (2-bit counters) for non-oracle branches
  static constexpr std::size_t TABLE_SIZE = 16384;
  static constexpr std::size_t PRIME = 16381;
  static constexpr std::size_t BITS = 2;
  
  std::array<champsim::msl::fwcounter<BITS>, TABLE_SIZE> bimodal_table;
  
  // Statistics
  uint64_t oracle_predictions = 0;
  uint64_t base_predictions = 0;
  uint64_t oracle_correct = 0;
  uint64_t oracle_total = 0;
  
  // Helper functions
  [[nodiscard]] static constexpr auto hash(champsim::address ip) { 
    return ip.to<unsigned long>() % PRIME; 
  }
  
  bool is_oracle_branch(champsim::address ip) const;
  bool predict_bimodal(champsim::address ip);
  void update_bimodal(champsim::address ip, bool taken);
  void load_oracle_addresses(const std::string& filename);

public:
  explicit oracle(O3_CPU* cpu);
  ~oracle();
  
  // ChampSim interface
  bool predict_branch(champsim::address ip);
  void last_branch_result(champsim::address ip, champsim::address branch_target, 
                         bool taken, uint8_t branch_type);
};

#endif // BRANCH_ORACLE_H
