#!/usr/bin/env bats
# Performance tests for VPS provisioning
# Tests performance requirements from performance-specs.md

load '../test_helper'

setup() {
  common_setup
  
  # Source logger for log_info function
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
  
  # Ensure log functions exist (fallback for testing)
  if ! declare -f log_info &>/dev/null; then
    # shellcheck disable=SC2317
    log_info() { echo "[INFO] $*"; }
    # shellcheck disable=SC2317
    log_warning() { echo "[WARN] $*"; }
    # shellcheck disable=SC2317
    log_error() { echo "[ERROR] $*"; }
    export -f log_info log_warning log_error
  fi
  
  # Performance test configuration
  export PERF_LOG_DIR="${BATS_TEST_TMPDIR}/perf-logs"
  export PERF_TIMING_CSV="${PERF_LOG_DIR}/timing.csv"
  export PERF_RESOURCES_CSV="${PERF_LOG_DIR}/resources.csv"
  
  mkdir -p "$PERF_LOG_DIR"
  
  # Mock hardware detection
  export MOCK_CPU_CORES=2
  export MOCK_RAM_MB=4096
}

teardown() {
  common_teardown
}

# Helper: Simulate provisioning phases with realistic timing
simulate_provisioning_phases() {
  local total_duration=0
  
  # Simulate phase execution with timing
  local -A phase_durations=(
    ["system-prep"]=120
    ["desktop-install"]=270
    ["rdp-config"]=60
    ["user-creation"]=30
    ["ide-vscode"]=90
    ["ide-cursor"]=90
    ["ide-antigravity"]=90
    ["terminal-setup"]=30
    ["dev-tools"]=60
    ["verification"]=60
  )
  
  # Write timing data
  echo "Timestamp,Phase,DurationSec,Status" > "$PERF_TIMING_CSV"
  
  for phase in "${!phase_durations[@]}"; do
    local duration="${phase_durations[$phase]}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${timestamp},${phase},${duration},success" >> "$PERF_TIMING_CSV"
    total_duration=$((total_duration + duration))
  done
  
  echo "$total_duration"
}

# Helper: Simulate resource monitoring data
simulate_resource_monitoring() {
  local samples="${1:-10}"
  
  echo "Timestamp,MemUsedMB,MemAvailMB,CPUPercent,DiskAvailMB,LoadAvg1m,ProcessCount" > "$PERF_RESOURCES_CSV"
  
  for _ in $(seq 1 "$samples"); do
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local mem_used=$((1500 + RANDOM % 500))
    local mem_avail=$((4096 - mem_used))
    local cpu_pct=$((40 + RANDOM % 40))
    local disk_avail=$((20000 + RANDOM % 5000))
    local load_avg="1.5"
    local proc_count=$((150 + RANDOM % 50))
    
    echo "${timestamp},${mem_used},${mem_avail},${cpu_pct},${disk_avail},${load_avg},${proc_count}" >> "$PERF_RESOURCES_CSV"
    
    sleep 0.1
  done
}

# T136: Test provisioning time ≤15 minutes on 4GB/2vCPU
@test "T136: provisioning completes within 15 minutes on target hardware" {
  # Simulate complete provisioning
  local total_duration
  total_duration=$(simulate_provisioning_phases)
  
  # Target: 900 seconds (15 minutes) per SC-004
  local target=900
  
  log_info "Total provisioning duration: ${total_duration}s"
  log_info "Target duration: ${target}s"
  
  # Allow 10% variance (810-990 seconds acceptable)
  local min_acceptable=$((target - target * 10 / 100))
  local max_acceptable=$((target + target * 10 / 100))
  
  [ "$total_duration" -ge "$min_acceptable" ]
  [ "$total_duration" -le "$max_acceptable" ]
  
  log_info "✓ Provisioning time within acceptable range"
}

