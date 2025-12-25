#!/usr/bin/env bats
# test_transaction.bats - Unit tests for transaction.sh
# Tests transaction recording, parsing, and retrieval

load '../test_helper.bash'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/transaction_test_$$"
  mkdir -p "$TEST_DIR"
  
  export LOG_DIR="${TEST_DIR}/logs"
  export TRANSACTION_LOG="${LOG_DIR}/transactions.log"
  export LOG_FILE="${LOG_DIR}/test.log"
  export LOG_LEVEL="ERROR"
  export ENABLE_COLORS="false"
  
  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
  source "${PROJECT_ROOT}/lib/core/transaction.sh" 2>/dev/null || true
}

teardown() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

@test "transaction_init creates transaction log" {
  transaction_init
  
  [[ -f "$TRANSACTION_LOG" ]]
}

@test "transaction_init creates log directory if missing" {
  rm -rf "$LOG_DIR"
  
  transaction_init
  
  [[ -d "$LOG_DIR" ]]
  [[ -f "$TRANSACTION_LOG" ]]
}

@test "transaction_record writes transaction to log" {
  transaction_init
  
  transaction_record "Installed package nginx" "apt-get remove -y nginx"
  
  grep -q "Installed package nginx" "$TRANSACTION_LOG"
  grep -q "apt-get remove -y nginx" "$TRANSACTION_LOG"
}

@test "transaction_record fails with empty action" {
  transaction_init
  
  run transaction_record "" "rollback_command"
  
  assert_failure
}

@test "transaction_record fails with empty rollback command" {
  transaction_init
  
  run transaction_record "action" ""
  
  assert_failure
}

