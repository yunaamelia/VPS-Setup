#!/bin/bash
# progress.sh - Progress tracking for VPS provisioning
# Provides phase tracking, percentage calculation, time estimation, and visual indicators

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_PROGRESS_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _PROGRESS_SH_LOADED=1

# Source logger for output
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Source performance monitoring utilities (T130)
if [[ -f "${LIB_DIR}/utils/performance-monitor.sh" ]]; then
  # shellcheck source=lib/utils/performance-monitor.sh
  source "${LIB_DIR}/utils/performance-monitor.sh"
fi

# Progress tracking variables
TOTAL_PHASES=10
CURRENT_PHASE=0
PHASE_START_TIME=0
OVERALL_START_TIME=0
PHASE_NAME=""
LAST_UPDATE_TIME=0

# Phase timing tracking (T130 - Performance Instrumentation)
declare -gA PHASE_START_TIMES
declare -gA PHASE_END_TIMES
declare -gA PHASE_DURATIONS

# Phase weight configuration (for more accurate time estimation - UX-002)
# Weights represent relative complexity/duration of each phase
declare -gA PHASE_WEIGHTS=(
  [system-prep]=10
  [desktop-install]=15
  [rdp-config]=8
  [user-creation]=5
  [ide-vscode]=12
  [ide-cursor]=12
  [ide-antigravity]=10
  [terminal-setup]=6
  [dev-tools]=8
  [verification]=14
)

# Progress state persistence (UX-005)
PROGRESS_STATE_FILE="${PROGRESS_STATE_FILE:-/var/vps-provision/progress.state}"
PROGRESS_STATE_DIR="$(dirname "${PROGRESS_STATE_FILE}")"

# Visual indicators (UX-022: Avoid complex ASCII art for critical info)
# Using simple text-based indicators that work with screen readers
readonly SPINNER_CHARS='-\\|/'  # Simple rotation instead of complex Unicode
SPINNER_PID=0


# UX Enhancement: Color codes for visual hierarchy (UX-004, UX-020)
# Note: Using PROGRESS_COLOR_* prefix to avoid conflicts with logger.sh colors
if [[ -z "${PROGRESS_COLOR_CURRENT:-}" ]]; then
  readonly PROGRESS_COLOR_CURRENT='\033[1;37m'    # Bold white for current step
  readonly PROGRESS_COLOR_COMPLETED='\033[2;32m'  # Dimmed green for completed
  readonly PROGRESS_COLOR_PENDING='\033[0;37m'    # Normal white for pending
  readonly PROGRESS_COLOR_WARNING='\033[1;33m'    # Bold yellow for warnings
  readonly PROGRESS_COLOR_RESET='\033[0m'         # Reset
fi

# Phase duration estimates (in seconds) for UX-006 warnings
declare -gA PHASE_ESTIMATES=(
  [system-prep]=120
  [desktop-install]=180
  [rdp-config]=90
  [user-creation]=60
  [ide-vscode]=150
  [ide-cursor]=150
  [ide-antigravity]=120
  [terminal-setup]=60
  [dev-tools]=90
  [verification]=120
)

# Initialize progress tracking
# Args: $1 - total number of phases
progress_init() {
  local total="${1:-10}"
  TOTAL_PHASES="$total"
  CURRENT_PHASE=0
  OVERALL_START_TIME=$(date +%s)
  LAST_UPDATE_TIME=$(date +%s)
  
  # UX-005: Create progress state directory if needed
  if [[ ! -d "$PROGRESS_STATE_DIR" ]]; then
    mkdir -p "$PROGRESS_STATE_DIR" 2>/dev/null || true
  fi
  
  log_debug "Progress tracking initialized: $TOTAL_PHASES phases"
  
  # UX-005: Save initial state
  progress_save_state "$PROGRESS_STATE_FILE"
}

