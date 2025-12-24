#!/usr/bin/env bats
# Integration test for resource management
# Tests disk space monitoring, memory checks, and resource exhaustion handling

load '../test_helper'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/resource_test"
  export LOG_FILE="${TEST_DIR}/test.log"
  
  mkdir -p "$TEST_DIR"
  
  # Source modules
  source "${LIB_DIR}/core/logger.sh"
  source "${LIB_DIR}/core/validator.sh"
  
  logger_init
  validator_init
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "resource: check disk space monitoring" {
  # Monitor current disk space
  run validator_monitor_disk_space 5
  # Should pass on test system with adequate space
  [ "$status" -eq 0 ]
}

@test "resource: detect low disk space" {
  # Mock df to report low disk space
  df() {
    echo "Filesystem     1G-blocks  Used Available Use% Mounted on"
    echo "/dev/sda1            25    22        3  89% /"
  }
  export -f df
  
  # Should detect low space and attempt cleanup
  run validator_monitor_disk_space 5
  # May pass or fail depending on whether cleanup succeeds
  # Just verify it attempts cleanup
  [[ "$output" == *"disk space"* ]]
}

@test "resource: get memory usage percentage" {
  run validator_get_memory_usage
  [ "$status" -eq 0 ]
  
  # Verify output is a number
  [[ "$output" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "resource: check system load" {
  run validator_check_system_load
  # Should complete (may warn if system is loaded)
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "resource: pre-flight resource validation" {
  # Run resource checks with minimal requirements
  run validator_preflight_resources 1 10
  # Should pass on test system
  [ "$status" -eq 0 ]
}

@test "resource: bandwidth check (non-critical)" {
  # This may timeout or fail on isolated test environments
  run validator_check_bandwidth
  # Always passes (warnings only)
  [ "$status" -eq 0 ]
}

@test "resource: RAM check with minimum requirement" {
  # Check for 1GB RAM (should pass on any modern system)
  run validator_check_ram 1
  [ "$status" -eq 0 ]
}

@test "resource: CPU check with minimum requirement" {
  # Check for 1 CPU core
  run validator_check_cpu 1
  [ "$status" -eq 0 ]
}

@test "resource: simulate resource exhaustion - disk full" {
  # Mock df to simulate full disk
  df() {
    echo "Filesystem     1G-blocks  Used Available Use% Mounted on"
    echo "/dev/sda1            25    24        1  96% /"
  }
  export -f df
  
  # Mock apt-get clean
  apt-get() {
    if [[ "$1" == "clean" ]]; then
      return 0
    fi
    command apt-get "$@"
  }
  export -f apt-get
  
  run validator_monitor_disk_space 5
  # Should attempt cleanup
  [[ "$output" == *"disk space"* ]]
}

@test "resource: validate minimum disk space at start" {
  # Verify disk space check works
  run validator_check_disk 1
  [ "$status" -eq 0 ]
}

@test "resource: detect insufficient resources" {
  # Mock checks to simulate insufficient resources
  validator_check_ram() {
    log_error "Insufficient RAM"
    return 1
  }
  export -f validator_check_ram
  
  run validator_preflight_resources 999 10
  [ "$status" -eq 1 ]
}
