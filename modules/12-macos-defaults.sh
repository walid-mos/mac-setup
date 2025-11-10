#!/usr/bin/env bash

# =============================================================================
# Module 11: macOS Defaults
# =============================================================================
# Configure macOS system preferences.
# =============================================================================

module_12_macos_defaults() {
  log_section "Module 11: Configuring macOS Defaults"

  if [[ "$APPLY_MACOS_DEFAULTS" != "true" ]]; then
    log_info "Skipping macOS defaults (APPLY_MACOS_DEFAULTS=false)"
    return 0
  fi

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

  # Table view size mode (file info display)
  set_macos_default "NSGlobalDomain" "NSTableViewDefaultSizeMode" "int" "1"
  log_info "Table view default size mode set to small"

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
    log_info "Disabling Gatekeeper quarantine for downloaded apps..."

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would run: sudo spctl --master-disable"
    else
      if ask_yes_no "This requires sudo. Disable Gatekeeper?" "y"; then
        sudo spctl --master-disable || log_warning "Failed to disable Gatekeeper"
      fi
    fi
  fi

  if [[ "$SYSTEM_FAST_KEY_REPEAT" == "true" ]]; then
    set_macos_default "-g" "ApplePressAndHoldEnabled" "bool" "false"
    log_info "Disabled press-and-hold for fast key repeat"
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
  module_12_macos_defaults
fi