# Start a new phase
# Args: $1 - phase number, $2 - phase name
progress_start_phase() {
  local phase_num="$1"
  local phase_name="$2"
  
  CURRENT_PHASE="$phase_num"
  PHASE_NAME="$phase_name"
  PHASE_START_TIME=$(date +%s)
  
  # T130: Record phase start time for performance tracking
  local phase_key
  phase_key=$(echo "$phase_name" | tr '[:upper:] ' '[:lower:]-')
  PHASE_START_TIMES["$phase_key"]="$PHASE_START_TIME"
  
  log_info "Phase $phase_num/$TOTAL_PHASES: $phase_name"
  log_debug "Phase started at: $(date)"
  log_debug "Phase start timestamp: $PHASE_START_TIME"
  
  # UX-005: Persist state on phase change
  progress_save_state "$PROGRESS_STATE_FILE"
}

# Complete current phase
# Args: $1 - phase number
progress_complete_phase() {
  local phase_num="$1"
  local phase_end_time
  local phase_duration
  local phase_key
  
  phase_end_time=$(date +%s)
  phase_duration=$((phase_end_time - PHASE_START_TIME))
  
  # T130: Record phase end time and duration for performance tracking
  phase_key=$(echo "$PHASE_NAME" | tr '[:upper:] ' '[:lower:]-')
  PHASE_END_TIMES["$phase_key"]="$phase_end_time"
  PHASE_DURATIONS["$phase_key"]="$phase_duration"
  
  # Log timing to performance monitor if available (T130)
  if declare -f perf_monitor_log_timing &>/dev/null; then
    perf_monitor_log_timing "$phase_key" "$phase_duration" "success"
  fi
  
  # UX-006: Check if phase exceeded estimated duration by 50%
  if [[ -n "${PHASE_ESTIMATES[$phase_key]:-}" ]]; then
    local estimate="${PHASE_ESTIMATES[$phase_key]}"
    progress_check_duration_warning "$phase_duration" "$estimate"
    
    # T134: Check against performance thresholds and alert
    if declare -f perf_monitor_check_phase_duration &>/dev/null; then
      perf_monitor_check_phase_duration "$phase_key" "$phase_duration" "$estimate" || true
    fi
  fi
  
  log_info "Phase $phase_num completed in $(progress_format_duration "$phase_duration")"
  log_debug "Phase end timestamp: $phase_end_time, Duration: ${phase_duration}s"
  
  # UX-005: Persist completion state
  progress_save_state "$PROGRESS_STATE_FILE"
}

# Calculate overall progress percentage (UX-001)
# Returns: progress percentage (0-100)
progress_get_percentage() {
  if [[ $TOTAL_PHASES -eq 0 ]]; then
    echo "0"
    return
  fi
  
  # Calculate percentage based on completed phases
  local percentage
  percentage=$(awk "BEGIN {printf \"%.0f\", ($CURRENT_PHASE / $TOTAL_PHASES) * 100}")
  echo "$percentage"
}

# Estimate remaining time with weighted phases (UX-002)
# Returns: estimated seconds remaining
progress_estimate_remaining() {
  if [[ $CURRENT_PHASE -eq 0 ]]; then
    # Use total weight estimate
    local total_weight=0
    for weight in "${PHASE_WEIGHTS[@]}"; do
      total_weight=$((total_weight + weight))
    done
    echo "$((total_weight * 10))"  # Rough estimate: 10 seconds per weight unit
    return
  fi
  
  local elapsed
  local completed_weight=0
  local remaining_weight=0
  local per_weight_time
  local estimated_remaining
  
  elapsed=$(($(date +%s) - OVERALL_START_TIME))
  
  # Calculate completed and remaining weights
  local phase_index=0
  for phase_key in system-prep desktop-install rdp-config user-creation ide-vscode ide-cursor ide-antigravity terminal-setup dev-tools verification; do
    phase_index=$((phase_index + 1))
    local weight="${PHASE_WEIGHTS[$phase_key]:-10}"
    
    if [[ $phase_index -le $CURRENT_PHASE ]]; then
      completed_weight=$((completed_weight + weight))
    else
      remaining_weight=$((remaining_weight + weight))
    fi
  done
  
  if [[ $completed_weight -eq 0 ]]; then
    echo "$((remaining_weight * 10))"
    return
  fi
  
  # Calculate time per weight unit and estimate remaining
  per_weight_time=$(awk "BEGIN {printf \"%.0f\", $elapsed / $completed_weight}")
  estimated_remaining=$((per_weight_time * remaining_weight))
  
  echo "$estimated_remaining"
}

