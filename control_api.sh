#!/bin/bash
# control_api.sh - Script to manage services via supervisorctl

set -eo pipefail # Exit on error, treat unset variables as an error, and propagate pipeline errors

SUPERVISORCTL_CMD="supervisorctl" # Assumes supervisorctl is in PATH

# --- Helper Functions ---
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

show_usage() {
    echo "Usage: $0 <start|stop|restart|status|stopall> [program_name|all_managed]"
    echo "  Program names (from supervisord.conf): sshd, java_command_server, mineru_api, docling_serve_api"
    echo "  Special targets:"
    echo "    all_managed:    Controls all programs defined in this script's list (see notes below)"
    echo "    stopall:        Stops both mineru_api and docling_serve_api. Does not require a program_name."
    echo "  Notes:"
    echo "    - When starting/restarting 'mineru_api' or 'docling_serve_api', this script will attempt to stop the other."
    echo "    - 'start all_managed' or 'restart all_managed' will skip mineru_api and docling_serve_api due to mutual exclusivity."
    echo "  Examples:"
    echo "    $0 start mineru_api"
    echo "    $0 status all_managed"
    echo "    $0 restart docling_serve_api"
    echo "    $0 stopall"
}

# --- Main Logic ---
ACTION=$1
TARGET_SERVICE=$2 # This will be empty for 'stopall'

if [[ -z "$ACTION" ]]; then
    log_error "Missing action argument."
    show_usage
    exit 1
fi

VALID_ACTIONS=("start" "stop" "restart" "status" "stopall")
if ! [[ " ${VALID_ACTIONS[@]} " =~ " ${ACTION} " ]]; then
    log_error "Invalid action: '$ACTION'. Must be one of: ${VALID_ACTIONS[*]}"
    show_usage
    exit 1
fi

# For actions other than 'stopall', TARGET_SERVICE is required
if [[ "$ACTION" != "stopall" ]] && [[ -z "$TARGET_SERVICE" ]]; then
    log_error "Missing target_service argument for action '$ACTION'."
    show_usage
    exit 1
fi


# Define service groups and individual known services
PYTHON_APIS=("mineru_api" "docling_serve_api") # These are mutually exclusive for start/restart
KNOWN_PROGRAMS=("sshd" "java_command_server" "mineru_api" "docling_serve_api") # Update if more are added

execute_supervisor_action() {
    local current_action=$1
    local service_to_control=$2
    local other_api=""

    # Mutual exclusivity logic for Python APIs on start/restart
    if [[ "$current_action" == "start" || "$current_action" == "restart" ]]; then
        if [[ "$service_to_control" == "mineru_api" ]]; then
            other_api="docling_serve_api"
        elif [[ "$service_to_control" == "docling_serve_api" ]]; then
            other_api="mineru_api"
        fi

        if [[ -n "$other_api" ]]; then
            log_info "Ensuring $other_api is stopped before starting/restarting $service_to_control..."
            # Check if the other API is running before attempting to stop it
            if sudo "$SUPERVISORCTL_CMD" status "$other_api" 2>/dev/null | grep -q "RUNNING"; then
                if ! sudo "$SUPERVISORCTL_CMD" stop "$other_api"; then
                    log_error "Failed to stop $other_api. Please check its status manually."
                    # Depending on strictness, you might want to exit here: return 1
                else
                    log_info "$other_api stopped."
                    sleep 1 # Give a moment for the stop to complete
                fi
            else
                log_info "$other_api was not running or status could not be determined."
            fi
        fi
    fi

    # Execute the requested action
    log_info "Executing: sudo $SUPERVISORCTL_CMD $current_action $service_to_control"
    if [[ "$current_action" == "status" ]]; then
        if sudo "$SUPERVISORCTL_CMD" "$current_action" "$service_to_control"; then
            log_info "Status displayed for $service_to_control."
        else
            log_error "Failed to get status for $service_to_control."
            return 1 # Propagate failure
        fi
    else
        # For start, stop, restart
        if sudo "$SUPERVISORCTL_CMD" "$current_action" "$service_to_control"; then
            log_info "Successfully executed: $current_action $service_to_control"
            sleep 1 # Give a moment for the action to take effect before checking status
            log_info "Current status for $service_to_control:"
            sudo "$SUPERVISORCTL_CMD" status "$service_to_control" || log_error "Could not retrieve status for $service_to_control after action."
        else
            log_error "Failed to execute: $current_action $service_to_control"
            # Attempt to show status anyway to see the current state
            sudo "$SUPERVISORCTL_CMD" status "$service_to_control" || true
            return 1 # Propagate failure
        fi
    fi
    return 0 # Success
}

# --- Action Handling ---
case "$ACTION" in
    start|stop|restart|status)
        # --- Target Service Handling for standard actions ---
        case "$TARGET_SERVICE" in
            all_managed)
                log_info "Performing '$ACTION' on all managed services: ${KNOWN_PROGRAMS[*]}"
                ALL_SUCCESS=true
                for managed_service in "${KNOWN_PROGRAMS[@]}"; do
                    # Special handling for 'start' or 'restart' with 'all_managed'
                    # to prevent starting both Python APIs due to mutual exclusivity.
                    if [[ "$ACTION" == "start" || "$ACTION" == "restart" ]]; then
                         if [[ "$managed_service" == "mineru_api" || "$managed_service" == "docling_serve_api" ]]; then
                            log_info "Skipping $managed_service for '$ACTION all_managed' due to mutual exclusivity. Manage these APIs individually for start/restart."
                            continue
                         fi
                    fi

                    if ! execute_supervisor_action "$ACTION" "$managed_service"; then
                        ALL_SUCCESS=false
                        # Optionally, break on first failure or continue processing others
                        # break
                    fi
                done
                if ! $ALL_SUCCESS; then
                    log_error "One or more operations failed for '$ACTION all_managed'."
                    exit 1
                fi
                ;;
            *)
                # Check if it's one of the known individual programs
                IS_KNOWN_PROGRAM=false
                for prog in "${KNOWN_PROGRAMS[@]}"; do
                    if [[ "$TARGET_SERVICE" == "$prog" ]]; then
                        IS_KNOWN_PROGRAM=true
                        break
                    fi
                done

                if $IS_KNOWN_PROGRAM; then
                    if ! execute_supervisor_action "$ACTION" "$TARGET_SERVICE"; then
                        exit 1 # Exit if the single operation failed
                    fi
                else
                    log_error "Invalid service target: '$TARGET_SERVICE' for action '$ACTION'."
                    show_usage
                    exit 1
                fi
                ;;
        esac
        ;;
    stopall)
        log_info "Performing 'stopall' on mineru_api and docling_serve_api"
        ALL_SUCCESS=true
        SERVICES_TO_STOP=("mineru_api" "docling_serve_api") # Explicitly define targets for stopall
        for service_to_stop in "${SERVICES_TO_STOP[@]}"; do
            if ! execute_supervisor_action "stop" "$service_to_stop"; then
                ALL_SUCCESS=false
                # Optionally, break on first failure or continue processing others
            fi
        done
        if ! $ALL_SUCCESS; then
            log_error "One or more operations failed for 'stopall'."
            exit 1
        fi
        ;;
    *)
        # This case should ideally not be reached due to VALID_ACTIONS check
        log_error "Internal error: Unhandled action '$ACTION'."
        show_usage
        exit 1
        ;;
esac

log_info "Operation complete for action '$ACTION' on target '${TARGET_SERVICE:-python_apis_for_stopall}'."