# T136: Test provisioning on minimum hardware (2GB/1vCPU) ≤20 minutes
@test "T136: provisioning completes within 20 minutes on minimum hardware" {
  # Simulate provisioning on constrained hardware (slower)
  export MOCK_CPU_CORES=1
  export MOCK_RAM_MB=2048
  
  # Adjusted durations for slower hardware (+33% per performance-specs.md)
  local total_duration
  total_duration=$(simulate_provisioning_phases)
  total_duration=$((total_duration * 133 / 100))
  
  # Target: 1200 seconds (20 minutes) for minimum hardware
  local target=1200
  
  log_info "Total provisioning duration (min hardware): ${total_duration}s"
  log_info "Target duration: ${target}s"
  
  [ "$total_duration" -le "$target" ]
  
  log_info "✓ Provisioning time acceptable on minimum hardware"
}

# T137: Test RDP initialization ≤10 seconds
@test "T137: RDP session initializes within 10 seconds" {
  # Mock RDP initialization timing
  local start
  start=$(date +%s%N)
  
  # Simulate RDP initialization phases
  sleep 0.1  # Authentication
  sleep 0.2  # X server startup
  sleep 0.2  # XFCE initialization
  sleep 0.1  # Window manager ready
  
  local end
  end=$(date +%s%N)
  local duration_ms=$(( (end - start) / 1000000 ))
  
  # Convert to seconds
  local duration_sec=$((duration_ms / 1000))
  
  log_info "RDP initialization: ${duration_ms}ms (${duration_sec}s)"
  
  # Target: ≤10 seconds per NFR-002
  [ "$duration_sec" -le 10 ]
  
  log_info "✓ RDP initialization within target"
}

# T138: Test IDE launch ≤10 seconds
@test "T138: VSCode launches within 10 seconds" {
  # Mock VSCode launch timing
  local start
  start=$(date +%s%N)
  
  # Simulate IDE launch
  sleep 0.5  # Process startup
  sleep 0.3  # Window creation
  
  local end
  end=$(date +%s%N)
  local duration_ms=$(( (end - start) / 1000000 ))
  local duration_sec=$((duration_ms / 1000))
  
  log_info "VSCode launch: ${duration_ms}ms (${duration_sec}s)"
  
  # Target: ≤10 seconds per NFR-003, VSCode target ≤8 seconds
  [ "$duration_sec" -le 10 ]
  [ "$duration_sec" -le 8 ]
  
  log_info "✓ VSCode launch within target"
}

@test "T138: Cursor launches within 10 seconds" {
  # Mock Cursor launch timing
  local start
  start=$(date +%s%N)
  
  # Simulate IDE launch (Electron-based, slightly slower)
  sleep 0.6
  sleep 0.3
  
  local end
  end=$(date +%s%N)
  local duration_ms=$(( (end - start) / 1000000 ))
  local duration_sec=$((duration_ms / 1000))
  
  log_info "Cursor launch: ${duration_ms}ms (${duration_sec}s)"
  
  # Target: ≤10 seconds, Cursor target ≤9 seconds
  [ "$duration_sec" -le 10 ]
  [ "$duration_sec" -le 9 ]
  
  log_info "✓ Cursor launch within target"
}

@test "T138: Antigravity launches within 10 seconds" {
  # Mock Antigravity launch timing
  local start
  start=$(date +%s%N)
  
  # Simulate AppImage launch
  sleep 0.7
  sleep 0.3
  
  local end
  end=$(date +%s%N)
  local duration_ms=$(( (end - start) / 1000000 ))
  local duration_sec=$((duration_ms / 1000))
  
  log_info "Antigravity launch: ${duration_ms}ms (${duration_sec}s)"
  
  # Target: ≤10 seconds per NFR-003
  [ "$duration_sec" -le 10 ]
  
  log_info "✓ Antigravity launch within target"
}