# Format duration in human-readable format
# Args: $1 - duration in seconds
# Returns: formatted duration string
progress_format_duration() {
  local seconds="$1"
  local minutes
  local hours
  
  if [[ $seconds -lt 60 ]]; then
    echo "${seconds}s"
  elif [[ $seconds -lt 3600 ]]; then
    minutes=$((seconds / 60))
    seconds=$((seconds % 60))
    echo "${minutes}m ${seconds}s"
  else
    hours=$((seconds / 3600))
    minutes=$(((seconds % 3600) / 60))
    seconds=$((seconds % 60))
    echo "${hours}h ${minutes}m ${seconds}s"
  fi
}

# Display progress bar
# Args: $1 - percentage (0-100)
progress_show_bar() {
  local percentage="$1"
  local bar_length=40
  local filled_length
  local empty_length
  local bar
  
  filled_length=$((percentage * bar_length / 100))
  empty_length=$((bar_length - filled_length))
  
  # UX-022: Use simple ASCII characters instead of Unicode for accessibility
  bar=$(printf '%*s' "$filled_length" "" | tr ' ' '=')
  bar+=$(printf '%*s' "$empty_length" "" | tr ' ' '-')
  
  echo -ne "\r[${bar}] ${percentage}%"
}

# Update progress display (UX-001, UX-002, UX-003)
# Updates at least every 2 seconds with percentage, elapsed, and remaining time
progress_update() {
  local current_time
  current_time=$(date +%s)
  
  # UX-003: Update at least every 2 seconds
  if [[ $((current_time - LAST_UPDATE_TIME)) -lt 2 ]] && [[ $LAST_UPDATE_TIME -gt 0 ]]; then
    return 0
  fi
  
  LAST_UPDATE_TIME=$current_time
  
  local percentage
  local elapsed
  local remaining
  
  percentage=$(progress_get_percentage)
  elapsed=$((current_time - OVERALL_START_TIME))
  remaining=$(progress_estimate_remaining)
  
  if [[ -t 1 ]] && [[ "${NO_COLOR:-0}" != "1" ]]; then
    # UX-001: Display percentage (0-100%)
    progress_show_bar "$percentage"
    echo -ne " | Elapsed: $(progress_format_duration "$elapsed")"
    
    # UX-002: Display estimated remaining time
    if [[ $remaining -gt 0 ]]; then
      echo -ne " | Remaining: ~$(progress_format_duration "$remaining")"
    fi
    
    echo -ne "    "
  else
    # Plain text output for non-TTY or no-color mode
    log_info "Progress: ${percentage}% | Elapsed: $(progress_format_duration "$elapsed") | Remaining: ~$(progress_format_duration "$remaining")"
  fi
  
  # UX-005: Periodically persist state
  progress_save_state "$PROGRESS_STATE_FILE"
}

# Clear progress line
progress_clear_line() {
  if [[ -t 1 ]]; then
    echo -ne "\r\033[K"
  fi
}

# Show spinner (for long-running operations)
# Args: $1 - message
progress_spinner_start() {
  local message="${1:-Working}"
  
  if [[ ! -t 1 ]]; then
    log_info "$message..."
    return 0
  fi
  
  (
    local i=0
    while true; do
      local char="${SPINNER_CHARS:i++%${#SPINNER_CHARS}:1}"
      echo -ne "\r$char $message... "
      sleep 0.1
    done
  ) &
  
  SPINNER_PID=$!
  log_debug "Spinner started (PID: $SPINNER_PID)"
}

