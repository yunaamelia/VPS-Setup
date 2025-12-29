#!/bin/bash
# docker-provision-test.sh - Automated Docker testing for VPS provisioning tool
#
# Usage: ./bin/docker-provision-test.sh [OPTIONS]
#
# Options:
#   --keep-container    Preserve container after execution for debugging
#   --use-cache         Use Docker cache for faster builds (default: no-cache)
#   --log-file PATH     Custom log file location (default: logs/docker-test-TIMESTAMP.log)
#   --quiet             Minimal console output, full file logging
#   --json-output       Output results in JSON format for CI/CD
#   --help              Display this help message

set -euo pipefail

# ============================================
# Configuration & Constants
# ============================================
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly LOCK_FILE="/tmp/docker-provision-test.lock"
readonly MIN_DISK_SPACE_GB=5
readonly PERFORMANCE_TARGET=900  # 15 minutes in seconds
readonly MAX_IMAGES_TO_KEEP=3

# Default settings
KEEP_CONTAINER=false
USE_CACHE=false
QUIET_MODE=false
JSON_OUTPUT=false
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/docker-test-${TIMESTAMP}.log"
BUILD_LOG="${LOG_DIR}/docker-test-${TIMESTAMP}-build.log"
PROVISION_LOG="${LOG_DIR}/docker-test-${TIMESTAMP}-provision.log"

# Docker settings
IMAGE_NAME="vps-provision"
IMAGE_TAG="test-${TIMESTAMP}"
CONTAINER_NAME="vps-provision-test-${TIMESTAMP}"
DOCKERFILE="${PROJECT_ROOT}/tests/e2e/Dockerfile.test"

# Timing tracking
PHASE_START_TIME=0
SCRIPT_START_TIME=$(date +%s)

# Statistics
declare -A PHASE_DURATIONS
declare -A PHASE_STATUS
ERROR_COUNT=0
WARNING_COUNT=0
INFO_COUNT=0

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ============================================
# Logging Functions
# ============================================
log_to_file() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Ensure log directory exists before writing
    mkdir -p "$(dirname "${LOG_FILE}")"
    echo "[${timestamp}] $*" >> "${LOG_FILE}"
}

log_info() {
    log_to_file "[INFO] $*"
    [[ "${QUIET_MODE}" == "false" ]] && echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    ((WARNING_COUNT++))
    log_to_file "[WARNING] $*"
    [[ "${QUIET_MODE}" == "false" ]] && echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    ((ERROR_COUNT++))
    log_to_file "[ERROR] $*"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_phase() {
    local phase=$1
    shift
    log_to_file "[${phase}] $*"
    [[ "${QUIET_MODE}" == "false" ]] && echo -e "${CYAN}[${phase}]${NC} $*" >&2
}

log_debug() {
    log_to_file "[DEBUG] $*"
}

# ============================================
# Utility Functions
# ============================================
print_header() {
    if [[ "${QUIET_MODE}" == "false" ]]; then
        echo ""
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║        VPS PROVISION - DOCKER AUTOMATED TEST SCRIPT          ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
    fi
    log_info "Script version: ${SCRIPT_VERSION}"
    log_info "Timestamp: ${TIMESTAMP}"
    log_info "Project root: ${PROJECT_ROOT}"
}

format_duration() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local remaining=$((seconds % 60))
    printf "%dm %02ds" $minutes $remaining
}

format_size() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}")GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")MB"
    else
        echo "${bytes}B"
    fi
}

start_phase() {
    PHASE_START_TIME=$(date +%s)
}

end_phase() {
    local phase=$1
    local duration=$(($(date +%s) - PHASE_START_TIME))
    PHASE_DURATIONS[$phase]=$duration
    log_debug "Phase ${phase} duration: $(format_duration $duration)"
}

