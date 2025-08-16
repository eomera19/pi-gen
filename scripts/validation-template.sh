#!/bin/bash
set -Eeuo pipefail

# This script expects the validation framework to be already sourced
# by the main validate-system.sh script

# --- Your validation functions ---
validate_something() {
    log_info "Validating something..."
    
    # Use the shared utility functions:
    check_file_exists "/path/to/file" "Description of file"
    check_directory_exists "/path/to/dir" "Description of directory"
    check_command_available "command_name" "Description of command"
    check_service_status "service_name" "active"  # or "enabled", "running"
    check_grep_pattern "/path/to/file" "pattern" "Description of pattern"
    
    # Or use the generic run_check for custom validations:
    run_check "Custom check name" "your_command_here" 0
}

validate_another_thing() {
    log_info "Validating another thing..."
    
    # Add your custom validation logic here
    # Remember to update counters using the shared functions
}

# --- Main validation execution ---
main() {
    echo "🔍 StageX: Your Step Validation"
    echo "================================"
    echo ""
    
    # Initialize validation counters (REQUIRED)
    init_validation
    
    # Run your validations
    validate_something
    validate_another_thing
    
    # Print summary and return exit code (REQUIRED)
    print_validation_summary "your step name"
}

# --- Script execution ---
main "$@"
