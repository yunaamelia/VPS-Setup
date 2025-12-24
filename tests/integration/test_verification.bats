#!/usr/bin/env bats
# Integration tests for verification module

load '../test_helper'

setup() {
  # Define Project Root
  export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
  export LOG_FILE="$(mktemp)"
  export CHECKPOINT_DIR="${BATS_TEST_TMPDIR}/checkpoints"
  mkdir -p "$CHECKPOINT_DIR"

  # Source the verification module
  source "${PROJECT_ROOT}/lib/modules/verification.sh"
}

teardown() {
  rm -f "$LOG_FILE"
  rm -rf "$CHECKPOINT_DIR"
}

@test "verification_check_services: validates required services" {
  function systemctl() { 
      return 0 
  }
  export -f systemctl
  
  run verification_check_services
  [ "$status" -eq 0 ]
}

@test "verification_check_ides: detects installed IDEs" {
  function command() { return 0; }
  export -f command
  check_executable() { return 0; }
  export -f check_executable
  
  run verification_check_ides
  [ "$status" -eq 0 ]
}

@test "verification_check_ports: validates network ports" {
  function netstat() { echo "tcp 0 0 0.0.0.0:22 LISTEN"; echo "tcp 0 0 0.0.0.0:3389 LISTEN"; }
  export -f netstat
  
  run verification_check_ports
  [ "$status" -eq 0 ]
}

@test "verification_check_permissions: validates file permissions" {
  check_file() { return 0; }
  export -f check_file
  check_dir() { return 0; }
  export -f check_dir
  
  function stat() {
    if [[ "$*" =~ "%a" ]]; then
        echo "600"
    else
        echo "devuser"
    fi
  }
  export -f stat
  
  run verification_check_permissions
  [ "$status" -eq 0 ]
}

@test "verification_check_configurations: validates config files" {
  check_file() { return 0; }
  export -f check_file
  check_dir() { return 0; }
  export -f check_dir
  
  function grep() { return 0; }
  export -f grep
  
  run verification_check_configurations
  [ "$status" -eq 0 ]
}

@test "verification_execute: runs all verification checks" {
  # Mock all dependencies
  function systemctl() { return 0; }
  export -f systemctl
  function command() { return 0; }
  export -f command
  check_executable() { return 0; }
  export -f check_executable
  function netstat() { echo "tcp 0 0 0.0.0.0:22 LISTEN"; echo "tcp 0 0 0.0.0.0:3389 LISTEN"; }
  export -f netstat
  check_file() { return 0; }
  export -f check_file
  check_dir() { return 0; }
  export -f check_dir
  function stat() {
    if [[ "$*" =~ "%a" ]]; then echo "600"; else echo "devuser"; fi
  }
  export -f stat
  function grep() { return 0; }
  export -f grep
  
  # Mock checkpoint (if needed, but script usually handles it)
  # But verification_execute calls checkpoint_exists/start/complete
  # We should mock them if not already mocked in test_helper or setup
  
  # Currently setup imports verification.sh which imports checkpoint.sh
  # We can override checkpoint functions
  checkpoint_exists() { return 1; } # Not completed yet
  export -f checkpoint_exists
  checkpoint_start() { return 0; }
  export -f checkpoint_start
  checkpoint_complete() { return 0; }
  export -f checkpoint_complete
  
  run verification_execute
  [ "$status" -eq 0 ]
}

@test "verification module exports required functions" {
  # Check that functions are exported
  declare -F verification_check_services
  declare -F verification_check_ides
  declare -F verification_check_ports
  declare -F verification_check_permissions
  declare -F verification_check_configurations
  declare -F verification_execute
}
