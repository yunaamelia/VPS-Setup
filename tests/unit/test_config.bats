#!/usr/bin/env bats
# test_config.bats - Unit tests for config.sh
# Tests configuration loading, validation, and access functions

load '../test_helper.bash'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/config_test_$$"
  mkdir -p "$TEST_DIR"
  
  export PROJECT_CONFIG="${TEST_DIR}/project.conf"
  export SYSTEM_CONFIG="${TEST_DIR}/system.conf"
  export USER_CONFIG="${TEST_DIR}/user.conf"
  export LOG_DIR="${TEST_DIR}/logs"
  export LOG_FILE="${LOG_DIR}/test.log"
  export LOG_LEVEL="ERROR"
  export ENABLE_COLORS="false"
  
  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
  source "${PROJECT_ROOT}/lib/core/config.sh" 2>/dev/null || true
  
  # Create test config files
  cat > "$PROJECT_CONFIG" <<'EOF'
USERNAME="testuser"
INSTALL_VSCODE="true"
INSTALL_CURSOR="true"
RDP_PORT="3389"
EOF

  cat > "$SYSTEM_CONFIG" <<'EOF'
USERNAME="sysuser"
INSTALL_ANTIGRAVITY="true"
TIMEOUT="300"
EOF

  cat > "$USER_CONFIG" <<'EOF'
USERNAME="userconfig"
CUSTOM_SETTING="custom_value"
EOF
}

teardown() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
  unset CONFIG
  declare -gA CONFIG
}

@test "config_load_file loads valid config file" {
  config_load_file "$PROJECT_CONFIG"
  
  [[ "${CONFIG[USERNAME]}" == "testuser" ]]
  [[ "${CONFIG[INSTALL_VSCODE]}" == "true" ]]
  [[ "${CONFIG[RDP_PORT]}" == "3389" ]]
}

@test "config_load_file fails with non-existent file" {
  run config_load_file "/nonexistent/config.conf"
  
  assert_failure
}

@test "config_load_file handles quoted values" {
  echo 'QUOTED_VALUE="value with spaces"' > "${TEST_DIR}/quotes.conf"
  
  config_load_file "${TEST_DIR}/quotes.conf"
  
  [[ "${CONFIG[QUOTED_VALUE]}" == "value with spaces" ]]
}

@test "config_load_file skips comment lines" {
  cat > "${TEST_DIR}/comments.conf" <<'EOF'
# This is a comment
VALID_KEY="valid_value"
# Another comment
ANOTHER_KEY="another_value"
EOF
  
  config_load_file "${TEST_DIR}/comments.conf"
  
  [[ "${CONFIG[VALID_KEY]}" == "valid_value" ]]
  [[ "${CONFIG[ANOTHER_KEY]}" == "another_value" ]]
}

@test "config_load_file skips empty lines" {
  cat > "${TEST_DIR}/empty.conf" <<'EOF'

KEY1="value1"

KEY2="value2"

EOF
  
  config_load_file "${TEST_DIR}/empty.conf"
  
  [[ "${CONFIG[KEY1]}" == "value1" ]]
  [[ "${CONFIG[KEY2]}" == "value2" ]]
}

@test "config_init loads multiple files in priority order" {
  config_init
  
  # USER_CONFIG should override SYSTEM_CONFIG and PROJECT_CONFIG
  [[ "${CONFIG[USERNAME]}" == "userconfig" ]]
  # Settings from other files should still be present
  [[ "${CONFIG[INSTALL_VSCODE]}" == "true" ]]
  [[ "${CONFIG[CUSTOM_SETTING]}" == "custom_value" ]]
}

@test "config_get returns correct value" {
  config_load_file "$PROJECT_CONFIG"
  
  result=$(config_get "USERNAME")
  
  [[ "$result" == "testuser" ]]
}

@test "config_get returns default for missing key" {
  config_load_file "$PROJECT_CONFIG"
  
  result=$(config_get "NONEXISTENT_KEY" "default_value")
  
  [[ "$result" == "default_value" ]]
}

@test "config_get returns empty for missing key without default" {
  config_load_file "$PROJECT_CONFIG"
  
  result=$(config_get "NONEXISTENT_KEY")
  
  [[ -z "$result" ]]
}

@test "config_set updates configuration value" {
  config_load_file "$PROJECT_CONFIG"
  
  config_set "USERNAME" "newuser"
  
  [[ "${CONFIG[USERNAME]}" == "newuser" ]]
}

@test "config_set creates new key if not exists" {
  config_load_file "$PROJECT_CONFIG"
  
  config_set "NEW_KEY" "new_value"
  
  [[ "${CONFIG[NEW_KEY]}" == "new_value" ]]
}

