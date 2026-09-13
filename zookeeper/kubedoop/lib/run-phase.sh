#!/bin/bash
# /kubedoop/lib/run-phase.sh -- Script auto-discovery and execution
#
# Discovers and executes .sh scripts in a directory, sorted by filename.
# Used for pre-script and post-script lifecycle phases.

# Discover executable .sh scripts in a directory, sorted by filename.
#
# Arguments:
#   $1 - Directory path to scan
#
# Output:
#   stdout - Null-delimited sorted list of matching script paths, empty if none found
#
# Returns:
#   0 - Discovery succeeded, or the directory does not exist
#   1 - find or sort failed
discover_scripts() {
    local phase_dir="$1"

    if [[ ! -d "$phase_dir" ]]; then
        return 0
    fi

    # Only match .sh files that have any execute bit set (owner, group, or other).
    # Note: -executable is GNU find specific (not BSD/macOS). Acceptable here since
    # the target environment is ubi9-minimal (Linux, GNU findutils).
    # With ConfigMap defaultMode: 0755, this correctly matches all executable scripts.
    # SECURITY: Only execute scripts owned by root (uid 0) to prevent injection
    # from non-root writable volumes (emptyDir, PVC, hostPath).
    find "$phase_dir" -maxdepth 1 -type f -name '*.sh' -executable \
        -uid 0 -print0 \
        | sort -z
    local -a pipeline_status=("${PIPESTATUS[@]}")
    if [[ "${pipeline_status[0]}" -ne 0 || "${pipeline_status[1]}" -ne 0 ]]; then
        return 1
    fi

    return 0
}

# Execute all discovered scripts in a phase directory sequentially.
# Script execution order is determined by filename sort order.
# First script failure aborts the phase immediately.
#
# Arguments:
#   $1 - Phase name (for logging, e.g., "pre-script", "post-script")
#   $2 - Directory containing executable .sh scripts
#
# Returns:
#   0 - All scripts succeeded, or no scripts found
#   1 - A script failed, or script discovery failed
run_phase() {
    local phase_name="$1"
    local phase_dir="$2"

    if [[ ! -d "$phase_dir" ]]; then
        return 0
    fi

    local count=0
    local found_any=false
    local script_list

    # Process substitution hides the producer's exit status from the while loop.
    # Materialize the null-delimited list first so discovery errors (permission
    # denied, I/O errors, etc.) fail the phase instead of looking like an empty
    # directory. KUBEDOOP_RUN_DIR is the writable runtime area in the image.
    if ! script_list=$(mktemp "${KUBEDOOP_RUN_DIR:-/tmp}/.phase-scripts.XXXXXX"); then
        log_error "Phase '$phase_name': failed to create script discovery file"
        return 1
    fi

    if ! discover_scripts "$phase_dir" > "$script_list"; then
        log_error "Phase '$phase_name': failed to discover scripts in $phase_dir"
        rm -f "$script_list"
        return 1
    fi

    local script_list_fd
    if ! exec {script_list_fd}<"$script_list"; then
        log_error "Phase '$phase_name': failed to read discovered script list"
        rm -f "$script_list"
        return 1
    fi
    rm -f "$script_list"

    while IFS= read -r -d '' script; do
        found_any=true
        local name
        name=$(basename "$script")
        log_info "Phase '$phase_name': running $name"
        count=$((count + 1))

        local rc=0
        "$script" || rc=$?
        if [[ $rc -ne 0 ]]; then
            log_error "Phase '$phase_name': $name failed with exit code $rc"
            exec {script_list_fd}<&-
            return 1
        fi
    done <&"$script_list_fd"

    exec {script_list_fd}<&-

    if [[ "$found_any" == false ]]; then
        log_info "Phase '$phase_name': no scripts found in $phase_dir"
        return 0
    fi

    log_info "Phase '$phase_name': completed ($count scripts)"
    return 0
}
