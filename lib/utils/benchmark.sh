#!/bin/bash
# benchmark.sh - Performance benchmarking utilities
# Provides CPU, disk I/O, and network speed tests for baseline measurements

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_BENCHMARK_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _BENCHMARK_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/logger.sh"

# Benchmark configuration
readonly BENCHMARK_DIR="${BENCHMARK_DIR:-/var/vps-provision/benchmark}"
readonly BENCHMARK_RESULTS_FILE="${BENCHMARK_RESULTS_FILE:-${BENCHMARK_DIR}/results.json}"

# Create benchmark directory
benchmark_init() {
  if [[ ! -d "$BENCHMARK_DIR" ]]; then
    mkdir -p "$BENCHMARK_DIR" 2>/dev/null || true
  fi
  log_debug "Benchmark directory initialized: $BENCHMARK_DIR"
}

# CPU benchmark - measures integer and floating-point performance
# Returns: operations per second
benchmark_cpu() {
  log_info "Running CPU benchmark..."
  local start end duration ops
  
  start=$(date +%s%N)
  
  # Integer benchmark: count to 1 million
  local count=0
  while ((count < 1000000)); do
    ((count++))
  done
  
  end=$(date +%s%N)
  duration=$(( (end - start) / 1000000 ))  # Convert to milliseconds
  ops=$(( 1000000 * 1000 / duration ))     # Operations per second
  
  log_info "CPU benchmark: ${ops} ops/sec (${duration}ms)"
  echo "$ops"
}

# Disk I/O benchmark - measures read/write speeds
# Returns: read_speed write_speed (in MB/s)
benchmark_disk_io() {
  log_info "Running disk I/O benchmark..."
  local test_file="${BENCHMARK_DIR}/disk_test.tmp"
  local size_mb=100
  local read_speed write_speed
  
  # Write test
  log_debug "Testing write speed..."
  local write_start write_end write_duration
  write_start=$(date +%s%N)
  
  dd if=/dev/zero of="$test_file" bs=1M count=$size_mb conv=fsync 2>/dev/null || {
    log_error "Disk write benchmark failed"
    return 1
  }
  
  write_end=$(date +%s%N)
  write_duration=$(( (write_end - write_start) / 1000000 ))  # Milliseconds
  write_speed=$(( size_mb * 1000 / write_duration ))         # MB/s
  
  # Read test
  log_debug "Testing read speed..."
  sync  # Clear cache
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  
  local read_start read_end read_duration
  read_start=$(date +%s%N)
  
  dd if="$test_file" of=/dev/null bs=1M 2>/dev/null || {
    log_error "Disk read benchmark failed"
    rm -f "$test_file"
    return 1
  }
  
  read_end=$(date +%s%N)
  read_duration=$(( (read_end - read_start) / 1000000 ))
  read_speed=$(( size_mb * 1000 / read_duration ))
  
  # Cleanup
  rm -f "$test_file"
  
  log_info "Disk I/O benchmark: Read=${read_speed}MB/s Write=${write_speed}MB/s"
  echo "$read_speed $write_speed"
}