# ============================================
# Lock File Management
# ============================================
acquire_lock() {
    if [[ -e "${LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid=$(cat "${LOCK_FILE}")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Another instance is already running (PID: $lock_pid)"
            exit 1
        else
            log_warn "Stale lock file found, removing"
            rm -f "${LOCK_FILE}"
        fi
    fi
    echo $$ > "${LOCK_FILE}"
    log_debug "Lock acquired: ${LOCK_FILE}"
}

release_lock() {
    rm -f "${LOCK_FILE}"
    log_debug "Lock released"
}

# ============================================
# Prerequisites Check
# ============================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not running"
        log_error "Start Docker: sudo systemctl start docker"
        exit 1
    fi
    log_debug "Docker daemon: RUNNING"
    
    # Check Docker version
    local docker_version
    docker_version=$(docker version --format '{{.Server.Version}}')
    log_debug "Docker version: ${docker_version}"
    
    # Check Dockerfile exists
    if [[ ! -f "${DOCKERFILE}" ]]; then
        log_error "Dockerfile not found: ${DOCKERFILE}"
        exit 1
    fi
    log_debug "Dockerfile: ${DOCKERFILE}"
    
    # Check disk space
    local available_space
    available_space=$(df "${PROJECT_ROOT}" | awk 'NR==2 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [[ $available_gb -lt $MIN_DISK_SPACE_GB ]]; then
        log_error "Insufficient disk space: ${available_gb}GB available, ${MIN_DISK_SPACE_GB}GB required"
        log_error "Free space with: docker system prune -af"
        exit 5
    fi
    log_debug "Available disk space: ${available_gb}GB"
    
    # Create log directory
    mkdir -p "${LOG_DIR}"
    
    log_info "Prerequisites check passed"
}

# ============================================
# Phase 1: Docker Cleanup
# ============================================
cleanup_docker() {
    log_phase "CLEANUP" "Starting Docker cleanup phase..."
    start_phase
    
    local removed_count=0
    local freed_space=0
    
    # Stop running test containers
    log_phase "CLEANUP" "→ Stopping running containers..."
    local running_containers
    running_containers=$(docker ps --filter "name=vps-provision-test" --format "{{.Names}}" 2>/dev/null || true)
    
    if [[ -n "${running_containers}" ]]; then
        while IFS= read -r container; do
            docker stop "${container}" >/dev/null 2>&1 || true
            docker rm "${container}" >/dev/null 2>&1 || true
            ((removed_count++)) || true
            log_debug "Removed container: ${container}"
        done <<< "${running_containers}"
        log_phase "CLEANUP" "  DONE ($removed_count containers removed)"
    else
        log_phase "CLEANUP" "  DONE (0 containers found)"
    fi
    
    # Remove old images
    log_phase "CLEANUP" "→ Removing old images..."
    local old_images
    old_images=$(docker images "${IMAGE_NAME}" --format "{{.ID}} {{.Repository}}:{{.Tag}} {{.Size}}" 2>/dev/null || true)
    
    removed_count=0
    if [[ -n "${old_images}" ]]; then
        while read -r image_id image_name image_size; do
            local size_bytes
            size_bytes=$(docker image inspect "$image_id" --format='{{.Size}}' 2>/dev/null || echo "0")
            freed_space=$((freed_space + size_bytes))
            
            docker rmi -f "$image_id" >/dev/null 2>&1 || true
            ((removed_count++)) || true
            log_debug "Removed image: ${image_name} (${image_size})"
        done <<< "${old_images}"
        log_phase "CLEANUP" "  DONE ($removed_count images removed, $(format_size $freed_space) freed)"
    else
        log_phase "CLEANUP" "  DONE (0 images found)"
    fi
    
    # Prune build cache
    log_phase "CLEANUP" "→ Pruning build cache..."
    local prune_output
    prune_output=$(docker builder prune -af 2>&1 || true)
    local cache_freed
    cache_freed=$(echo "$prune_output" | grep -oP 'Total:\s+\K[\d.]+[A-Z]+' || echo "0B")
    log_phase "CLEANUP" "  DONE (${cache_freed} freed)"
    
    end_phase "cleanup"
    local duration=${PHASE_DURATIONS[cleanup]}
    log_phase "CLEANUP" "✓ Cleanup completed successfully"
    log_phase "CLEANUP" "  Duration: $(format_duration $duration)"
    echo ""
}

# ============================================
# Phase 2: Fresh Image Build
# ============================================
build_fresh_image() {
    log_phase "BUILD" "Starting fresh image build phase..."
    start_phase
    
    local build_start=$(date +%s)
    local build_flags="--pull"
    
    if [[ "${USE_CACHE}" == "false" ]]; then
        build_flags="--no-cache --pull"
        log_phase "BUILD" "→ Building image without cache..."
    else
        log_phase "BUILD" "→ Building image with cache..."
    fi
    
    # Build the image
    log_phase "BUILD" "  Image tag: ${IMAGE_NAME}:${IMAGE_TAG}"
    
    if docker build ${build_flags} \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        -f "${DOCKERFILE}" \
        "${PROJECT_ROOT}" \
        > "${BUILD_LOG}" 2>&1; then
        
        # Get image details
        local image_id
        local image_size
        image_id=$(docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "{{.ID}}")
        image_size=$(docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "{{.Size}}")
        
        log_phase "BUILD" "→ Build completed successfully"
        log_phase "BUILD" "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
        log_phase "BUILD" "  ID: ${image_id}"
        log_phase "BUILD" "  Size: ${image_size}"
        
        PHASE_STATUS["build"]="SUCCESS"
    else
        log_error "Image build failed"
        log_error "Build log: ${BUILD_LOG}"
        log_error ""
        log_error "Last 20 lines of build log:"
        tail -n 20 "${BUILD_LOG}" | while IFS= read -r line; do
            log_error "  $line"
        done
        log_error ""
        log_error "Troubleshooting:"
        log_error "  1. Check network connectivity"
        log_error "  2. Review full build log: ${BUILD_LOG}"
        log_error "  3. Verify Dockerfile syntax"
        
        PHASE_STATUS["build"]="FAILED"
        exit 2
    fi
    
    end_phase "build"
    local duration=${PHASE_DURATIONS[build]}
    log_phase "BUILD" "  Duration: $(format_duration $duration)"
    echo ""
}

# ============================================
# Phase 3: Provisioning Execution
# ============================================
run_provisioning() {
    log_phase "PROVISION" "Starting provisioning execution phase..."
    start_phase
    
    log_phase "PROVISION" "→ Launching container in privileged mode..."
    log_phase "PROVISION" "  Container: ${CONTAINER_NAME}"
    log_phase "PROVISION" "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
    
    # Determine if interactive
    local tty_flag=""
    if [[ -t 0 ]] && [[ "${QUIET_MODE}" == "false" ]]; then
        tty_flag="-it"
    fi
    
    # Run the container with cgroups v2 support for systemd
    local container_id
    container_id=$(docker run -d \
        --name "${CONTAINER_NAME}" \
        --privileged \
        --cgroupns=host \
        --tmpfs /tmp \
        --tmpfs /run \
        --tmpfs /run/lock \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        "${IMAGE_NAME}:${IMAGE_TAG}")
    
    log_debug "Container started: ${container_id}"
    
    # Wait for systemd to initialize and check container is running
    log_phase "PROVISION" "→ Waiting for systemd initialization..."
    sleep 5
    
    # Verify container is still running
    if ! docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container failed to start or exited immediately"
        log_error "Checking container logs..."
        docker logs "${CONTAINER_NAME}" 2>&1 | tail -n 30
        PHASE_STATUS["provision"]="FAILED"
        exit 3
    fi
    
    # Execute provisioning script
    log_phase "PROVISION" "→ Executing: /bin/vps-provision --log-level DEBUG"
    
    if [[ "${QUIET_MODE}" == "false" ]]; then
        # Stream to console and log file
        docker exec ${tty_flag} "${CONTAINER_NAME}" \
            /bin/vps-provision --log-level DEBUG \
            2>&1 | tee -a "${PROVISION_LOG}"
        local exit_code=${PIPESTATUS[0]}
    else
        # Log to file only
        docker exec "${CONTAINER_NAME}" \
            /bin/vps-provision --log-level DEBUG \
            > "${PROVISION_LOG}" 2>&1
        local exit_code=$?
    fi
    
    end_phase "provision"
    local duration=${PHASE_DURATIONS[provision]}
    
    if [[ $exit_code -eq 0 ]]; then
        log_phase "PROVISION" "→ Provisioning completed: SUCCESS"
        log_phase "PROVISION" "  Duration: $(format_duration $duration)"
        PHASE_STATUS["provision"]="SUCCESS"
    else
        log_error "Provisioning failed with exit code: $exit_code"
        log_error "Provision log: ${PROVISION_LOG}"
        log_error ""
        log_error "Analyzing errors..."
        
        # Extract errors from log
        if [[ -f "${PROVISION_LOG}" ]]; then
            local error_lines
            error_lines=$(grep -i "error" "${PROVISION_LOG}" | head -n 10)
            if [[ -n "${error_lines}" ]]; then
                log_error "Recent errors:"
                echo "$error_lines" | while IFS= read -r line; do
                    log_error "  $line"
                done
            fi
        fi
        
        PHASE_STATUS["provision"]="FAILED"
        
        if [[ "${KEEP_CONTAINER}" == "false" ]]; then
            log_warn "Setting --keep-container for debugging"
            KEEP_CONTAINER=true
        fi
        
        exit 4
    fi
    
    echo ""
}

# ============================================
# Phase 4: Results Report
# ============================================
generate_report() {
    log_phase "REPORT" "Generating results summary..."
    start_phase
    
    # Parse provision log for phase status
    declare -A provision_phases
    if [[ -f "${PROVISION_LOG}" ]]; then
        # Extract phase completion info
        while IFS= read -r line; do
            if [[ $line =~ completed.*\(([0-9]+)m\ ([0-9]+)s\) ]]; then
                local phase_name
                phase_name=$(echo "$line" | grep -oP '(?<=\[)[^\]]+(?=\])' | tail -n1)
                local minutes=${BASH_REMATCH[1]}
                local seconds=${BASH_REMATCH[2]}
                local total_seconds=$((minutes * 60 + seconds))
                provision_phases[$phase_name]=$total_seconds
            fi
        done < "${PROVISION_LOG}"
        
        # Count issues
        ERROR_COUNT=$(grep -c "\[ERROR\]" "${PROVISION_LOG}" 2>/dev/null || echo "0")
        WARNING_COUNT=$(grep -c "\[WARNING\]" "${PROVISION_LOG}" 2>/dev/null || echo "0")
        INFO_COUNT=$(grep -c "\[INFO\]" "${PROVISION_LOG}" 2>/dev/null || echo "0")
    fi
    
    # Calculate total duration
    local total_duration=$(($(date +%s) - SCRIPT_START_TIME))
    
    # Determine overall status
    local overall_status="SUCCESS"
    for status in "${PHASE_STATUS[@]}"; do
        if [[ "$status" == "FAILED" ]]; then
            overall_status="FAILED"
            break
        fi
    done
    
    # Generate output based on format
    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        generate_json_report "$overall_status" "$total_duration"
    else
        generate_text_report "$overall_status" "$total_duration" "${provision_phases[@]}"
    fi
    
    end_phase "report"
}

generate_text_report() {
    local overall_status=$1
    local total_duration=$2
    shift 2
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                     EXECUTION SUMMARY                         ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    printf "║ %-20s %-40s ║\n" "Overall Status:" "$overall_status"
    printf "║ %-20s %-40s ║\n" "Total Duration:" "$(format_duration $total_duration)"
    printf "║ %-20s %-40s ║\n" "Container ID:" "${CONTAINER_NAME}"
    printf "║ %-20s %-40s ║\n" "Exit Code:" "0"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║ Phase Status:                                                 ║"
    
    # List known phases
    local phases=(
        "system-prep" "desktop-env" "user-provisioning" "rdp-server"
        "ide-vscode" "ide-cursor" "ide-antigravity" "terminal-setup"
        "dev-tools" "firewall" "fail2ban" "verification"
    )
    
    for phase in "${phases[@]}"; do
        local duration="unknown"
        local status="✓"
        
        if [[ -v provision_phases[$phase] ]]; then
            duration=$(format_duration ${provision_phases[$phase]})
            printf "║   %s %-18s COMPLETED (%-8s)                  ║\n" "$status" "$phase" "$duration"
        fi
    done
    
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║ Issue Summary:                                                ║"
    printf "║   %-20s %-36s ║\n" "Errors:" "$ERROR_COUNT"
    printf "║   %-20s %-36s ║\n" "Warnings:" "$WARNING_COUNT"
    printf "║   %-20s %-36s ║\n" "Info Messages:" "$INFO_COUNT"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║ Log Files:                                                    ║"
    printf "║   %-15s %-44s ║\n" "Main Log:" "$(basename ${LOG_FILE})"
    printf "║   %-15s %-44s ║\n" "Build Log:" "$(basename ${BUILD_LOG})"
    printf "║   %-15s %-44s ║\n" "Provision Log:" "$(basename ${PROVISION_LOG})"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [[ "$overall_status" == "SUCCESS" ]]; then
        echo "✓ All phases completed successfully"
        if [[ $total_duration -le $PERFORMANCE_TARGET ]]; then
            echo "✓ Performance target met ($(format_duration $total_duration) ≤ 15 minutes)"
        else
            echo "⚠ Performance target exceeded ($(format_duration $total_duration) > 15 minutes)"
        fi
        echo "✓ No critical errors detected"
    else
        echo "✗ Provisioning completed with errors"
    fi
    echo ""
    
    if [[ "${KEEP_CONTAINER}" == "true" ]]; then
        echo "Container preserved for inspection: docker exec -it ${CONTAINER_NAME} bash"
        echo "To remove: docker rm -f ${CONTAINER_NAME}"
        echo ""
    fi
    
    echo "Log files saved to:"
    echo "  ${LOG_FILE}"
    echo ""
}

generate_json_report() {
    local overall_status=$1
    local total_duration=$2
    
    cat > "${LOG_DIR}/docker-test-${TIMESTAMP}-report.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "overall_status": "${overall_status}",
  "total_duration_seconds": ${total_duration},
  "container_name": "${CONTAINER_NAME}",
  "image_tag": "${IMAGE_TAG}",
  "phases": {
EOF

    local first=true
    for phase in "${!PHASE_DURATIONS[@]}"; do
        if [[ "$first" == "false" ]]; then
            echo "," >> "${LOG_DIR}/docker-test-${TIMESTAMP}-report.json"
        fi
        echo -n "    \"${phase}\": {\"duration\": ${PHASE_DURATIONS[$phase]}, \"status\": \"${PHASE_STATUS[$phase]:-UNKNOWN}\"}" >> "${LOG_DIR}/docker-test-${TIMESTAMP}-report.json"
        first=false
    done

    cat >> "${LOG_DIR}/docker-test-${TIMESTAMP}-report.json" <<EOF

  },
  "issues": {
    "errors": ${ERROR_COUNT},
    "warnings": ${WARNING_COUNT},
    "info": ${INFO_COUNT}
  },
  "logs": {
    "main": "${LOG_FILE}",
    "build": "${BUILD_LOG}",
    "provision": "${PROVISION_LOG}"
  }
}
EOF

    log_info "JSON report saved to: ${LOG_DIR}/docker-test-${TIMESTAMP}-report.json"
}

# ============================================
# Cleanup & Maintenance
# ============================================
cleanup_old_images() {
    log_debug "Cleaning up old test images..."
    
    local images
    images=$(docker images "${IMAGE_NAME}" --format "{{.Tag}} {{.CreatedAt}}" | grep "^test-" | sort -k2 -r)
    
    local count=0
    while IFS= read -r tag created; do
        ((count++))
        if [[ $count -gt $MAX_IMAGES_TO_KEEP ]]; then
            log_debug "Removing old image: ${IMAGE_NAME}:${tag}"
            docker rmi "${IMAGE_NAME}:${tag}" >/dev/null 2>&1 || true
        fi
    done <<< "$images"
}

cleanup_on_exit() {
    local exit_code=$?
    
    # Remove container if not keeping
    if [[ "${KEEP_CONTAINER}" == "false" ]] && docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_debug "Removing container: ${CONTAINER_NAME}"
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
    
    # Cleanup old images
    cleanup_old_images
    
    # Release lock
    release_lock
    
    exit $exit_code
}

# ============================================
# Help & Usage
# ============================================
show_help() {
    cat <<'EOF'
docker-provision-test.sh - Automated Docker testing for VPS provisioning tool

USAGE:
    ./bin/docker-provision-test.sh [OPTIONS]

OPTIONS:
    --keep-container    Preserve container after execution for debugging
    --use-cache         Use Docker cache for faster builds (default: no-cache)
    --log-file PATH     Custom log file location
    --quiet             Minimal console output, full file logging
    --json-output       Output results in JSON format for CI/CD
    --help              Display this help message

EXAMPLES:
    # Default usage - full automated workflow
    ./bin/docker-provision-test.sh

    # Keep container for debugging
    ./bin/docker-provision-test.sh --keep-container

    # Use cache for faster iteration
    ./bin/docker-provision-test.sh --use-cache

    # CI/CD integration
    ./bin/docker-provision-test.sh --quiet --json-output

EXIT CODES:
    0 - Success
    1 - Docker daemon not running
    2 - Image build failure
    3 - Container execution failure
    4 - Provisioning script failure
    5 - Insufficient disk space

LOGS:
    logs/docker-test-TIMESTAMP.log          Main execution log
    logs/docker-test-TIMESTAMP-build.log    Docker build output
    logs/docker-test-TIMESTAMP-provision.log Provisioning output

EOF
}

# ============================================
# Main Execution
# ============================================
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-container)
                KEEP_CONTAINER=true
                shift
                ;;
            --use-cache)
                USE_CACHE=true
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
                BUILD_LOG="${LOG_FILE%.log}-build.log"
                PROVISION_LOG="${LOG_FILE%.log}-provision.log"
                shift 2
                ;;
            --quiet)
                QUIET_MODE=true
                shift
                ;;
            --json-output)
                JSON_OUTPUT=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Setup
    trap cleanup_on_exit EXIT INT TERM HUP QUIT
    acquire_lock
    print_header
    check_prerequisites
    
    # Execute phases
    echo "[PHASE 1/4] Docker Cleanup"
    cleanup_docker
    
    echo "[PHASE 2/4] Fresh Image Build"
    build_fresh_image
    
    echo "[PHASE 3/4] Provisioning Execution"
    run_provisioning
    
    echo "[PHASE 4/4] Results Summary"
    generate_report
    
    log_info "Script completed successfully"
}

# Run main function
main "$@"
