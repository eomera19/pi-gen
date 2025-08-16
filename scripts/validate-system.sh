#!/bin/bash
set -Eeuo pipefail

# Eomera Pi System Validation Script
# This script validates the entire system configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_DIR="${HOME}/validations"
FRAMEWORK_PATH="${SCRIPT_DIR}/validation-framework.sh"

# Detect execution context: build-time vs runtime
IS_BUILD_TIME=false
if [ -n "${ROOTFS_DIR:-}" ] || [ -n "${IMG_NAME:-}" ] || [ -n "${STAGE_NAME:-}" ]; then
    IS_BUILD_TIME=true
elif [ "$1" = "--build-time" ]; then
    IS_BUILD_TIME=true
    shift
fi

# Source the validation framework to make functions available to child processes
source "$FRAMEWORK_PATH"

show_usage() {
    echo "🔍 Eomera Pi System Validation"
    echo "=============================="
    echo ""
    echo "Usage: $0 [OPTIONS] [STAGE] [STEP]"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -l, --list        List all available validations"
    echo "  -a, --all         Run all validations (default)"
    echo "  -v, --verbose     Verbose output"
    echo "  --build-time      Force build-time mode (skip *_runtime.sh)"
    echo "  --runtime         Force runtime mode (run all validations)"
    echo ""
    echo "Context Detection:"
    echo "  Build-time: Only runs validations that don't end with '_runtime.sh'"
    echo "  Runtime:    Runs all validations including runtime checks"
    echo ""
    echo "Examples:"
    echo "  $0                    # Auto-detect context and run validations"
    echo "  $0 --build-time       # Force build-time context"
    echo "  $0 --runtime          # Force runtime context"
    echo "  $0 --list             # List available validations"
    echo "  $0 stage2             # Run all stage2 validations"
    echo "  $0 stage3 50-desktop-core  # Run specific validation"
    echo ""
}

# Filter validation files based on context
should_run_validation() {
    local validation_file="$1"
    local validation_name=$(basename "${validation_file}" .sh)
    
    if [ "$IS_BUILD_TIME" = "true" ]; then
        # During build time, skip runtime validations
        if [[ "$validation_name" == *"_runtime" ]]; then
            return 1  # Don't run
        fi
    fi
    
    return 0  # Run the validation
}

