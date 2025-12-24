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
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Progress tracking variables
TOTAL_PHASES=10
CURRENT_PHASE=0
PHASE_START_TIME=0
OVERALL_START_TIME=0
PHASE_NAME=""

# Visual indicators
readonly SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPINNER_PID=0

# Initialize progress tracking
# Args: $1 - total number of phases
progress_init() {
  local total="${1:-10}"
  TOTAL_PHASES="$total"
  CURRENT_PHASE=0
  OVERALL_START_TIME=$(date +%s)
  
  log_debug "Progress tracking initialized: $TOTAL_PHASES phases"
}

# Start a new phase
# Args: $1 - phase number, $2 - phase name
progress_start_phase() {
  local phase_num="$1"
  local phase_name="$2"
  
  CURRENT_PHASE="$phase_num"
  PHASE_NAME="$phase_name"
  PHASE_START_TIME=$(date +%s)
  
  log_info "Phase $phase_num/$TOTAL_PHASES: $phase_name"
  log_debug "Phase started at: $(date)"
}

# Complete current phase
# Args: $1 - phase number
progress_complete_phase() {
  local phase_num="$1"
  local phase_end_time
  local phase_duration
  
  phase_end_time=$(date +%s)
  phase_duration=$((phase_end_time - PHASE_START_TIME))
  
  log_info "Phase $phase_num completed in $(progress_format_duration "$phase_duration")"
}

# Calculate overall progress percentage
# Returns: progress percentage (0-100)
progress_get_percentage() {
  if [[ $TOTAL_PHASES -eq 0 ]]; then
    echo "0"
    return
  fi
  
  local percentage
  percentage=$(awk "BEGIN {printf \"%.0f\", ($CURRENT_PHASE / $TOTAL_PHASES) * 100}")
  echo "$percentage"
}

# Estimate remaining time
# Returns: estimated seconds remaining
progress_estimate_remaining() {
  if [[ $CURRENT_PHASE -eq 0 ]]; then
    echo "0"
    return
  fi
  
  local elapsed
  local per_phase_avg
  local remaining_phases
  local estimated_remaining
  
  elapsed=$(($(date +%s) - OVERALL_START_TIME))
  per_phase_avg=$((elapsed / CURRENT_PHASE))
  remaining_phases=$((TOTAL_PHASES - CURRENT_PHASE))
  estimated_remaining=$((per_phase_avg * remaining_phases))
  
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
  
  bar=$(printf '%*s' "$filled_length" | tr ' ' '█')
  bar+=$(printf '%*s' "$empty_length" | tr ' ' '░')
  
  echo -ne "\r[${bar}] ${percentage}%"
}

# Update progress display
progress_update() {
  local percentage
  local elapsed
  local remaining
  
  percentage=$(progress_get_percentage)
  elapsed=$(($(date +%s) - OVERALL_START_TIME))
  remaining=$(progress_estimate_remaining)
  
  if [[ -t 1 ]]; then
    progress_show_bar "$percentage"
    echo -ne " | Elapsed: $(progress_format_duration "$elapsed")"
    
    if [[ $remaining -gt 0 ]]; then
      echo -ne " | Remaining: ~$(progress_format_duration "$remaining")"
    fi
    
    echo -ne "    "
  fi
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

# Check if phase duration exceeds estimate
# Args: $1 - phase duration, $2 - estimated duration
# Returns: 0 if within limits, 1 if exceeded
progress_check_duration_warning() {
  local actual="$1"
  local estimate="$2"
  local threshold
  
  threshold=$((estimate * 150 / 100))  # 150% of estimate
  
  if [[ $actual -gt $threshold ]]; then
    log_warning "Phase took longer than expected: $(progress_format_duration "$actual") vs ~$(progress_format_duration "$estimate")"
    return 1
  fi
  
  return 0
}

# Get current phase info
progress_get_current_phase() {
  echo "Phase $CURRENT_PHASE/$TOTAL_PHASES: $PHASE_NAME"
}

# Persist progress state (for crash recovery)
# Args: $1 - state file path
progress_save_state() {
  local state_file="$1"
  
  cat > "$state_file" <<EOF
TOTAL_PHASES=$TOTAL_PHASES
CURRENT_PHASE=$CURRENT_PHASE
PHASE_START_TIME=$PHASE_START_TIME
OVERALL_START_TIME=$OVERALL_START_TIME
PHASE_NAME="$PHASE_NAME"
EOF
  
  log_debug "Progress state saved to: $state_file"
}

# Restore progress state
# Args: $1 - state file path
progress_load_state() {
  local state_file="$1"
  
  if [[ ! -f "$state_file" ]]; then
    log_warning "Progress state file not found: $state_file"
    return 1
  fi
  
  # shellcheck source=/dev/null
  source "$state_file"
  
  log_info "Progress state restored from: $state_file"
  log_debug "Resumed at: $(progress_get_current_phase)"
  
  return 0
}
