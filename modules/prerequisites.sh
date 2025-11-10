#!/usr/bin/env bash

# =============================================================================
# Prerequisites Module
# =============================================================================
# Install Xcode Command Line Tools and other system prerequisites.
# =============================================================================

module_prerequisites() {
  log_section "Prerequisites: Installing Xcode Command Line Tools"

  # Check if Xcode CLI tools are already installed
  if xcode-select -p &>/dev/null; then
    log_success "Xcode Command Line Tools are already installed"
    local xcode_path
    xcode_path="$(xcode-select -p)"
    log_info "Installation path: $xcode_path"
    return 0
  fi

  log_info "Installing Xcode Command Line Tools..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would install Xcode Command Line Tools"
    return 0
  fi

  # Trigger Xcode CLI installation
  log_info "This will open a dialog to install Xcode Command Line Tools"
  log_info "Please follow the on-screen instructions"

  xcode-select --install 2>/dev/null || {
    log_warning "xcode-select --install failed (may already be installed)"
  }

  # Wait for installation to complete
  log_progress "Waiting for Xcode Command Line Tools installation to complete..."
  log_info "The script will continue once installation is detected"

  local timeout=600  # 10 minutes timeout
  local elapsed=0
  local check_interval=5

  while ! xcode-select -p &>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
      log_error_exit "Timeout waiting for Xcode Command Line Tools installation"
    fi

    sleep $check_interval
    ((elapsed += check_interval))

    if [[ $((elapsed % 30)) -eq 0 ]]; then
      log_progress "Still waiting... ($elapsed seconds elapsed)"
    fi
  done

  log_success "Xcode Command Line Tools installed successfully"

  # Verify git is now available
  if command_exists git; then
    local git_version
    git_version="$(git --version)"
    log_success "$git_version is now available"
  else
    log_error_exit "Git not found after Xcode CLI installation"
  fi

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_prerequisites
fi
