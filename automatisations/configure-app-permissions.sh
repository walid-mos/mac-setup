#!/usr/bin/env bash

# ============================================================================
# Application Permissions Configuration
# Guide users to grant necessary macOS permissions to applications
# ============================================================================

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/config.sh" ]]; then
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/logger.sh"
  source "$PROJECT_ROOT/lib/helpers.sh"
fi

# ============================================================================
# Permission Check Functions
# ============================================================================

check_screen_recording_access() {
  # Test if screen recording is available by attempting a capture
  local test_file="/tmp/test_capture_$$_.png"

  if screencapture -x "$test_file" 2>/dev/null; then
    rm -f "$test_file" 2>/dev/null || true
    return 0
  else
    rm -f "$test_file" 2>/dev/null || true
    return 1
  fi
}

# ============================================================================
# Configuration Functions
# ============================================================================

configure_terminal_permissions() {
  log_step "Checking Terminal/Ghostty Full Disk Access..."

  # Check if plutil can access protected files
  if plutil -lint /Library/Preferences/com.apple.TimeMachine.plist >/dev/null 2>&1; then
    log_success "Terminal has Full Disk Access"
    return 0
  fi

  log_warning "Terminal does NOT have Full Disk Access"
  log_info ""
  log_info "Full Disk Access allows your terminal to:"
  log_info "  • Access system configuration files"
  log_info "  • Modify application preferences"
  log_info "  • Run system maintenance tasks"
  log_info ""
  log_info "To grant Full Disk Access:"
  log_info "  1. Open System Settings > Privacy & Security > Full Disk Access"
  log_info "  2. Click the lock icon and authenticate"
  log_info "  3. Click '+' and add your terminal app:"
  log_info "     - Terminal.app (default macOS terminal)"
  log_info "     - Ghostty.app (if installed)"
  log_info "     - iTerm.app (if installed)"
  log_info "  4. IMPORTANT: Quit and restart your terminal completely (Cmd+Q)"
  log_info ""

  if ask_yes_no "Open Full Disk Access settings now?" "y"; then
    log_info "Opening System Settings..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    log_info ""
    log_info "After granting access:"
    log_info "  1. Quit this terminal (Cmd+Q)"
    log_info "  2. Reopen the terminal"
    log_info "  3. Verify access with: plutil -lint /Library/Preferences/com.apple.TimeMachine.plist"
  fi
}

configure_discord_permissions() {
  log_step "Checking Discord Screen Recording permissions..."

  # Discord needs Screen Recording permission for screen sharing
  log_info ""
  log_info "Discord requires Screen Recording permission to:"
  log_info "  • Share your screen in calls"
  log_info "  • Stream gameplay or applications"
  log_info "  • Use Go Live feature"
  log_info ""
  log_info "To grant Screen Recording permission to Discord:"
  log_info "  1. Open System Settings > Privacy & Security > Screen Recording"
  log_info "  2. Enable the toggle for Discord"
  log_info "  3. Restart Discord for changes to take effect"
  log_info ""
  log_info "Note: If Discord is not in the list yet, try to share your screen"
  log_info "once - macOS will then prompt you to grant permission."
  log_info ""

  if ask_yes_no "Open Screen Recording settings now?" "y"; then
    log_info "Opening System Settings..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  fi
}

configure_accessibility_permissions() {
  log_step "Information about Accessibility permissions..."

  log_info ""
  log_info "Some applications may require Accessibility permission for:"
  log_info "  • Keyboard shortcuts and automation"
  log_info "  • Window management tools"
  log_info "  • Clipboard managers"
  log_info "  • Screen recording software"
  log_info ""
  log_info "If an app requests this permission:"
  log_info "  1. System Settings > Privacy & Security > Accessibility"
  log_info "  2. Enable the toggle for the requesting application"
  log_info "  3. Restart the application"
  log_info ""

  if ask_yes_no "Open Accessibility settings to review permissions?" "n"; then
    log_info "Opening System Settings..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  fi
}

# ============================================================================
# Main Automation Function
# ============================================================================

automation_configure_app_permissions() {
  log_section "🔒 Configuring Application Permissions"

  log_info "This automation will guide you through granting necessary macOS"
  log_info "permissions to your applications. These permissions CANNOT be"
  log_info "automated and require manual approval for security reasons."
  log_info ""

  # Terminal/Ghostty Full Disk Access
  configure_terminal_permissions

  log_info ""

  # Discord Screen Recording
  if ask_yes_no "Do you want to configure Discord Screen Recording permissions?" "y"; then
    configure_discord_permissions
  fi

  log_info ""

  # Accessibility (informational)
  if ask_yes_no "Do you want to review Accessibility permissions?" "n"; then
    configure_accessibility_permissions
  fi

  log_info ""
  log_success "Application permissions configuration completed"
  log_info ""
  log_info "Summary of permission locations:"
  log_info "  • Full Disk Access: System Settings > Privacy & Security > Full Disk Access"
  log_info "  • Screen Recording: System Settings > Privacy & Security > Screen Recording"
  log_info "  • Accessibility: System Settings > Privacy & Security > Accessibility"
  log_info ""
  log_info "Remember to quit and restart applications after granting permissions!"

  return 0
}

# Run automation if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_configure_app_permissions
fi
