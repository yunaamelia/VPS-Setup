#!/bin/bash
# performance-monitor.sh - Real-time performance monitoring during provisioning
# Tracks CPU, memory, disk, and network usage with threshold alerts

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_PERFORMANCE_MONITOR_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _PERFORMANCE_MONITOR_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/logger.sh"

# Monitoring configuration
readonly PERF_LOG_DIR="${PERF_LOG_DIR:-/var/log/vps-provision}"
readonly PERF_RESOURCES_CSV="${PERF_RESOURCES_CSV:-${PERF_LOG_DIR}/resources.csv}"
readonly PERF_TIMING_CSV="${PERF_TIMING_CSV:-${PERF_LOG_DIR}/timing.csv}"
readonly PERF_MONITOR_INTERVAL="${PERF_MONITOR_INTERVAL:-10}"  # seconds
readonly PERF_MONITOR_PID_FILE="${PERF_MONITOR_PID_FILE:-/var/run/vps-provision-monitor.pid}"

# Alert thresholds (from performance-specs.md)
readonly MEM_CRITICAL_MB=500      # Alert if available memory < 500MB
readonly DISK_CRITICAL_MB=5120    # Alert if available disk < 5GB
readonly CPU_CRITICAL_PCT=95      # Alert if CPU usage > 95%

# Background monitor PID
MONITOR_PID=0

# Initialize performance monitoring
perf_monitor_init() {
  # Create log directory if needed
  if [[ ! -d "$PERF_LOG_DIR" ]]; then
    mkdir -p "$PERF_LOG_DIR" 2>/dev/null || true
  fi
  
  # Initialize CSV headers if files don't exist
  if [[ ! -f "$PERF_RESOURCES_CSV" ]]; then
    echo "Timestamp,MemUsedMB,MemAvailMB,CPUPercent,DiskAvailMB,LoadAvg1m,ProcessCount" > "$PERF_RESOURCES_CSV"
  fi
  
  if [[ ! -f "$PERF_TIMING_CSV" ]]; then
    echo "Timestamp,Phase,DurationSec,Status" > "$PERF_TIMING_CSV"
  fi
  
  log_debug "Performance monitoring initialized"
}

# Start background monitoring
perf_monitor_start() {
  if [[ -f "$PERF_MONITOR_PID_FILE" ]]; then
    local old_pid
    old_pid=$(cat "$PERF_MONITOR_PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
      log_warning "Monitor already running with PID $old_pid"
      return 0
    fi
  fi
  
  perf_monitor_init
  perf_monitor_background &
  MONITOR_PID=$!
  echo "$MONITOR_PID" > "$PERF_MONITOR_PID_FILE"
  
  log_info "Performance monitoring started (PID: $MONITOR_PID)"
}

# Stop background monitoring
perf_monitor_stop() {
  if [[ -f "$PERF_MONITOR_PID_FILE" ]]; then
    local pid
    pid=$(cat "$PERF_MONITOR_PID_FILE")
    
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      log_info "Performance monitoring stopped (PID: $pid)"
    fi
    
    rm -f "$PERF_MONITOR_PID_FILE"
  fi
  
  MONITOR_PID=0
}

# Background monitoring loop
perf_monitor_background() {
  while true; do
    perf_monitor_collect
    sleep "$PERF_MONITOR_INTERVAL"
  done
}

# Collect current system metrics
perf_monitor_collect() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Memory metrics (in MB)
  local mem_used mem_avail
  read -r mem_used mem_avail <<< "$(free -m | awk '/^Mem:/ {print $3, $7}')"
  
  # CPU utilization (percentage)
  local cpu_usage
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | cut -d'.' -f1)
  
  # Disk available (in MB)
  local disk_avail
  disk_avail=$(df -BM / | awk 'NR==2 {print $4}' | sed 's/M//')
  
  # Load average (1 minute)
  local load_avg
  load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
  
  # Process count
  local proc_count
  proc_count=$(ps aux | wc -l)
  
  # Write to CSV
  echo "${timestamp},${mem_used},${mem_avail},${cpu_usage},${disk_avail},${load_avg},${proc_count}" >> "$PERF_RESOURCES_CSV"
  
  # Check thresholds and alert
  perf_monitor_check_thresholds "$mem_avail" "$disk_avail" "$cpu_usage"
}

# Check resource thresholds and log alerts
perf_monitor_check_thresholds() {
  local mem_avail=$1
  local disk_avail=$2
  local cpu_usage=$3
  
  # Memory check
  if ((mem_avail < MEM_CRITICAL_MB)); then
    log_warning "ALERT: Available memory below threshold: ${mem_avail}MB < ${MEM_CRITICAL_MB}MB"
  fi
  
  # Disk check
  if ((disk_avail < DISK_CRITICAL_MB)); then
    log_warning "ALERT: Available disk space below threshold: ${disk_avail}MB < ${DISK_CRITICAL_MB}MB"
  fi
  
  # CPU check
  if ((cpu_usage > CPU_CRITICAL_PCT)); then
    log_warning "ALERT: CPU usage above threshold: ${cpu_usage}% > ${CPU_CRITICAL_PCT}%"
  fi
}

