#!/usr/bin/env bash
#
# Module: permissions-preflight
# Description: Pre-flight permission checks and app registration
#
# This module runs AFTER applications are installed but BEFORE macos-defaults
# needs Full Disk Access. It ensures permissions are granted and apps are
# registered with LaunchServices/TCC before attempting system modifications.
#
# Key Features:
# - Checks terminal Full Disk Access (FDA)
# - Opens System Settings and pauses for user to grant FDA
# - Tests FDA in fresh subshell (avoids terminal restart)
# - Registers newly installed apps with LaunchServices
# - Launches apps briefly to trigger TCC registration

set -eo pipefail

# Check if terminal has Full Disk Access
# Returns: 0 if access granted, 1 if denied
check_full_disk_access() {
  # Test access to a protected file that requires Full Disk Access
  # The TimeMachine plist is a good test target
  if plutil -lint /Library/Preferences/com.apple.TimeMachine.plist >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Prompt user to grant FDA and wait for confirmation
# Returns: 0 to continue, 1 to abort
prompt_for_fda_and_wait() {
  log_warning "Full Disk Access is required for macOS system configuration"
  log_info ""
  log_info "This module needs to modify system preferences and protected files."
  log_info "Your terminal application needs Full Disk Access to:"
  log_info "  • Configure Finder settings (hidden files, extensions, etc.)"
  log_info "  • Modify Dock preferences (autohide, size, magnification, etc.)"
  log_info "  • Set system-wide keyboard and display settings"
  log_info "  • Delete .DS_Store files from protected directories"
  log_info ""
  log_info "How to grant Full Disk Access:"
  log_info "  1. System Settings will open automatically"
  log_info "  2. Navigate to: Privacy & Security > Full Disk Access"
  log_info "  3. Click the lock icon and authenticate"
  log_info "  4. Enable the toggle for your terminal app"
  log_info "  5. Return here and press Enter to continue"
  log_info ""

  if ask_yes_no "Open System Settings now?" "y"; then
    log_info "Opening Full Disk Access settings..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    log_info ""
    log_info "After granting Full Disk Access:"
    log_info "  1. Keep this terminal window open (DO NOT quit)"
    log_info "  2. Enable your terminal in System Settings"
    log_info "  3. Return here and press Enter"
    log_info ""

    read -r -p "Press Enter when you've granted Full Disk Access..."

    # Test FDA in fresh subshell to avoid cached TCC decisions
    log_progress "Testing Full Disk Access..."
    if bash -c "plutil -lint /Library/Preferences/com.apple.TimeMachine.plist" >/dev/null 2>&1; then
      log_success "Full Disk Access detected! Continuing..."
      return 0
    else
      log_warning "Full Disk Access not detected in test"
      log_warning "This might mean:"
      log_warning "  • You haven't granted access yet"
      log_warning "  • The setting hasn't taken effect"
      log_warning "  • A terminal restart may be needed"
      log_info ""
      log_warning "Continuing anyway - operations requiring FDA may fail gracefully"
      return 0
    fi
  else
    log_warning "Skipping Full Disk Access grant"
    log_warning "Operations requiring FDA will fail"
    return 0
  fi
}

# Register an application with LaunchServices by launching it briefly
# Args:
#   $1 - App name (e.g., "Ghostty")
#   $2 - App path (e.g., "/Applications/Ghostty.app")
register_app_with_launch_services() {
  local app_name="$1"
  local app_path="$2"

  # Check if app exists
  if [[ ! -d "$app_path" ]]; then
    log_verbose "Skipping ${app_name} registration - not found at ${app_path}"
    return 0
  fi

  log_progress "Registering ${app_name} with LaunchServices..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would register: ${app_path}"
    log_dry_run "Would launch briefly: open -a \"${app_name}\" --hide"
    return 0
  fi

  # Launch app in background (hidden) to trigger registration
  if open -a "$app_name" --hide 2>/dev/null; then
    log_verbose "Launched ${app_name} in background"

    # Wait for LaunchServices to register (2 seconds should be enough)
    sleep 2

    # Kill the app process
    if killall "$app_name" 2>/dev/null; then
      log_verbose "Terminated ${app_name} process"
    fi

    log_success "${app_name} registered with LaunchServices"
  else
    log_warning "Could not launch ${app_name} - it may not be installed yet"
    return 0  # Non-fatal - app might not be in this run's config
  fi

  return 0
}

# Main module function
module_permissions_preflight() {
  log_section "Permissions Pre-Flight Check"

  # Step 1: Check Terminal Full Disk Access
  log_subsection "Checking Terminal Full Disk Access"

  if check_full_disk_access; then
    log_success "Terminal has Full Disk Access ✓"
  else
    log_info "Full Disk Access not detected"
    prompt_for_fda_and_wait || {
      log_error "User aborted Full Disk Access grant"
      return 1
    }
  fi

  # Step 2: Register newly installed applications (read from TOML)
  log_subsection "Registering Applications with System"

  # Read apps to register from TOML config
  local apps_to_register
  apps_to_register=$(parse_toml_array "$TOML_CONFIG" "permissions.register_apps" 2>/dev/null || true)

  if [[ -z "$apps_to_register" ]]; then
    log_info "No apps configured for registration in mac-setup.toml"
    log_verbose "To add apps, edit [permissions] register_apps array in mac-setup.toml"
  else
    # Register each app
    while IFS= read -r app_name; do
      if [[ -n "$app_name" ]]; then
        local app_path="/Applications/${app_name}.app"
        register_app_with_launch_services "$app_name" "$app_path"
      fi
    done <<< "$apps_to_register"
  fi

  log_success "Permissions pre-flight check completed"
  log_info "System is ready for macOS configuration changes"

  return 0
}

# Execute module if run directly (for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Source required dependencies for standalone execution
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT_DIR="$(dirname "$SCRIPT_DIR")"

  # shellcheck source=lib/config.sh
  source "${ROOT_DIR}/lib/config.sh"
  # shellcheck source=lib/logger.sh
  source "${ROOT_DIR}/lib/logger.sh"
  # shellcheck source=lib/helpers.sh
  source "${ROOT_DIR}/lib/helpers.sh"

  module_permissions_preflight
fi
