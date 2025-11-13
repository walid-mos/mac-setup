#!/usr/bin/env bash

# =============================================================================
# macOS Defaults
# =============================================================================
# Configure macOS system preferences.
# =============================================================================

# -----------------------------------------------------------------------------
# Helper Functions for Permissions
# -----------------------------------------------------------------------------

# Check if the terminal has Full Disk Access
# Returns: 0 if has access, 1 if not
check_full_disk_access() {
  # Test access to a protected file that requires Full Disk Access
  # The TCC database itself is a good test target
  if plutil -lint /Library/Preferences/com.apple.TimeMachine.plist >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Prompt user to grant Full Disk Access if missing
# Returns: 0 if has access or user chose to continue anyway, 1 if should abort
prompt_for_permissions() {
  if check_full_disk_access; then
    log_success "Full Disk Access: Already granted"
    return 0
  fi

  log_warning "Full Disk Access is required for this module"
  log_info ""
  log_info "This module needs to modify system preferences and protected files."
  log_info "Your terminal application needs Full Disk Access to:"
  log_info "  • Configure Finder settings (hidden files, extensions, etc.)"
  log_info "  • Modify Dock preferences (autohide, size, etc.)"
  log_info "  • Set system-wide keyboard and display settings"
  log_info ""
  log_info "How to grant Full Disk Access:"
  log_info "  1. System Settings will open automatically"
  log_info "  2. Navigate to: Privacy & Security > Full Disk Access"
  log_info "  3. Click the lock icon and authenticate"
  log_info "  4. Enable the toggle for your terminal app"
  log_info "  5. IMPORTANT: Quit and restart your terminal application"
  log_info "  6. Re-run this script"
  log_info ""

  if ask_yes_no "Open System Settings now?" "y"; then
    log_info "Opening Full Disk Access settings..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    log_info ""
    log_warning "Please grant Full Disk Access, then:"
    log_warning "  1. Quit this terminal completely (Cmd+Q)"
    log_warning "  2. Reopen the terminal"
    log_warning "  3. Re-run the setup script"
    log_info ""
    return 1
  else
    log_info ""
    if ask_yes_no "Continue without Full Disk Access? (some settings may fail)" "n"; then
      log_warning "Continuing without Full Disk Access - some operations may fail"
      return 0
    else
      log_info "Aborting macOS defaults configuration"
      return 1
    fi
  fi
}

# -----------------------------------------------------------------------------
# Main Module Function
# -----------------------------------------------------------------------------

module_macos_defaults() {
  log_section " Configuring macOS Defaults"

  if [[ "$APPLY_MACOS_DEFAULTS" != "true" ]]; then
    log_info "Skipping macOS defaults (APPLY_MACOS_DEFAULTS=false)"
    return 0
  fi

  # Full Disk Access is handled by permissions-preflight module
  # No need to check again here - assume it's already granted

  # Dock Configuration
  log_subsection "Dock Settings"

  if [[ "$DOCK_AUTOHIDE" == "true" ]]; then
    set_macos_default "com.apple.dock" "autohide" "bool" "true"
    log_info "Dock autohide enabled"
  fi

  if [[ -n "$DOCK_SIZE" ]]; then
    set_macos_default "com.apple.dock" "tilesize" "int" "$DOCK_SIZE"
    log_info "Dock size set to: $DOCK_SIZE"
  fi

  if [[ "$DOCK_MAGNIFICATION" == "true" ]]; then
    set_macos_default "com.apple.dock" "magnification" "bool" "true"
    log_info "Dock magnification enabled"

    if [[ -n "$DOCK_MAGNIFICATION_SIZE" ]]; then
      set_macos_default "com.apple.dock" "largesize" "int" "$DOCK_MAGNIFICATION_SIZE"
      log_info "Dock magnification size set to: $DOCK_MAGNIFICATION_SIZE"
    fi
  fi

  if [[ "$DOCK_MRU_SPACES" == "false" ]]; then
    set_macos_default "com.apple.dock" "mru-spaces" "bool" "false"
    log_info "Disabled 'most recently used' spaces reordering"
  fi

  # Spaces span displays
  if [[ "$SYSTEM_SPACES_SPAN_DISPLAYS" == "true" ]]; then
    set_macos_default "com.apple.spaces" "spans-displays" "bool" "true"
    log_info "Enabled spaces spanning displays"
  fi

  # Finder Configuration
  log_subsection "Finder Settings"

  if [[ "$FINDER_SHOW_HIDDEN" == "true" ]]; then
    set_macos_default "com.apple.finder" "AppleShowAllFiles" "bool" "true"
    log_info "Show hidden files enabled"
  fi

  if [[ "$FINDER_SHOW_EXTENSIONS" == "true" ]]; then
    set_macos_default "NSGlobalDomain" "AppleShowAllExtensions" "bool" "true"
    log_info "Show file extensions enabled"
  fi

  if [[ -n "$FINDER_VIEW_STYLE" ]]; then
    set_macos_default "com.apple.finder" "FXPreferredViewStyle" "string" "$FINDER_VIEW_STYLE"
    log_info "Finder view style set to: $FINDER_VIEW_STYLE"
  fi

  # Set default folder for new Finder windows
  if [[ -n "$FINDER_NEW_WINDOW_TARGET" ]]; then
    set_macos_default "com.apple.finder" "NewWindowTarget" "string" "$FINDER_NEW_WINDOW_TARGET"
    set_macos_default "com.apple.finder" "NewWindowTargetPath" "string" "file://${HOME}/"
    log_info "Finder new window default folder set to: Home directory (~)"
  fi

  # Table view size mode (file info display)
  set_macos_default "NSGlobalDomain" "NSTableViewDefaultSizeMode" "int" "1"
  log_info "Table view default size mode set to small"

  # Hide Recent Tags from sidebar
  if [[ "$FINDER_HIDE_RECENT_TAGS" == "true" ]]; then
    set_macos_default "com.apple.finder" "ShowRecentTags" "bool" "false"
    log_info "Hide Recent Tags from Finder sidebar enabled"
  fi

  # Hide network devices from Shared section
  if [[ "$FINDER_HIDE_NETWORK_BROWSER" == "true" ]]; then
    set_macos_default "com.apple.NetworkBrowser" "BackToMyMacDiscoveryEnabled" "bool" "false"
    set_macos_default "com.apple.NetworkBrowser" "ShowConnectedEnabled" "bool" "false"
    log_info "Hide network devices from Finder sidebar enabled"
  fi

  # Note about Recents folder limitation
  log_verbose "Note: The 'Recents' folder itself cannot be hidden via Terminal on modern macOS."
  log_verbose "To hide it, manually go to Finder > Settings > Sidebar and uncheck 'Recents'."

  # Disable .DS_Store files
  if [[ "$FINDER_DISABLE_DS_STORE" == "true" ]]; then
    log_info "Cleaning existing .DS_Store files..."

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would delete all .DS_Store files"
    else
      find "$HOME" -name ".DS_Store" -exec rm {} \; 2>/dev/null || true
      log_success "Deleted .DS_Store files"
    fi
  fi

  # System Configuration
  log_subsection "System Settings"

  if [[ "$SYSTEM_DISABLE_GATEKEEPER" == "true" ]]; then
    # Check if Gatekeeper is already disabled
    local gatekeeper_status
    gatekeeper_status=$(spctl --status 2>/dev/null || echo "unknown")

    if [[ "$gatekeeper_status" == *"disabled"* ]]; then
      log_success "Gatekeeper is already disabled"
    else
      log_info "Disabling Gatekeeper to allow apps from anywhere..."
      log_warning "Note: This reduces system security. Only do this if you understand the risks."

      if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would run: sudo spctl --master-disable"
      else
        if ask_yes_no "This requires sudo. Disable Gatekeeper?" "y"; then
          log_info ""
          log_info "Attempting to disable Gatekeeper..."

          if sudo spctl --master-disable 2>&1 | grep -q "confirmation in System Settings"; then
            log_warning "⚠️  macOS Ventura+ Detected - Manual Step Required:"
            log_info ""
            log_info "  1. Open: System Settings > Privacy & Security"
            log_info "  2. Scroll down to the 'Security' section"
            log_info "  3. Look for 'Allow applications from: Anywhere'"
            log_info "  4. Click 'Allow' to confirm the change"
            log_info ""
            log_info "The command has been executed, but macOS now requires manual confirmation."
            log_info "Press any key after you've completed the manual step..."
            read -n 1 -s -r
            log_success "Gatekeeper disable confirmed"
          elif sudo spctl --master-disable 2>/dev/null; then
            log_success "Gatekeeper disabled successfully"
          else
            log_warning "Failed to disable Gatekeeper - this may require manual configuration"
          fi
        fi
      fi
    fi
  fi

  if [[ "$SYSTEM_FAST_KEY_REPEAT" == "true" ]]; then
    set_macos_default "-g" "ApplePressAndHoldEnabled" "bool" "false"
    log_info "Disabled press-and-hold for fast key repeat"
  fi

  # Computer Name Configuration
  log_subsection "Computer Name"

  if [[ "$PROMPT_COMPUTER_NAME" == "true" ]]; then
    # Get current computer name
    local current_name
    current_name=$(scutil --get ComputerName 2>/dev/null || echo "Not set")

    log_info "Current computer name: $current_name"

    if ask_yes_no "Would you like to configure the computer name?" "n"; then
      log_info ""
      log_info "Enter the desired computer name (or press Enter to keep current):"
      log_info "This will set:"
      log_info "  • ComputerName: User-friendly name shown in System Settings"
      log_info "  • LocalHostName: Bonjour hostname (name.local)"
      log_info "  • HostName: Fully qualified domain name"
      log_info ""

      read -r -p "Computer name [$current_name]: " new_name

      # Use current name if user pressed Enter
      new_name="${new_name:-$current_name}"

      if [[ -n "$new_name" ]] && [[ "$new_name" != "$current_name" ]]; then
        # Trim whitespace
        new_name=$(echo "$new_name" | xargs)

        # Validate length (max 63 chars per RFC 1123)
        if [[ ${#new_name} -gt 63 ]]; then
          log_error "Computer name too long (max 63 characters). Current length: ${#new_name}"
          log_info "Please run the setup again with a shorter name."
          return 1
        fi

        # Validate character set (RFC 1123 compliant: alphanumeric, space, dot, underscore, hyphen)
        # Must start with alphanumeric character
        if [[ ! "$new_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9\ \._-]{0,62}$ ]]; then
          log_error "Invalid characters in computer name"
          log_info "Allowed: letters, numbers, spaces, dots, underscores, hyphens"
          log_info "Must start with letter or number"
          return 1
        fi

        # Sanitize for LocalHostName (remove spaces and special chars, trim leading/trailing hyphens)
        local sanitized_name
        sanitized_name=$(echo "$new_name" | sed 's/[^a-zA-Z0-9-]/-/g' | sed 's/^-//' | sed 's/-$//')

        if [[ "$DRY_RUN" == "true" ]]; then
          log_dry_run "Would set ComputerName to: $new_name"
          log_dry_run "Would set LocalHostName to: $sanitized_name"
          log_dry_run "Would set HostName to: $sanitized_name"
        else
          log_info "Setting computer name (requires sudo)..."

          # Acquire sudo once upfront
          if ! sudo -v 2>/dev/null; then
            log_error "Failed to acquire sudo privileges"
            return 1
          fi

          # Set system names using helper function
          set_system_name "ComputerName" "$new_name" || return 1
          set_system_name "LocalHostName" "$sanitized_name" || return 1
          set_system_name "HostName" "$sanitized_name" || return 1
        fi
      else
        log_info "Keeping current computer name: $current_name"
      fi
    else
      log_info "Skipping computer name configuration"
    fi
  fi

  # Restart affected services
  if [[ "$RESTART_SERVICES" == "true" ]]; then
    log_subsection "Restarting Services"

    log_info "Restarting Dock, Finder, and SystemUIServer..."

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would restart: Dock, Finder, SystemUIServer"
    else
      killall Dock 2>/dev/null || true
      killall Finder 2>/dev/null || true
      killall SystemUIServer 2>/dev/null || true

      log_success "Services restarted"
    fi
  fi

  log_success "macOS defaults configuration completed"
  log_info "Some changes may require logging out and back in to take full effect"

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_macos_defaults
fi