@test "transaction_record includes timestamp in ISO 8601 format" {
  transaction_init
  
  transaction_record "Test action" "rollback"
  
  line=$(tail -1 "$TRANSACTION_LOG")
  timestamp=$(echo "$line" | cut -d'|' -f1)
  
  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "transaction_get_all_reverse returns transactions in LIFO order" {
  transaction_init
  
  transaction_record "First action" "first_rollback"
  transaction_record "Second action" "second_rollback"
  transaction_record "Third action" "third_rollback"
  
  lines=$(transaction_get_all_reverse)
  first_line=$(echo "$lines" | head -1)
  
  [[ "$first_line" =~ "Third action" ]]
}

@test "transaction_count returns correct count" {
  transaction_init
  
  transaction_record "Action 1" "rollback1"
  transaction_record "Action 2" "rollback2"
  transaction_record "Action 3" "rollback3"
  
  count=$(transaction_count)
  
  [[ $count -eq 3 ]]
}

@test "transaction_count returns 0 for empty log" {
  transaction_init
  
  count=$(transaction_count)
  
  [[ $count -eq 0 ]]
}

@test "transaction_count returns 0 for missing log" {
  rm -f "$TRANSACTION_LOG"
  
  count=$(transaction_count)
  
  [[ $count -eq 0 ]]
}

@test "transaction_parse extracts fields correctly" {
  transaction_init
  
  transaction_record "Test action" "test_rollback"
  
  line=$(tail -1 "$TRANSACTION_LOG")
  result=$(transaction_parse "$line")
  
  [[ "$result" =~ "Test action" ]]
  [[ "$result" =~ "test_rollback" ]]
}

@test "transaction_get_rollback_commands extracts only rollback commands" {
  transaction_init
  
  transaction_record "Action 1" "rollback_cmd_1"
  transaction_record "Action 2" "rollback_cmd_2"
  
  commands=$(transaction_get_rollback_commands)
  
  [[ "$commands" =~ "rollback_cmd_1" ]]
  [[ "$commands" =~ "rollback_cmd_2" ]]
  ! [[ "$commands" =~ "Action 1" ]]
}

@test "transaction_get_rollback_commands returns in LIFO order" {
  transaction_init
  
  transaction_record "First" "rollback_first"
  transaction_record "Second" "rollback_second"
  transaction_record "Third" "rollback_third"
  
  commands=$(transaction_get_rollback_commands)
  first_cmd=$(echo "$commands" | head -1)
  
  [[ "$first_cmd" == "rollback_third" ]]
}

@test "transaction_clear removes all transactions" {
  transaction_init
  
  transaction_record "Action 1" "rollback1"
  transaction_record "Action 2" "rollback2"
  
  transaction_clear
  
  count=$(transaction_count)
  [[ $count -eq 0 ]]
}

@test "transaction_backup creates backup file" {
  transaction_init
  
  transaction_record "Action" "rollback"
  
  backup_file="${TEST_DIR}/backup.log"
  transaction_backup "$backup_file"
  
  [[ -f "$backup_file" ]]
  grep -q "Action" "$backup_file"
}

@test "transaction_restore restores from backup" {
  transaction_init
  
  transaction_record "Original action" "original_rollback"
  
  backup_file="${TEST_DIR}/backup.log"
  transaction_backup "$backup_file"
  
  transaction_clear
  transaction_restore "$backup_file"
  
  grep -q "Original action" "$TRANSACTION_LOG"
}

@test "transaction_get_last returns most recent transaction" {
  transaction_init
  
  transaction_record "First" "rollback1"
  transaction_record "Second" "rollback2"
  transaction_record "Last" "rollback_last"
  
  last=$(transaction_get_last)
  
  [[ "$last" =~ "Last" ]]
  [[ "$last" =~ "rollback_last" ]]
}

@test "transaction_get_first returns oldest transaction" {
  transaction_init
  
  transaction_record "First" "rollback_first"
  transaction_record "Second" "rollback2"
  transaction_record "Last" "rollback3"
  
  first=$(transaction_get_first)
  
  [[ "$first" =~ "First" ]]
  [[ "$first" =~ "rollback_first" ]]
}

@test "transaction log handles pipe characters in commands" {
  transaction_init
  
  transaction_record "Modify config" "sed 's/old|new/backup/' config.txt"
  
  grep -q "sed 's/old|new/backup/'" "$TRANSACTION_LOG"
}

@test "transaction log handles special characters" {
  transaction_init
  
  transaction_record "Test \$special @chars" "rm -f '/path/with spaces'"
  
  grep -q "Test" "$TRANSACTION_LOG"
  grep -q "rm -f" "$TRANSACTION_LOG"
}

@test "transaction_filter_by_pattern filters transactions" {
  transaction_init
  
  transaction_record "Install nginx" "remove nginx"
  transaction_record "Install apache" "remove apache"
  transaction_record "Configure firewall" "reset firewall"
  
  filtered=$(transaction_filter_by_pattern "Install")
  
  [[ "$filtered" =~ "nginx" ]]
  [[ "$filtered" =~ "apache" ]]
  ! [[ "$filtered" =~ "firewall" ]]
}

@test "transaction_export_json generates JSON array" {
  transaction_init
  
  transaction_record "Action 1" "rollback1"
  transaction_record "Action 2" "rollback2"
  
  json=$(transaction_export_json)
  
  [[ "$json" =~ "[" ]] && [[ "$json" =~ "]" ]]
  [[ "$json" =~ "Action 1" ]]
  [[ "$json" =~ "rollback1" ]]
}

@test "transaction handles concurrent writes safely" {
  transaction_init
  
  # Simulate concurrent transaction recording
  transaction_record "Concurrent 1" "rollback1" &
  transaction_record "Concurrent 2" "rollback2" &
  transaction_record "Concurrent 3" "rollback3" &
  wait
  
  count=$(transaction_count)
  [[ $count -eq 3 ]]
}

@test "transaction_get_by_index retrieves specific transaction" {
  transaction_init
  
  transaction_record "First" "rollback1"
  transaction_record "Second" "rollback2"
  transaction_record "Third" "rollback3"
  
  second=$(transaction_get_by_index 2)
  
  [[ "$second" =~ "Second" ]]
}

@test "transaction_validate checks log integrity" {
  transaction_init
  
  transaction_record "Valid action" "valid_rollback"
  
  transaction_validate
  
  [[ $? -eq 0 ]]
}

@test "transaction_validate fails for corrupted log" {
  transaction_init
  
  transaction_record "Valid" "rollback"
  echo "corrupted|line|without|proper|format|too|many|fields" >> "$TRANSACTION_LOG"
  
  run transaction_validate
  
  assert_failure
}

@test "transaction log persists across init calls" {
  transaction_init
  transaction_record "Persistent" "rollback"
  
  # Re-initialize
  transaction_init
  
  count=$(transaction_count)
  [[ $count -eq 1 ]]
}

@test "transaction_summarize provides statistics" {
  transaction_init
  
  transaction_record "Action 1" "rollback1"
  transaction_record "Action 2" "rollback2"
  transaction_record "Action 3" "rollback3"
  
  summary=$(transaction_summarize)
  
  [[ "$summary" =~ "3" ]]
  [[ "$summary" =~ "transaction" ]]
}