@test "config_has_key returns 0 for existing key" {
  config_load_file "$PROJECT_CONFIG"
  
  config_has_key "USERNAME"
  
  [[ $? -eq 0 ]]
}

@test "config_has_key returns 1 for non-existing key" {
  config_load_file "$PROJECT_CONFIG"
  
  run config_has_key "NONEXISTENT"
  
  assert_failure
}

@test "config_validate_required checks required keys" {
  config_load_file "$PROJECT_CONFIG"
  
  config_validate_required "USERNAME" "INSTALL_VSCODE"
  
  [[ $? -eq 0 ]]
}

@test "config_validate_required fails for missing required key" {
  config_load_file "$PROJECT_CONFIG"
  
  run config_validate_required "USERNAME" "MISSING_KEY"
  
  assert_failure
}

@test "config_validate_boolean accepts true/false" {
  config_set "BOOL_TRUE" "true"
  config_set "BOOL_FALSE" "false"
  
  config_validate_boolean "BOOL_TRUE"
  config_validate_boolean "BOOL_FALSE"
  
  [[ $? -eq 0 ]]
}

@test "config_validate_boolean rejects invalid values" {
  config_set "INVALID_BOOL" "maybe"
  
  run config_validate_boolean "INVALID_BOOL"
  
  assert_failure
}

@test "config_validate_integer accepts valid integers" {
  config_set "INT_VALUE" "3389"
  
  config_validate_integer "INT_VALUE"
  
  [[ $? -eq 0 ]]
}

@test "config_validate_integer rejects non-integers" {
  config_set "NOT_INT" "abc123"
  
  run config_validate_integer "NOT_INT"
  
  assert_failure
}

@test "config_validate_range checks value within range" {
  config_set "PORT" "3389"
  
  config_validate_range "PORT" 1024 65535
  
  [[ $? -eq 0 ]]
}

@test "config_validate_range rejects out of range values" {
  config_set "PORT" "999"
  
  run config_validate_range "PORT" 1024 65535
  
  assert_failure
}

@test "config_export generates key=value output" {
  config_load_file "$PROJECT_CONFIG"
  
  output=$(config_export)
  
  [[ "$output" =~ USERNAME=\"testuser\" ]]
  [[ "$output" =~ INSTALL_VSCODE=\"true\" ]]
}

@test "config_export_json generates JSON output" {
  config_load_file "$PROJECT_CONFIG"
  
  json=$(config_export_json)
  
  [[ "$json" =~ "USERNAME" ]]
  [[ "$json" =~ "testuser" ]]
  [[ "$json" =~ "{" ]] && [[ "$json" =~ "}" ]]
}

@test "config_save writes configuration to file" {
  config_load_file "$PROJECT_CONFIG"
  config_set "NEW_SETTING" "new_value"
  
  output_file="${TEST_DIR}/saved.conf"
  config_save "$output_file"
  
  [[ -f "$output_file" ]]
  grep -q "NEW_SETTING" "$output_file"
}

@test "config_reload clears and reloads configuration" {
  config_load_file "$PROJECT_CONFIG"
  config_set "TEMP_KEY" "temp_value"
  
  config_reload
  
  ! config_has_key "TEMP_KEY"
}

@test "config handles values with equals signs" {
  echo 'ENCODED="key=value&foo=bar"' > "${TEST_DIR}/equals.conf"
  
  config_load_file "${TEST_DIR}/equals.conf"
  
  [[ "${CONFIG[ENCODED]}" == "key=value&foo=bar" ]]
}

@test "config handles multi-line values with backslash continuation" {
  cat > "${TEST_DIR}/multiline.conf" <<'EOF'
LONG_VALUE="line1 \
line2 \
line3"
EOF
  
  config_load_file "${TEST_DIR}/multiline.conf"
  
  [[ "${CONFIG[LONG_VALUE]}" =~ "line1" ]]
}

@test "config_list_keys returns all configuration keys" {
  config_load_file "$PROJECT_CONFIG"
  
  keys=$(config_list_keys)
  
  [[ "$keys" =~ "USERNAME" ]]
  [[ "$keys" =~ "INSTALL_VSCODE" ]]
  [[ "$keys" =~ "RDP_PORT" ]]
}

@test "config_clear removes all configuration" {
  config_load_file "$PROJECT_CONFIG"
  
  config_clear
  
  count=$(config_list_keys | wc -w)
  [[ $count -eq 0 ]]
}

@test "config handles empty values" {
  echo 'EMPTY_VALUE=""' > "${TEST_DIR}/empty_val.conf"
  
  config_load_file "${TEST_DIR}/empty_val.conf"
  
  [[ "${CONFIG[EMPTY_VALUE]}" == "" ]]
  config_has_key "EMPTY_VALUE"
}