list_validations() {
    echo "📋 Available Validations:"
    echo "========================"
    
    if [ "$IS_BUILD_TIME" = "true" ]; then
        echo "🏗️  Context: BUILD-TIME (excluding *_runtime.sh files)"
    else
        echo "🚀 Context: RUNTIME (including all validations)"
    fi
    echo ""
    
    if [ ! -d "${VALIDATION_DIR}" ]; then
        log_warning "No validations directory found at ${VALIDATION_DIR}"
        return 1
    fi
    
    local found_any=false
    for stage_dir in "${VALIDATION_DIR}"/stage*; do
        if [ -d "${stage_dir}" ]; then
            local stage_name=$(basename "${stage_dir}")
            echo ""
            echo "📁 ${stage_name}:"
            
            for step_dir in "${stage_dir}"/*; do
                if [ -d "${step_dir}" ]; then
                    local step_name=$(basename "${step_dir}")
                    local validation_dir="${step_dir}/validations"
                    
                    if [ -d "${validation_dir}" ]; then
                        echo "  └── ${step_name}/"
                        for validation_file in "${validation_dir}"/*.sh; do
                            if [ -f "${validation_file}" ]; then
                                local validation_name=$(basename "${validation_file}" .sh)
                                if should_run_validation "${validation_file}"; then
                                    echo "      └── ${validation_name}.sh"
                                    found_any=true
                                else
                                    echo "      └── ${validation_name}.sh (skipped - runtime only)"
                                fi
                            fi
                        done
                    fi
                fi
            done
        fi
    done
    
    if [ "$found_any" = false ]; then
        log_warning "No validation scripts found for current context"
        return 1
    fi
}

run_validation_script() {
    local script_path="$1"
    local script_name=$(basename "${script_path}")
    
    if [ ! -f "${script_path}" ] || [ ! -x "${script_path}" ]; then
        log_error "Validation script not found or not executable: ${script_path}"
        return 1
    fi
    
    log_info "Running ${script_name}..."
    echo ""
    
    # Run the script (framework functions are already exported)
    if bash "${script_path}"; then
        log_success "${script_name} completed successfully"
        return 0
    else
        log_error "${script_name} failed"
        return 1
    fi
}

run_all_validations() {
    local total_scripts=0
    local passed_scripts=0
    local failed_scripts=0
    
    echo "🚀 Running All System Validations"
    echo "=================================="
    echo ""
    
    if [ ! -d "${VALIDATION_DIR}" ]; then
        log_error "Validations directory not found: ${VALIDATION_DIR}"
        return 1
    fi
    
    for stage_dir in "${VALIDATION_DIR}"/stage*; do
        if [ -d "${stage_dir}" ]; then
            local stage_name=$(basename "${stage_dir}")
            
            for step_dir in "${stage_dir}"/*; do
                if [ -d "${step_dir}" ]; then
                    local step_name=$(basename "${step_dir}")
                    local validation_dir="${step_dir}/validations"
                    
                    if [ -d "${validation_dir}" ]; then
                        for validation_file in "${validation_dir}"/*.sh; do
                            if [ -f "${validation_file}" ] && should_run_validation "${validation_file}"; then
                                total_scripts=$((total_scripts + 1))
                                
                                if run_validation_script "${validation_file}"; then
                                    passed_scripts=$((passed_scripts + 1))
                                else
                                    failed_scripts=$((failed_scripts + 1))
                                fi
                                echo ""
                            fi
                        done
                    fi
                fi
            done
        fi
    done
    
    # Print final summary
    echo "🏁 Final Validation Summary"
    echo "=========================="
    echo "Total validation scripts: ${total_scripts}"
    echo "Passed: ${passed_scripts}"
    echo "Failed: ${failed_scripts}"
    
    if [ ${failed_scripts} -eq 0 ]; then
        log_success "🎉 All system validations passed!"
        return 0
    else
        log_error "⚠️  ${failed_scripts} validation script(s) failed"
        return 1
    fi
}

run_stage_validations() {
    local target_stage="$1"
    local target_step="${2:-}"
    
    local stage_dir="${VALIDATION_DIR}/${target_stage}"
    
    if [ ! -d "${stage_dir}" ]; then
        log_error "Stage not found: ${target_stage}"
        return 1
    fi
    
    echo "🎯 Running ${target_stage} Validations"
    echo "======================================"
    echo ""
    
    local total_scripts=0
    local passed_scripts=0
    local failed_scripts=0
    
    for step_dir in "${stage_dir}"/*; do
        if [ -d "${step_dir}" ]; then
            local step_name=$(basename "${step_dir}")
            
            # If specific step requested, skip others
            if [ -n "${target_step}" ] && [ "${step_name}" != "${target_step}" ]; then
                continue
            fi
            
            local validation_dir="${step_dir}/validations"
            
            if [ -d "${validation_dir}" ]; then
                for validation_file in "${validation_dir}"/*.sh; do
                    if [ -f "${validation_file}" ] && should_run_validation "${validation_file}"; then
                        total_scripts=$((total_scripts + 1))
                        
                        if run_validation_script "${validation_file}"; then
                            passed_scripts=$((passed_scripts + 1))
                        else
                            failed_scripts=$((failed_scripts + 1))
                        fi
                        echo ""
                    fi
                done
            fi
        fi
    done
    
    if [ ${total_scripts} -eq 0 ]; then
        log_warning "No validation scripts found for ${target_stage}${target_step:+ ${target_step}}"
        return 1
    fi
    
    # Print summary
    echo "📊 ${target_stage} Validation Summary"
    echo "=================================="
    echo "Scripts run: ${total_scripts}"
    echo "Passed: ${passed_scripts}"
    echo "Failed: ${failed_scripts}"
    
    if [ ${failed_scripts} -eq 0 ]; then
        log_success "🎉 All ${target_stage} validations passed!"
        return 0
    else
        log_error "⚠️  ${failed_scripts} validation(s) failed"
        return 1
    fi
}

main() {
    local run_all=true
    local target_stage=""
    local target_step=""
    local verbose=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--list)
                list_validations
                exit $?
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --build-time)
                IS_BUILD_TIME=true
                shift
                ;;
            --runtime)
                IS_BUILD_TIME=false
                shift
                ;;
            stage*)
                target_stage="$1"
                run_all=false
                shift
                if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                    target_step="$1"
                    shift
                fi
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check if validation framework exists
    if [ ! -f "$FRAMEWORK_PATH" ]; then
        log_error "Validation framework not found at $FRAMEWORK_PATH"
        log_info "This may indicate the validation system wasn't installed properly during build."
        exit 1
    fi
    
    # Show context information
    echo "🔍 Eomera Pi System Validation"
    echo "=============================="
    if [ "$IS_BUILD_TIME" = "true" ]; then
        echo "🏗️  Context: BUILD-TIME (excluding runtime validations)"
        echo "📋 Running: Non-runtime validations only"
    else
        echo "🚀 Context: RUNTIME (including all validations)"
        echo "📋 Running: All validations including runtime checks"
    fi
    echo ""
    
    # Run validations based on arguments
    if [ "$run_all" = true ]; then
        run_all_validations
    else
        run_stage_validations "$target_stage" "$target_step"
    fi
}

main "$@"