# Stop spinner
progress_spinner_stop() {
  if [[ $SPINNER_PID -gt 0 ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=0
    progress_clear_line
    log_debug "Spinner stopped"
  fi
}

# Display phase summary
progress_show_summary() {
  local total_duration
  
  total_duration=$(($(date +%s) - OVERALL_START_TIME))
  
  log_separator "="
  log_info "Provisioning Summary"
  log_separator "="
  log_info "Total phases completed: $CURRENT_PHASE/$TOTAL_PHASES"
  log_info "Total duration: $(progress_format_duration "$total_duration")"
  log_separator "="
}

# Check if phase duration exceeds estimate (UX-006)
# Args: $1 - phase duration, $2 - estimated duration
# Returns: 0 if within limits, 1 if exceeded
progress_check_duration_warning() {
  local actual="$1"
  local estimate="$2"
  local threshold
  
  threshold=$((estimate * 150 / 100))  # 150% of estimate per UX-006
  
  if [[ $actual -gt $threshold ]]; then
    # UX-006: Warn when phase exceeds 150% of estimate
    if [[ "${NO_COLOR:-0}" != "1" ]] && [[ -t 1 ]]; then
      echo -e "\n${PROGRESS_COLOR_WARNING}⚠ Phase taking longer than expected: $(progress_format_duration "$actual") (expected ~$(progress_format_duration "$estimate"))${PROGRESS_COLOR_RESET}"
    else
      log_warning "Phase taking longer than expected: $(progress_format_duration "$actual") (expected ~$(progress_format_duration "$estimate"))"
    fi
    return 1
  fi
  
  return 0
}

# Get current phase info
progress_get_current_phase() {
  echo "Phase $CURRENT_PHASE/$TOTAL_PHASES: $PHASE_NAME"
}

# Persist progress state (UX-005 - crash recovery)
# Args: $1 - state file path
progress_save_state() {
  local state_file="$1"
  
  # Create directory if it doesn't exist
  local state_dir
  state_dir=$(dirname "$state_file")
  if [[ ! -d "$state_dir" ]]; then
    mkdir -p "$state_dir" 2>/dev/null || {
      log_debug "Failed to create state directory: $state_dir"
      return 1
    }
  fi
  
  # Save state with timestamp
  cat > "$state_file" <<EOF
# VPS Provision Progress State
# Generated: $(date)
TOTAL_PHASES=$TOTAL_PHASES
CURRENT_PHASE=$CURRENT_PHASE
PHASE_START_TIME=$PHASE_START_TIME
OVERALL_START_TIME=$OVERALL_START_TIME
LAST_UPDATE_TIME=$LAST_UPDATE_TIME
PHASE_NAME="$PHASE_NAME"
EOF
  
  log_debug "Progress state saved to: $state_file"
}

# Restore progress state (UX-005)
# Args: $1 - state file path
progress_load_state() {
  local state_file="$1"
  
  if [[ ! -f "$state_file" ]]; then
    log_warning "Progress state file not found: $state_file"
    return 1
  fi
  
  # Validate state file is readable
  if [[ ! -r "$state_file" ]]; then
    log_error "Progress state file not readable: $state_file"
    return 1
  fi
  
  # shellcheck source=/dev/null
  source "$state_file"
  
  log_info "Progress state restored from: $state_file"
  log_info "Resumed at: Phase $CURRENT_PHASE/$TOTAL_PHASES - $PHASE_NAME"
  
  return 0
}

#######################################
# Display phase list with visual hierarchy (UX-004)
# Shows completed, current, and pending phases with different visual styles
# Globals:
#   CURRENT_PHASE, TOTAL_PHASES
#   COLOR_* constants
# Arguments:
#   $@ - Array of phase names
# Returns:
#   None
#######################################
progress_show_phase_list() {
  local -a phases=("$@")
  local use_colors=true
  
  # Disable colors if NO_COLOR set or not in TTY
  if [[ "${NO_COLOR:-0}" == "1" ]] || [[ ! -t 1 ]]; then
    use_colors=false
  fi
  
  echo ""
  log_info "Provisioning Progress:"
  echo ""
  
  for i in "${!phases[@]}"; do
    local phase_num=$((i + 1))
    local phase_name="${phases[$i]}"
    local status_icon
    local color_code=""
    local reset_code=""
    
    if [[ $phase_num -lt $CURRENT_PHASE ]]; then
      # Completed phase
      status_icon="✓"
      if $use_colors; then
        color_code="$PROGRESS_COLOR_COMPLETED"
        reset_code="$PROGRESS_COLOR_RESET"
      fi
    elif [[ $phase_num -eq $CURRENT_PHASE ]]; then
      # Current phase
      status_icon="▶"
      if $use_colors; then
        color_code="$PROGRESS_COLOR_CURRENT"
        reset_code="$PROGRESS_COLOR_RESET"
      fi
    else
      # Pending phase
      status_icon="○"
      if $use_colors; then
        color_code="$PROGRESS_COLOR_PENDING"
        reset_code="$PROGRESS_COLOR_RESET"
      fi
    fi
    
    if $use_colors; then
      echo -e "  ${color_code}${status_icon} Phase ${phase_num}/${TOTAL_PHASES}: ${phase_name}${reset_code}"
    else
      echo "  [$status_icon] Phase ${phase_num}/${TOTAL_PHASES}: ${phase_name}"
    fi
  done
  
  echo ""
}

#######################################
# Format phase name for display (UX-004)
# Applies visual styling based on phase status
# Arguments:
#   $1 - Phase number
#   $2 - Phase name
#   $3 - Phase status (completed|current|pending)
# Returns:
#   Formatted phase name string
#######################################
progress_format_phase() {
  local phase_num="$1"
  local phase_name="$2"
  local status="${3:-pending}"
  local use_colors=true
  
  # Disable colors if NO_COLOR set or not in TTY
  if [[ "${NO_COLOR:-0}" == "1" ]] || [[ ! -t 1 ]]; then
    use_colors=false
  fi
  
  local status_icon
  local color_code=""
  local reset_code=""
  local prefix=""
  
  case "$status" in
    completed)
      status_icon="✓"
      prefix="[DONE]"
      if $use_colors; then
        color_code="$PROGRESS_COLOR_COMPLETED"
        reset_code="$PROGRESS_COLOR_RESET"
      fi
      ;;
    current)
      status_icon="▶"
      prefix="[NOW] "
      if $use_colors; then
        color_code="$PROGRESS_COLOR_CURRENT"
        reset_code="$PROGRESS_COLOR_RESET"
      fi
      ;;
    pending)
      status_icon="○"
      prefix="[TODO]"
      if $use_colors; then
        color_code="$PROGRESS_COLOR_PENDING"
        reset_code="$PROGRESS_COLOR_RESET"
      fi
      ;;
    *)
      status_icon="?"
      prefix="[????]"
      ;;
  esac
  
  if $use_colors; then
    echo -e "${color_code}${status_icon} ${prefix} Phase ${phase_num}: ${phase_name}${reset_code}"
  else
    echo "${prefix} Phase ${phase_num}: ${phase_name}"
  fi
}
#######################################
# Get phase timing data (T130 - Performance Instrumentation)
# Returns phase start, end, and duration times
# Arguments:
#   $1 - Phase name (e.g., "system-prep")
# Outputs:
#   Writes timing data to stdout in format: "start end duration"
# Returns:
#   0 if data found, 1 if not
#######################################
progress_get_phase_timing() {
  local phase_key="$1"
  
  local start="${PHASE_START_TIMES[$phase_key]:-0}"
  local end="${PHASE_END_TIMES[$phase_key]:-0}"
  local duration="${PHASE_DURATIONS[$phase_key]:-0}"
  
  if [[ $start -eq 0 ]]; then
    return 1
  fi
  
  echo "$start $end $duration"
  return 0
}

