#!/bin/bash
# Shared validation framework for Eomera Pi validation scripts
# Source this file at the top of your validation scripts to get:
# - Colors and formatting
# - Logging functions
# - Validation framework
# - Common utilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

# --- Validation framework ---
# Debug mode (set to true to show all command output)
DEBUG_MODE="${DEBUG_MODE-false}"

export DEBUG_MODE

# Initialize validation counters (call this at the start of your main function)
init_validation() {
  TOTAL_CHECKS=0
  PASSED_CHECKS=0
  FAILED_CHECKS=0
  
  # Check for debug mode from environment or command line
  if [ "${1:-}" = "--debug" ] || [ "$DEBUG_MODE" = "true" ]; then
    DEBUG_MODE=true
    log_info "Debug mode enabled - showing all command output"
  fi
}

# Run a validation check and update counters
run_check() {
  local check_name="$1"
  local check_command="$2"
  local expected_result="${3:-0}"
  local show_output="${4:-$DEBUG_MODE}"
  
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  echo "🔍 Checking: $check_name"
  
  # Capture both output and exit code
  local output
  local exit_code
  
  if [ "$show_output" = "true" ]; then
    # Show output for debugging
    echo "  Command: $check_command"
    eval "$check_command"
    exit_code=$?
  else
    # Capture output but don't show it unless there's an error
    output=$(eval "$check_command" 2>&1)
    exit_code=$?
  fi
  
  if [ "$exit_code" -eq "$expected_result" ]; then
    log_success "PASS: $check_name"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    return 0
  else
    log_error "FAIL: $check_name (exit code $exit_code, expected $expected_result)"
    if [ -n "$output" ] && [ "$show_output" != "true" ]; then
      echo "  Output: $output"
    fi
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    return 1
  fi
}

# Print validation summary (call this at the end of your main function)
print_validation_summary() {
  local stage_name="$1"
  
  echo ""
  echo "📊 Validation Results Summary"
  echo "============================="
  echo "Total checks: $TOTAL_CHECKS"
  echo "Passed: $PASSED_CHECKS"
  echo "Failed: $FAILED_CHECKS"
  
  local success_rate
  if [ $TOTAL_CHECKS -gt 0 ]; then
    success_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo "Success rate: ${success_rate}%"
  fi
  
  echo ""
  if [ $FAILED_CHECKS -eq 0 ]; then
    log_success "🎉 All $stage_name validations passed!"
  else
    log_error "⚠️  Some $stage_name validations failed."
  fi
  
  # Return exit code for main validator
  [ $FAILED_CHECKS -eq 0 ]
}

# Common validation utilities
check_file_exists() {
  local file_path="$1"
  local description="$2"
  
  if [ -f "$file_path" ]; then
    log_success "$description exists: $file_path"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    log_error "$description missing: $file_path"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

check_directory_exists() {
  local dir_path="$1"
  local description="$2"
  
  if [ -d "$dir_path" ]; then
    log_success "$description exists: $dir_path"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    log_error "$description missing: $dir_path"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

check_command_available() {
  local command_name="$1"
  local description="$2"
  local show_output="${3:-$DEBUG_MODE}"
  
  echo "🔍 Checking: $description available"
  
  if [ "$show_output" = "true" ]; then
    echo "  Command: command -v $command_name"
    command -v "$command_name"
    local exit_code=$?
  else
    local output=$(command -v "$command_name" 2>&1)
    local exit_code=$?
  fi
  
  if [ $exit_code -eq 0 ]; then
    log_success "$description available: $command_name"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    log_error "$description not available: $command_name"
    if [ -n "$output" ] && [ "$show_output" != "true" ]; then
      echo "  Output: $output"
    fi
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

check_service_status() {
  local service_name="$1"
  local expected_status="${2:-active}"
  local show_output="${3:-$DEBUG_MODE}"
  
  echo "🔍 Checking: Service $service_name is $expected_status"
  
  if [ "$show_output" = "true" ]; then
    echo "  Command: systemctl is-$expected_status $service_name"
    systemctl is-"$expected_status" "$service_name"
    local exit_code=$?
  else
    local output=$(systemctl is-"$expected_status" "$service_name" 2>&1)
    local exit_code=$?
  fi
  
  if [ $exit_code -eq 0 ]; then
    log_success "Service $service_name is $expected_status"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    log_error "Service $service_name is not $expected_status"
    if [ -n "$output" ] && [ "$show_output" != "true" ]; then
      echo "  Output: $output"
    fi
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

check_grep_pattern() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"
  local show_output="${4:-$DEBUG_MODE}"
  
  echo "🔍 Checking: $description in $file_path"
  
  if [ ! -f "$file_path" ]; then
    log_error "File not found: $file_path"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    return 1
  fi
  
  if [ "$show_output" = "true" ]; then
    echo "  Command: grep '$pattern' $file_path"
    grep "$pattern" "$file_path"
    local exit_code=$?
  else
    local output=$(grep "$pattern" "$file_path" 2>&1)
    local exit_code=$?
  fi
  
  if [ $exit_code -eq 0 ]; then
    log_success "$description found in $file_path"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    log_error "$description not found in $file_path"
    if [ -n "$output" ] && [ "$show_output" != "true" ]; then
      echo "  Pattern: $pattern"
    fi
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

# Export functions so they can be used by sourcing scripts
export -f log_info log_success log_warning log_error
export -f init_validation run_check print_validation_summary
export -f check_file_exists check_directory_exists check_command_available
export -f check_service_status check_grep_pattern