# Log phase timing
# Args: $1 - phase name, $2 - duration in seconds, $3 - status (success/failure)
perf_monitor_log_timing() {
  local phase=$1
  local duration=$2
  local status=${3:-success}
  local timestamp
  
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "${timestamp},${phase},${duration},${status}" >> "$PERF_TIMING_CSV"
  
  log_debug "Phase timing logged: $phase = ${duration}s ($status)"
}

# Check if phase exceeded expected duration
# Args: $1 - phase name, $2 - actual duration, $3 - expected duration
# Returns: 0 if within tolerance, 1 if exceeded warning threshold
perf_monitor_check_phase_duration() {
  local phase=$1
  local actual=$2
  local expected=$3
  local threshold_warn=1.5  # 150% of expected (per performance-specs.md §UX-006)
  local threshold_critical=2.0  # 200% of expected
  
  # Calculate percentage
  local percentage
  percentage=$(echo "scale=2; $actual / $expected" | bc)
  
  if (( $(echo "$percentage >= $threshold_critical" | bc -l) )); then
    log_error "Phase '$phase' critically exceeded expected duration: ${actual}s vs ${expected}s (${percentage}x)"
    return 2
  elif (( $(echo "$percentage >= $threshold_warn" | bc -l) )); then
    log_warning "Phase '$phase' exceeded expected duration: ${actual}s vs ${expected}s (${percentage}x)"
    return 1
  fi
  
  log_debug "Phase '$phase' completed within expected duration: ${actual}s vs ${expected}s"
  return 0
}

# Generate performance summary report
perf_monitor_report() {
  local output_file="${1:-${PERF_LOG_DIR}/performance-report.json}"
  
  log_info "Generating performance report..."
  
  # Calculate summary statistics
  local total_duration avg_cpu avg_mem peak_cpu peak_mem
  
  # Read timing data
  if [[ -f "$PERF_TIMING_CSV" ]]; then
    total_duration=$(awk -F',' 'NR>1 {sum+=$3} END {print sum}' "$PERF_TIMING_CSV")
  else
    total_duration=0
  fi
  
  # Read resource data
  if [[ -f "$PERF_RESOURCES_CSV" ]]; then
    avg_cpu=$(awk -F',' 'NR>1 {sum+=$4; count++} END {if(count>0) print int(sum/count); else print 0}' "$PERF_RESOURCES_CSV")
    avg_mem=$(awk -F',' 'NR>1 {sum+=$2; count++} END {if(count>0) print int(sum/count); else print 0}' "$PERF_RESOURCES_CSV")
    peak_cpu=$(awk -F',' 'NR>1 {if($4>max) max=$4} END {print max}' "$PERF_RESOURCES_CSV")
    peak_mem=$(awk -F',' 'NR>1 {if($2>max) max=$2} END {print max}' "$PERF_RESOURCES_CSV")
  else
    avg_cpu=0
    avg_mem=0
    peak_cpu=0
    peak_mem=0
  fi
  
  # Generate JSON report
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  cat > "$output_file" <<EOF
{
  "timestamp": "$timestamp",
  "summary": {
    "total_duration_sec": ${total_duration:-0},
    "target_duration_sec": 900,
    "performance_score": $(echo "scale=2; 100 * (900 / ${total_duration:-900})" | bc)
  },
  "resource_usage": {
    "cpu_avg_percent": ${avg_cpu:-0},
    "cpu_peak_percent": ${peak_cpu:-0},
    "memory_avg_mb": ${avg_mem:-0},
    "memory_peak_mb": ${peak_mem:-0}
  },
  "data_files": {
    "resources": "$PERF_RESOURCES_CSV",
    "timing": "$PERF_TIMING_CSV"
  }
}
EOF
  
  log_info "Performance report generated: $output_file"
  cat "$output_file"
}

# Cleanup monitoring resources
perf_monitor_cleanup() {
  perf_monitor_stop
  
  # Archive old logs if they exist
  if [[ -f "$PERF_RESOURCES_CSV" ]] && [[ -f "$PERF_TIMING_CSV" ]]; then
    local archive_dir="${PERF_LOG_DIR}/archive"
    mkdir -p "$archive_dir" 2>/dev/null || true
    
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    
    mv "$PERF_RESOURCES_CSV" "${archive_dir}/resources-${timestamp}.csv" 2>/dev/null || true
    mv "$PERF_TIMING_CSV" "${archive_dir}/timing-${timestamp}.csv" 2>/dev/null || true
    
    log_debug "Performance logs archived"
  fi
}

# Signal handler for cleanup
trap 'perf_monitor_stop' EXIT INT TERM

# Main execution when run as script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    start)
      perf_monitor_start
      wait $MONITOR_PID
      ;;
    stop)
      perf_monitor_stop
      ;;
    report)
      perf_monitor_report "${2:-}"
      ;;
    *)
      echo "Usage: $0 {start|stop|report [output_file]}"
      exit 1
      ;;
  esac
fi