#######################################
# Get all phase timing data (T130)
# Outputs complete timing report for all phases
# Returns:
#   0 on success
#######################################
progress_get_all_timings() {
  log_info "Phase Timing Summary:"
  log_separator "-"
  
  local total_duration=0
  local phase_count=0
  
  for phase_key in system-prep desktop-install rdp-config user-creation ide-vscode ide-cursor ide-antigravity terminal-setup dev-tools verification; do
    if [[ -n "${PHASE_DURATIONS[$phase_key]:-}" ]]; then
      local duration="${PHASE_DURATIONS[$phase_key]}"
      local estimate="${PHASE_ESTIMATES[$phase_key]:-0}"
      local variance=""
      
      if [[ $estimate -gt 0 ]]; then
        local pct
        pct=$(awk "BEGIN {printf \"%.0f\", (($duration - $estimate) / $estimate) * 100}")
        variance=" (${pct}% vs estimate)"
      fi
      
      log_info "  $phase_key: $(progress_format_duration "$duration")$variance"
      total_duration=$((total_duration + duration))
      phase_count=$((phase_count + 1))
    fi
  done
  
  log_separator "-"
  log_info "Total: $(progress_format_duration "$total_duration") across $phase_count phases"
  
  # Performance score calculation (T136)
  if [[ $total_duration -gt 0 ]]; then
    local target=900  # 15 minutes target
    local score
    score=$(awk "BEGIN {printf \"%.1f\", (100.0 * $target) / $total_duration}")
    
    # Cap score at 100
    if (( $(echo "$score > 100" | bc -l) )); then
      score=100
    fi
    
    log_info "Performance Score: ${score}% (target: 15min, actual: $(progress_format_duration "$total_duration"))"
  fi
}