# Network speed benchmark - measures download speed
# Returns: download_speed (in Mbps)
benchmark_network() {
  log_info "Running network speed benchmark..."
  
  # Test with a small Debian mirror file (10MB)
  local test_url="http://deb.debian.org/debian/README"
  local test_file="${BENCHMARK_DIR}/network_test.tmp"
  local start end duration speed_mbps
  
  start=$(date +%s%N)
  
  if wget -q -O "$test_file" "$test_url" --timeout=30 2>/dev/null; then
    end=$(date +%s%N)
    duration=$(( (end - start) / 1000000 ))  # Milliseconds
    
    local file_size_kb
    file_size_kb=$(stat -f "%z" "$test_file" 2>/dev/null || stat -c "%s" "$test_file" 2>/dev/null || echo "0")
    file_size_kb=$(( file_size_kb / 1024 ))  # Convert to KB
    
    # Calculate speed: (KB * 8) / (ms / 1000) = Kbps, then / 1024 = Mbps
    speed_mbps=$(( (file_size_kb * 8 * 1000) / (duration * 1024) ))
    
    rm -f "$test_file"
    log_info "Network benchmark: ${speed_mbps}Mbps"
    echo "$speed_mbps"
  else
    log_warning "Network benchmark failed - using fallback test"
    # Fallback: measure time to connect to debian.org
    local latency
    latency=$(ping -c 4 deb.debian.org 2>/dev/null | grep 'avg' | awk -F'/' '{print $5}' | cut -d'.' -f1)
    
    if [[ -n "$latency" ]]; then
      log_info "Network latency: ${latency}ms"
      # Estimate speed based on latency (rough approximation)
      # <50ms = excellent (100Mbps+), 50-100ms = good (50Mbps), >100ms = poor (10Mbps)
      if ((latency < 50)); then
        echo "100"
      elif ((latency < 100)); then
        echo "50"
      else
        echo "10"
      fi
    else
      log_error "Network benchmark failed completely"
      echo "0"
    fi
  fi
}

# Run all benchmarks and save results
benchmark_run_all() {
  log_info "Running comprehensive system benchmarks..."
  benchmark_init
  
  local cpu_ops disk_read disk_write network_mbps
  
  # Run benchmarks
  cpu_ops=$(benchmark_cpu)
  read -r disk_read disk_write <<< "$(benchmark_disk_io)"
  network_mbps=$(benchmark_network)
  
  # Generate timestamp
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Create JSON report
  cat > "$BENCHMARK_RESULTS_FILE" <<EOF
{
  "timestamp": "$timestamp",
  "cpu": {
    "operations_per_second": $cpu_ops
  },
  "disk_io": {
    "read_speed_mbps": $disk_read,
    "write_speed_mbps": $disk_write
  },
  "network": {
    "download_speed_mbps": $network_mbps
  },
  "system": {
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "cpu_cores": $(nproc),
    "total_ram_mb": $(free -m | awk '/^Mem:/ {print $2}'),
    "total_disk_gb": $(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
  }
}
EOF
  
  log_info "Benchmark results saved to: $BENCHMARK_RESULTS_FILE"
  cat "$BENCHMARK_RESULTS_FILE"
}

# Compare current run against baseline
# Args: $1 - current results file, $2 - baseline results file
benchmark_compare() {
  local current_file="${1:-$BENCHMARK_RESULTS_FILE}"
  local baseline_file="${2:-${BENCHMARK_DIR}/baseline.json}"
  
  if [[ ! -f "$current_file" ]]; then
    log_error "Current results file not found: $current_file"
    return 1
  fi
  
  if [[ ! -f "$baseline_file" ]]; then
    log_warning "Baseline file not found: $baseline_file"
    log_info "Creating baseline from current results..."
    cp "$current_file" "$baseline_file"
    return 0
  fi
  
  log_info "Comparing performance against baseline..."
  
  # Extract values (requires jq or manual parsing)
  if command -v jq &>/dev/null; then
    local current_cpu baseline_cpu variance_cpu
    current_cpu=$(jq -r '.cpu.operations_per_second' "$current_file")
    baseline_cpu=$(jq -r '.cpu.operations_per_second' "$baseline_file")
    variance_cpu=$(echo "scale=2; (($current_cpu - $baseline_cpu) / $baseline_cpu) * 100" | bc)
    
    log_info "CPU Performance: ${variance_cpu}% variance"
    
    if (( $(echo "$variance_cpu < -20" | bc -l) )); then
      log_warning "CPU performance degraded by more than 20%"
    fi
  else
    log_warning "jq not available - skipping detailed comparison"
  fi
}

# Main execution when run as script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  benchmark_init
  benchmark_run_all
  benchmark_compare
fi