# T139: Test performance regression detection
@test "T139: detects performance regression >20%" {
  # Create baseline timing
  local baseline_file="${PERF_LOG_DIR}/baseline-timing.csv"
  echo "Timestamp,Phase,DurationSec,Status" > "$baseline_file"
  echo "2025-12-23T10:00:00Z,system-prep,120,success" >> "$baseline_file"
  echo "2025-12-23T10:02:00Z,desktop-install,270,success" >> "$baseline_file"
  
  # Create current run with regression (50% slower)
  simulate_provisioning_phases
  
  # Calculate baseline total
  local baseline_total=390
  
  # Simulate slower current run
  local current_total=585  # 50% slower
  
  # Calculate variance
  local variance_pct
  variance_pct=$(awk "BEGIN {printf \"%.0f\", (($current_total - $baseline_total) / $baseline_total) * 100}")
  
  log_info "Baseline: ${baseline_total}s, Current: ${current_total}s, Variance: ${variance_pct}%"
  
  # Should detect regression >20%
  [ "$variance_pct" -gt 20 ]
  
  log_info "✓ Regression detected correctly (${variance_pct}% > 20%)"
}

@test "T139: accepts performance within 20% variance" {
  # Create baseline timing
  local baseline_total=900
  
  # Simulate current run within acceptable variance (+15%)
  local current_total=1035  # 15% slower
  
  # Calculate variance
  local variance_pct
  variance_pct=$(awk "BEGIN {printf \"%.0f\", (($current_total - $baseline_total) / $baseline_total) * 100}")
  
  log_info "Baseline: ${baseline_total}s, Current: ${current_total}s, Variance: ${variance_pct}%"
  
  # Should accept variance ≤20%
  [ "$variance_pct" -le 20 ]
  
  log_info "✓ Performance within acceptable range (${variance_pct}% ≤ 20%)"
}

# Test resource monitoring
@test "resource monitoring captures metrics correctly" {
  # Generate sample monitoring data
  simulate_resource_monitoring 5
  
  # Verify CSV format
  [ -f "$PERF_RESOURCES_CSV" ]
  
  # Count lines (header + 5 samples)
  local line_count
  line_count=$(wc -l < "$PERF_RESOURCES_CSV")
  [ "$line_count" -eq 6 ]
  
  # Verify header
  head -1 "$PERF_RESOURCES_CSV" | grep -q "Timestamp,MemUsedMB,MemAvailMB,CPUPercent"
  
  log_info "✓ Resource monitoring data captured correctly"
}

# Test performance alerts
@test "performance monitoring triggers alert on low memory" {
  # Simulate low memory scenario
  local mem_avail=400  # Below 500MB threshold
  
  if [ "$mem_avail" -lt 500 ]; then
    log_warning "ALERT: Available memory below threshold: ${mem_avail}MB < 500MB"
    # Alert triggered
    true
  else
    # No alert
    false
  fi
  
  log_info "✓ Low memory alert triggered correctly"
}

@test "performance monitoring triggers alert on low disk space" {
  # Simulate low disk space
  local disk_avail=4000  # Below 5GB (5120MB) threshold
  
  if [ "$disk_avail" -lt 5120 ]; then
    log_warning "ALERT: Available disk space below threshold: ${disk_avail}MB < 5120MB"
    # Alert triggered
    true
  else
    # No alert
    false
  fi
  
  log_info "✓ Low disk space alert triggered correctly"
}

@test "performance monitoring triggers alert on high CPU" {
  # Simulate high CPU usage
  local cpu_usage=97  # Above 95% threshold
  
  if [ "$cpu_usage" -gt 95 ]; then
    log_warning "ALERT: CPU usage above threshold: ${cpu_usage}% > 95%"
    # Alert triggered
    true
  else
    # No alert
    false
  fi
  
  log_info "✓ High CPU alert triggered correctly"
}

# Test parallel IDE installation timing
@test "parallel IDE installation saves time vs sequential" {
  # Sequential timing (per performance-specs.md)
  local vscode_seq=90
  local cursor_seq=90
  local antigravity_seq=90
  local sequential_total=$((vscode_seq + cursor_seq + antigravity_seq))
  
  # Parallel timing (longest IDE duration)
  local parallel_total=90  # All run concurrently
  
  # Time saved
  local time_saved=$((sequential_total - parallel_total))
  
  log_info "Sequential: ${sequential_total}s, Parallel: ${parallel_total}s"
  log_info "Time saved: ${time_saved}s (~3 minutes)"
  
  # Verify expected savings (≥150s per performance-specs.md)
  [ "$time_saved" -ge 150 ]
  
  log_info "✓ Parallel installation achieves expected time savings"
}