#######################################
# Export timing data to JSON (T141)
# Creates JSON performance report with all metrics
# Arguments:
#   $1 - Output file path (optional, defaults to performance-report.json)
# Returns:
#   0 on success, 1 on failure
#######################################
progress_export_timing_json() {
  local output_file="${1:-/var/log/vps-provision/performance-report.json}"
  local output_dir
  output_dir=$(dirname "$output_file")
  
  # Ensure output directory exists
  if [[ ! -d "$output_dir" ]]; then
    mkdir -p "$output_dir" 2>/dev/null || {
      log_error "Failed to create output directory: $output_dir"
      return 1
    }
  fi
  
  log_info "Exporting timing data to: $output_file"
  
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  local total_duration=0
  for duration in "${PHASE_DURATIONS[@]}"; do
    total_duration=$((total_duration + duration))
  done
  
  local target=900
  local performance_score
  if [[ $total_duration -gt 0 ]]; then
    performance_score=$(awk "BEGIN {printf \"%.1f\", (100.0 * $target) / $total_duration}")
    if (( $(echo "$performance_score > 100" | bc -l) )); then
      performance_score=100
    fi
  else
    performance_score=0
  fi
  
  # Build phases JSON array
  local phases_json="["
  local first=true
  
  for phase_key in system-prep desktop-install rdp-config user-creation ide-vscode ide-cursor ide-antigravity terminal-setup dev-tools verification; do
    if [[ -n "${PHASE_DURATIONS[$phase_key]:-}" ]]; then
      local duration="${PHASE_DURATIONS[$phase_key]}"
      local estimate="${PHASE_ESTIMATES[$phase_key]:-0}"
      local variance=0
      
      if [[ $estimate -gt 0 ]]; then
        variance=$(awk "BEGIN {printf \"%.1f\", (($duration - $estimate) / $estimate) * 100}")
      fi
      
      if ! $first; then
        phases_json+=","
      fi
      first=false
      
      phases_json+="
    {
      \"name\": \"$phase_key\",
      \"duration_sec\": $duration,
      \"target_sec\": $estimate,
      \"variance_pct\": $variance
    }"
    fi
  done
  
  phases_json+="
  ]"
  
  # Write JSON report
  cat > "$output_file" <<EOF
{
  "timestamp": "$timestamp",
  "summary": {
    "total_duration_sec": $total_duration,
    "target_duration_sec": $target,
    "performance_score": $performance_score,
    "phases_completed": ${#PHASE_DURATIONS[@]}
  },
  "phases": $phases_json
}
EOF
  
  log_info "Timing data exported successfully"
  return 0
}